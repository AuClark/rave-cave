#!/usr/bin/env python3
"""Rave Cave generative visuals: control host on :8110.

A sketch is a GLSL content() function (sketches/NAME.glsl) plus its parameter
schema (sketches/NAME.json). The projector renders it on any surface whose
content is "gen"; this service holds the live parameter values and pushes every
change to the projector and to the control page.

  /                 control page (sliders, randomise, presets, live preview)
  /render.js        the projector's renderer, reused for the preview
  /api/events       Server-Sent Events: {"t":"sketch"}, {"t":"params"}, {"t":"state"} ~20x/s
  /api/sketch       GET the active sketch (name, schema, glsl)
  /api/sketches     GET sketch names
  /api/params       GET current values; POST {"id": value, ...} to change some
  /api/select       POST {"sketch": NAME} to switch sketch
  /api/presets      GET preset names for the active sketch
  /api/presets/NAME GET a preset; POST saves current values as NAME; POST .../NAME/load

Live values and presets live in state/ next to this file (not in git).

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
from pathlib import Path

HERE = Path(__file__).resolve().parent
WEB = HERE / "web"
SKETCHES = HERE / "sketches"
STATE = HERE / "state"
RENDER_JS = HERE.parent / "projector" / "web" / "render.js"   # brain/projector in the repo, ~/projector on the Pi
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8110
SHOWBRAIN = "http://127.0.0.1:8090/api/state"
STATE_HZ = 20
SAFE_NAME = re.compile(r"^[A-Za-z0-9 _.-]{1,40}$")

lock = threading.Lock()
clients = []            # queue.Queue per connected page
sketch = None           # {"name", "title", "about", "groups", "glsl"}
values = {}             # param id -> float
last_state = b"null"


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


def preset_dir():
    d = STATE / "presets" / sketch["name"]
    d.mkdir(parents=True, exist_ok=True)
    return d


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
            if path == "/api/sketches":
                return self._json(200, {"sketches": sketch_names(), "active": sketch["name"]})
            if path == "/api/params":
                return self._json(200, values)
            if path == "/api/presets":
                return self._json(200, {"presets": sorted(p.stem for p in preset_dir().glob("*.json"))})
            m = re.match(r"^/api/presets/([^/]+)$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                f = preset_dir() / f"{name}.json"
                if SAFE_NAME.match(name) and f.is_file():
                    return self._json(200, json.loads(f.read_text()))
                return self._json(404, {"error": "no such preset"})
        return super().do_GET()

    def do_POST(self):
        global values
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
                name = self._body().get("sketch", "")
                if name not in sketch_names():
                    return self._json(404, {"error": "no such sketch"})
                with lock:
                    select(name)
                    sk, snap = sketch, dict(values)
                broadcast({"t": "sketch", "sketch": sk})
                broadcast({"t": "params", "params": snap})
                return self._json(200, {"ok": True})
            m = re.match(r"^/api/presets/([^/]+?)(/load)?$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                if not SAFE_NAME.match(name):
                    return self._json(400, {"error": "bad name"})
                with lock:
                    f = preset_dir() / f"{name}.json"
                    if m.group(2):
                        if not f.is_file():
                            return self._json(404, {"error": "no such preset"})
                        values = clamp_values(sketch, json.loads(f.read_text()), defaults(sketch))
                        save_values()
                        snap = dict(values)
                    else:
                        f.write_text(json.dumps(values, indent=1))
                        snap = None
                if snap is not None:
                    broadcast({"t": "params", "params": snap})
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
                     "data: " + json.dumps({"t": "params", "params": values}) + "\n\n").encode()
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
    log(f"visuals up on :{PORT} (sketch {sketch['name']}; {len(names)} available)")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
