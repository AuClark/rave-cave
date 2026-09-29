#!/usr/bin/env python3
"""Sektor5 generative visuals: control host on :8110.

A sketch is a GLSL content() function (sketches/NAME.glsl) plus its parameter
schema (sketches/NAME.json). The projector renders it on any surface whose
content is "gen"; this service holds the live parameter values and pushes every
change to the projector and to the control page.

  /                 control page (sliders, randomise, presets, live preview)
  /render.js        the projector's renderer, reused for the preview
  /api/events       Server-Sent Events: {"t":"sketch"}, {"t":"params"}, {"t":"state"} ~20x/s,
                    {"t":"wave"} once per track (the live track's waveform, see trackwave.py)
  /api/wave         GET the current waveform message
  /api/sketch       GET the active sketch (name, schema, glsl)
  /api/sketches     GET sketch names
  /api/sketches/NAME  GET any sketch (schema, glsl) with its values, for a projection surface that
                    shows it: live if it's active, else as last left; ?preset=P applies a preset
  /api/params       GET current values; POST {"id": value, ...} to change some
  /api/select       POST {"sketch": NAME} to switch sketch
  /api/presets      GET preset names for the active sketch (?sketch=NAME for another one)
  /api/presets/NAME GET a preset; POST saves current values as NAME; POST .../NAME/load
  /api/transition   GET the transition settings (and the types); POST {"type", "beats", "sync",
                    "presets"} to change them. Switching sketch (and loading a preset, if
                    "presets") hands over through a transition, synced to the beat.
  /api/next         POST: mix to another sketch (random, with one of its presets) through a transition

Live values and presets live in state/ next to this file (not in git). Presets can also ship
with a sketch in sketches/presets/NAME/ (in git); one saved on the brain with the same name wins.

    python3 visuals.py [port]
"""
import hashlib
import json
import queue
import random
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

import s5auth
from pathlib import Path

import trackwave

HERE = Path(__file__).resolve().parent
WEB = HERE / "web"
SKETCHES = HERE / "sketches"
STATE = HERE / "state"
RENDER_JS = HERE.parent / "projector" / "web" / "render.js"   # brain/projector in the repo, ~/projector on the Pi
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8110
SHOWBRAIN = "http://127.0.0.1:8090/api/state"
DECKDASH = "http://127.0.0.1:8080"
STATE_HZ = 20
SAFE_NAME = re.compile(r"^[A-Za-z0-9 _.-]{1,40}$")

lock = threading.Lock()
clients = []            # queue.Queue per connected page
sketch = None           # {"name", "title", "about", "groups", "glsl"}
values = {}             # param id -> float
last_state = b"null"
wave = None             # the live track's waveform message (trackwave.py)

# Transitions (render.js draws them). Each type is a shader mode; "auto" picks one that suits the
# song section showbrain is in, and a length for it; "cut" is an instant change on the sync point.
TRANS_TYPES = ["crossfade", "wipe", "iris", "dissolve", "luma", "tiles", "slices", "zoom", "swirl",
               "stutter", "flash", "pixelate"]
TRANS_BEATS = {"crossfade": 8, "dissolve": 8, "luma": 8, "wipe": 4, "iris": 4, "tiles": 4, "slices": 4,
               "zoom": 4, "swirl": 4, "pixelate": 4, "stutter": 2, "flash": 1, "cut": 0}
TRANS_AUTO = [   # (song sections, the types that suit them, beats)
    (("DROP", "PREDROP"), ["flash", "stutter", "zoom"], None),
    (("BUILD", "HOLD"), ["zoom", "swirl", "pixelate", "tiles"], 4),
    (("BREAKDOWN", "INTRO", "OUTRO", "PAUSED", "IDLE"), ["dissolve", "luma", "crossfade", "iris"], 16),
]
TRANS_GROOVE = ["wipe", "iris", "tiles", "slices", "dissolve", "pixelate", "swirl"]
transition = {"type": "auto", "beats": 0, "sync": "bar", "presets": True}   # beats 0 = the type's own
last_type = None


