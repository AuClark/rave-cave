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
  /api/auto         GET per-parameter automation; POST {"id": {...}, ...} to change some
  /api/text         GET the words sketches can draw; POST {"text": "ONE|TWO"} to change them
  /api/select       POST {"sketch": NAME} to switch sketch
  /api/presets      GET preset names for the active sketch (?sketch=NAME for another one)
  /api/presets/NAME GET a preset; POST saves current values as NAME; POST .../NAME/load

Live values and presets live in state/ next to this file (not in git). Presets can also ship
with a sketch in sketches/presets/NAME/ (in git); one saved on the brain with the same name wins.

    python3 visuals.py [port]
"""
import hashlib
import json
import queue
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
auto = {}               # param id -> automation settings (see AUTO_KEYS)
auto_freeze = False     # hold every automated value where it is (the page's Freeze)
text = "SEKTOR5"        # words for sketches that draw type, split on | or newline (see word() in COMMON)
TEXT_MAX = 240
CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
last_state = b"null"
wave = None             # the live track's waveform message (trackwave.py)


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


# Per-parameter automation, evaluated in render.js (see the note there). Held here so it is
# shared by every page and projector, saved with the live values, and stored in presets.
# lo/hi are the range the value is allowed to move between, and double as the range Randomise
# works within; they are always clamped to the parameter's own min/max.
AUTO_KEYS = {"on": bool, "lo": float, "hi": float, "rate": float,
             "shape": int, "phase": float, "retrig": bool, "hz": bool, "duty": float}


def auto_default(p):
    return {"on": False, "lo": float(p["min"]), "hi": float(p["max"]),
            "rate": 0.25, "shape": 0, "phase": 0.0, "retrig": False, "hz": False, "duty": 0.5}


def auto_defaults(sk):
    return {p["id"]: auto_default(p) for p in params_of(sk)}


def clamp_auto(sk, d, base):
    """Merge a partial automation update in, keeping every field inside what the sketch allows."""
    out = {k: dict(v) for k, v in base.items()}
    for p in params_of(sk):
        pid = p["id"]
        got = d.get(pid)
        if not isinstance(got, dict):
            continue
        cur = out.setdefault(pid, auto_default(p))
        for k, cast in AUTO_KEYS.items():
            if k not in got:
                continue
            try:
                cur[k] = cast(got[k]) if cast is not bool else bool(got[k])
            except (TypeError, ValueError):
                continue
        lo, hi = max(p["min"], min(p["max"], cur["lo"])), max(p["min"], min(p["max"], cur["hi"]))
        cur["lo"], cur["hi"] = min(lo, hi), max(lo, hi)
        cur["rate"] = max(0.0, min(64.0, cur["rate"]))
        cur["shape"] = max(0, min(6, cur["shape"]))
        cur["phase"] = cur["phase"] % 1.0
        cur["duty"] = max(0.02, min(0.98, cur.get("duty", 0.5)))
    return out


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


def clean_text(v):
    """Whatever the page sent, made safe to draw: no control characters, a sane length."""
    t = CTRL.sub("", str(v or "")).replace("\r", "")
    return t[:TEXT_MAX]


def split_saved(d):
    """A saved blob, old or new. Before automation existed a file was a flat {id: value}."""
    if isinstance(d, dict) and isinstance(d.get("values"), dict):
        return d["values"], d.get("auto") or {}, d.get("text")
    return (d if isinstance(d, dict) else {}), {}, None


def select(name):
    """Make NAME the active sketch, restoring its last values, automation and words."""
    global sketch, values, auto, text
    sk = load_sketch(name)
    saved = {}
    try:
        saved = json.loads((STATE / f"{name}.current.json").read_text())
    except (OSError, ValueError):
        pass
    v, a, tx = split_saved(saved)
    sketch = sk
    values = clamp_values(sk, v, defaults(sk))
    auto = clamp_auto(sk, a, auto_defaults(sk))
    if tx is not None:
        text = clean_text(tx)
    (STATE / "active").write_text(name)


def save_values():
    (STATE / f"{sketch['name']}.current.json").write_text(
        json.dumps({"_v": 2, "values": values, "auto": auto, "text": text}, indent=1))


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
        # Both of these go through split_saved: a saved blob is {"values", "auto", "text"} since
        # automation arrived, and reading one as a flat {id: value} finds no ids at all and falls
        # back to the defaults without saying so. Only the values are wanted here -- automation is
        # evaluated in render.js against the sketch the Visuals page is driving, and a surface
        # pinned to some other sketch is not that.
        try:
            saved, _, _ = split_saved(json.loads((STATE / f"{name}.current.json").read_text()))
            vals = clamp_values(sk, saved, defaults(sk))
        except (OSError, ValueError):
            vals = defaults(sk)
    if preset and SAFE_NAME.match(preset):
        f = preset_file(preset, name)
        if f.is_file():
            pv, _, _ = split_saved(json.loads(f.read_text()))
            vals = clamp_values(sk, pv, vals)
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
            if path == "/api/auto":
                return self._json(200, {"auto": auto, "freeze": auto_freeze})
            if path == "/api/text":
                return self._json(200, {"text": text})
            if path == "/api/presets":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                name = (q.get("sketch") or [None])[0]
                if name and name not in sketch_names():
                    return self._json(404, {"error": "no such sketch"})
                return self._json(200, {"presets": preset_names(name)})
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
        global values, auto, auto_freeze, text
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
            if path == "/api/auto":
                d = self._body()
                with lock:
                    if "_freeze" in d:
                        auto_freeze = bool(d["_freeze"])
                    auto = clamp_auto(sketch, d, auto)
                    save_values()
                    snap = {k: dict(v) for k, v in auto.items()}
                    frz = auto_freeze
                broadcast({"t": "auto", "auto": snap, "freeze": frz})
                return self._json(200, {"ok": True})
            if path == "/api/text":
                with lock:
                    text = clean_text(self._body().get("text", ""))
                    save_values()
                    snap = text
                broadcast({"t": "text", "text": snap})
                return self._json(200, {"ok": True})
            if path == "/api/select":
                name = self._body().get("sketch", "")
                if name not in sketch_names():
                    return self._json(404, {"error": "no such sketch"})
                with lock:
                    select(name)
                    sk, snap = sketch, dict(values)
                    asnap = {k: dict(v) for k, v in auto.items()}
                broadcast({"t": "sketch", "sketch": sk})
                broadcast({"t": "params", "params": snap})
                broadcast({"t": "auto", "auto": asnap, "freeze": auto_freeze})
                return self._json(200, {"ok": True})
            m = re.match(r"^/api/presets/([^/]+?)(/load)?$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                if not SAFE_NAME.match(name):
                    return self._json(400, {"error": "bad name"})
                with lock:
                    if m.group(2):
                        f = preset_file(name)
                        if not f.is_file():
                            return self._json(404, {"error": "no such preset"})
                        # A preset written before automation existed is a flat {id: value}; it
                        # loads with the automation back at its defaults, which is off.
                        v, a, tx = split_saved(json.loads(f.read_text()))
                        values = clamp_values(sketch, v, defaults(sketch))
                        auto = clamp_auto(sketch, a, auto_defaults(sketch))
                        if tx is not None:
                            text = clean_text(tx)
                        save_values()
                        snap = dict(values)
                        asnap = {k: dict(v2) for k, v2 in auto.items()}
                        tsnap = text
                    else:
                        (preset_dir() / f"{name}.json").write_text(
                            json.dumps({"_v": 2, "values": values, "auto": auto, "text": text}, indent=1))
                        snap = asnap = tsnap = None
                if snap is not None:
                    broadcast({"t": "params", "params": snap})
                    broadcast({"t": "auto", "auto": asnap, "freeze": auto_freeze})
                    broadcast({"t": "text", "text": tsnap})
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
                     "data: " + json.dumps({"t": "auto", "auto": auto, "freeze": auto_freeze}) + "\n\n"
                     "data: " + json.dumps({"t": "text", "text": text}) + "\n\n"
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
    threading.Thread(target=state_pump, daemon=True).start()
    trackwave.Follower(DECKDASH, STATE, live_player, set_wave).start()
    log(f"visuals up on :{PORT} (sketch {sketch['name']}; {len(names)} available)")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