def code_version():
    """Changes whenever the control page or the shared renderer changes (a deploy), so pages reload."""
    h = hashlib.sha1()
    for f in sorted([*WEB.rglob("*"), RENDER_JS]):
        if f.is_file():
            st = f.stat()
            h.update(f"{f.name}{st.st_mtime_ns}{st.st_size}".encode())
    return h.hexdigest()[:12]


def log(msg):
    print(time.strftime("%X"), msg, flush=True)


def sketch_names():
    return sorted(p.stem for p in SKETCHES.glob("*.glsl") if (SKETCHES / f"{p.stem}.json").is_file())


def params_of(sk):
    return [p for g in sk["groups"] for p in g["params"]]


def clamp_values(sk, d, base):
    out = dict(base)
    for p in params_of(sk):
        if p["id"] in d:
            try:
                out[p["id"]] = max(p["min"], min(p["max"], float(d[p["id"]])))
            except (TypeError, ValueError):
                pass
    return out


def defaults(sk):
    return {p["id"]: float(p["default"]) for p in params_of(sk)}


def load_sketch(name):
    meta = json.loads((SKETCHES / f"{name}.json").read_text())
    meta.update(name=name, glsl=(SKETCHES / f"{name}.glsl").read_text())
    return meta


def select(name):
    """Make NAME the active sketch, restoring its last values."""
    global sketch, values
    sk = load_sketch(name)
    saved = {}
    try:
        saved = json.loads((STATE / f"{name}.current.json").read_text())
    except (OSError, ValueError):
        pass
    sketch, values = sk, clamp_values(sk, saved, defaults(sk))
    (STATE / "active").write_text(name)


def save_transition():
    (STATE / "transition.json").write_text(json.dumps(transition, indent=1))


def scene_now():
    try:
        return (json.loads(last_state) or {}).get("scene") or "GROOVE"
    except ValueError:
        return "GROOVE"


def make_trans(override=None):
    """The transition message for a change now: its type (auto picks one for the song section,
    not the same as last time), length in beats, sync point and a seed. None for an instant change."""
    global last_type
    t = dict(transition, **(override or {}))
    kind, beats = t.get("type", "auto"), float(t.get("beats") or 0)
    if kind == "none":
        return None
    if kind == "auto":
        scene = scene_now()
        pool, auto_beats = TRANS_GROOVE, None
        for scenes, types, b in TRANS_AUTO:
            if scene in scenes:
                pool, auto_beats = types, b
        choices = [x for x in pool if x != last_type] or pool
        kind = random.choice(choices)
        if not beats:
            beats = auto_beats or TRANS_BEATS[kind]
    if not beats:
        beats = TRANS_BEATS.get(kind, 4)
    last_type = kind
    if kind == "cut":
        return {"type": "cut", "mode": 0, "beats": 0, "sync": t.get("sync", "bar"), "seed": random.random()}
    return {"type": kind, "mode": TRANS_TYPES.index(kind), "beats": beats, "sync": t.get("sync", "bar"),
            "seed": random.random()}


def switch(name, preset=None, override=None):
    """Make NAME live (optionally with one of its presets) and tell every page, with a transition."""
    global values
    with lock:
        select(name)
        if preset:
            f = preset_file(preset)
            if f.is_file():
                values = clamp_values(sketch, json.loads(f.read_text()), defaults(sketch))
                save_values()
        sk, snap = sketch, dict(values)
        tr = make_trans(override)
    broadcast({"t": "sketch", "sketch": sk, "trans": tr})
    broadcast({"t": "params", "params": snap})
    return tr


def save_values():
    (STATE / f"{sketch['name']}.current.json").write_text(json.dumps(values, indent=1))


def push(data):
    with lock:
        for q in list(clients):
            try:
                q.put_nowait(data)
            except queue.Full:
                pass


def broadcast(obj):
    push(("data: " + json.dumps(obj, separators=(",", ":")) + "\n\n").encode())


def live_player():
    """showbrain's live deck, from the last state we polled."""
    try:
        return (json.loads(last_state) or {}).get("live")
    except ValueError:
        return None


def set_wave(msg):
    global wave
    wave = msg
    log(f"waveform: {msg['source']} {msg.get('title')!r} ({msg['beats']} beats)")
    broadcast({"t": "wave", "wave": msg})


def state_pump():
    """Poll showbrain for the preview's beat clock, only while someone is watching."""
    global last_state
    while True:
        t0 = time.time()
        if clients:
            try:
                with urllib.request.urlopen(SHOWBRAIN, timeout=0.3) as r:
                    last_state = r.read()
                payload = b'{"t":"state","s":' + last_state + b"}"
            except Exception:
                payload = b'{"t":"state","s":null}'
            push(b"data: " + payload + b"\n\n")
        time.sleep(max(0.0, 1 / STATE_HZ - (time.time() - t0)))


def preset_dir(sk_name=None):
    d = STATE / "presets" / (sk_name or sketch["name"])
    d.mkdir(parents=True, exist_ok=True)
    return d


def preset_names(sk_name=None):
    """Saved presets plus the ones shipped with the sketch in git (sketches/presets/NAME/)."""
    shipped = SKETCHES / "presets" / (sk_name or sketch["name"])
    return sorted({p.stem for d in (preset_dir(sk_name), shipped) for p in d.glob("*.json")})


def preset_file(name, sk_name=None):
    """A preset saved on the brain wins over a shipped one of the same name."""
    f = preset_dir(sk_name) / f"{name}.json"
    return f if f.is_file() else SKETCHES / "presets" / (sk_name or sketch["name"]) / f"{name}.json"


def values_for(name, preset=None):
    """A sketch's values for a projection surface that shows it (not necessarily the active one):
    the live values if it's active, else as it was last left on the control page, or its defaults;
    then a preset on top, if one is given."""
    sk = sketch if name == sketch["name"] else load_sketch(name)
    if name == sketch["name"]:
        vals = dict(values)
    else:
        try:
            vals = clamp_values(sk, json.loads((STATE / f"{name}.current.json").read_text()), defaults(sk))
        except (OSError, ValueError):
            vals = defaults(sk)
    if preset and SAFE_NAME.match(preset):
        f = preset_file(preset, name)
        if f.is_file():
            vals = clamp_values(sk, json.loads(f.read_text()), vals)
    return sk, vals


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")    # the projector page on :8100 reads these
        super().end_headers()

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        if s5auth.handle(self):
            return
        path = self.path.split("?", 1)[0]
        if path == "/api/events":
            return self._events()
        if path == "/render.js":
            body = RENDER_JS.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        with lock:
            if path == "/api/sketch":
                return self._json(200, sketch)
            if path == "/api/wave":
                return self._json(200 if wave else 404, wave or {"error": "no waveform yet"})
            if path == "/api/sketches":
                return self._json(200, {"sketches": sketch_names(), "active": sketch["name"]})
            if path == "/api/params":
                return self._json(200, values)
            if path == "/api/presets":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                name = (q.get("sketch") or [None])[0]
                if name and name not in sketch_names():
                    return self._json(404, {"error": "no such sketch"})
                return self._json(200, {"presets": preset_names(name)})
            if path == "/api/transition":
                return self._json(200, {"settings": transition, "types": ["auto", "cut"] + TRANS_TYPES + ["none"],
                                        "last": last_type})
            # Any sketch, for a projection surface that shows it: definition + values (?preset=NAME)
            m = re.match(r"^/api/sketches/([^/]+)$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                if name not in sketch_names():
                    return self._json(404, {"error": "no such sketch"})
                preset = (urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("preset") or [None])[0]
                sk, vals = values_for(name, preset)
                return self._json(200, {"sketch": sk, "values": vals})
            m = re.match(r"^/api/presets/([^/]+)$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                f = preset_file(name)
                if SAFE_NAME.match(name) and f.is_file():
                    return self._json(200, json.loads(f.read_text()))
                return self._json(404, {"error": "no such preset"})
        return super().do_GET()

    def do_POST(self):
        global values
        if s5auth.handle(self) or not s5auth.guard(self):
            return
        path = self.path.split("?", 1)[0]
        try:
            if path == "/api/params":
                d = self._body()
                with lock:
                    values = clamp_values(sketch, d, values)
                    save_values()
                    snap = dict(values)
                broadcast({"t": "params", "params": snap})
                return self._json(200, {"ok": True})
            if path == "/api/select":
                d = self._body()
                name = d.get("sketch", "")
                if name not in sketch_names():
                    return self._json(404, {"error": "no such sketch"})
                tr = switch(name, d.get("preset"), d.get("transition"))
                return self._json(200, {"ok": True, "trans": tr})
            if path == "/api/next":
                d = self._body()
                others = [n for n in sketch_names() if n != sketch["name"]] or sketch_names()
                name = random.choice(others)
                shipped = sorted(p.stem for p in (SKETCHES / "presets" / name).glob("*.json"))
                tr = switch(name, random.choice(shipped) if shipped else None, d.get("transition"))
                return self._json(200, {"ok": True, "sketch": name, "trans": tr})
            if path == "/api/transition":
                d = self._body()
                with lock:
                    if d.get("type") in ["auto", "cut", "none"] + TRANS_TYPES:
                        transition["type"] = d["type"]
                    if "beats" in d:
                        transition["beats"] = max(0.0, min(64.0, float(d["beats"])))
                    if d.get("sync") in ("now", "beat", "bar", "phrase"):
                        transition["sync"] = d["sync"]
                    if "presets" in d:
                        transition["presets"] = bool(d["presets"])
                    save_transition()
                    snap = dict(transition)
                broadcast({"t": "transition", "settings": snap})
                return self._json(200, {"ok": True, "settings": snap})
            m = re.match(r"^/api/presets/([^/]+?)(/load)?$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                if not SAFE_NAME.match(name):
                    return self._json(400, {"error": "bad name"})
                tr = None
                with lock:
                    if m.group(2):
                        f = preset_file(name)
                        if not f.is_file():
                            return self._json(404, {"error": "no such preset"})
                        values = clamp_values(sketch, json.loads(f.read_text()), defaults(sketch))
                        save_values()
                        snap = dict(values)
                        tr = make_trans() if transition.get("presets") else None
                    else:
                        (preset_dir() / f"{name}.json").write_text(json.dumps(values, indent=1))
                        snap = None
                if snap is not None:
                    broadcast({"t": "params", "params": snap, "trans": tr})
                return self._json(200, {"ok": True})
        except (ValueError, KeyError, TypeError) as e:
            return self._json(400, {"error": str(e)})
        self._json(404, {"error": "not found"})

    def _events(self):
        q = queue.Queue(maxsize=60)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        with lock:
            clients.append(q)
            first = ("data: " + json.dumps({"t": "hello", "version": code_version()}) + "\n\n"
                     "data: " + json.dumps({"t": "sketch", "sketch": sketch}) + "\n\n"
                     "data: " + json.dumps({"t": "params", "params": values}) + "\n\n"
                     "data: " + json.dumps({"t": "transition", "settings": transition}) + "\n\n"
                     + ("data: " + json.dumps({"t": "wave", "wave": wave}) + "\n\n" if wave else "")).encode()
        try:
            self.wfile.write(first)
            self.wfile.flush()
            while True:
                try:
                    data = q.get(timeout=15)
                except queue.Empty:
                    data = b": keep-alive\n\n"
                self.wfile.write(data)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with lock:
                if q in clients:
                    clients.remove(q)


if __name__ == "__main__":
    STATE.mkdir(exist_ok=True)
    names = sketch_names()
    try:
        active = (STATE / "active").read_text().strip()
    except OSError:
        active = ""
    select(active if active in names else names[0])
    try:
        transition.update(json.loads((STATE / "transition.json").read_text()))
    except (OSError, ValueError):
        pass
    threading.Thread(target=state_pump, daemon=True).start()
    trackwave.Follower(DECKDASH, STATE, live_player, set_wave).start()
    log(f"visuals up on :{PORT} (sketch {sketch['name']}; {len(names)} available)")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
