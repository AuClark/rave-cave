#!/usr/bin/env python3
"""Sektor5 projector host: projection mapping on :8100.

  /                 the output page, opened full-screen in Chrome on the projector
  /edit             the mapping editor, for a phone or laptop
  /api/events       Server-Sent Events: {"t":"state"} ~25x/s; with ?frames=1 also {"t":"frames"}
                    (showbrain's output frames, each once: the Stage view plays them back) (showbrain state) and
                    {"t":"layout"} whenever the layout changes
  /api/state        showbrain state (one-off)
  /api/layout       GET current layout; POST a new layout (saved and pushed live)
  /api/layouts      GET preset names
  /api/layouts/NAME GET a preset; POST saves the current layout as NAME;
                    POST .../NAME/load makes it current
  /api/stage        GET / POST the 3D stage design (stage.html): fixtures, positions, links to
                    real fixtures. Saved as layouts/stage.json; broadcast as {"t":"stage"}
  /stage.html       3D stage visualiser and designer (three.js in web/vendor)
  /api/screen       POST from the output page: {"w","h"} (its real resolution) plus stats
                    {"fps","scale","gpu"} every few seconds, shown in the editor

Layouts live in layouts/ next to this file (not in git): current.json plus presets.

    python3 projector.py [port]
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
LAYOUTS = HERE / "layouts"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8100
SHOWBRAIN = "http://127.0.0.1:8090/api/state"
STATE_HZ = 25

DEFAULT_LAYOUT = {
    "version": 1,
    "edit": False,          # show handles on the projector
    "test": False,          # global test pattern
    "selected": None,
    "lead_ms": 60,          # latency compensation for this projector
    "brightness": 1.0,
    "render_scale": 0,      # 0 = auto (drop resolution to keep the frame rate up), else 0.25..1
    "surfaces": [
        {"id": "s1", "name": "Wall", "content": "show", "opacity": 1.0, "hue_shift": 0.0,
         "corners": [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]]},
    ],
    "masks": [],
}
CONTENTS = {"show", "pulse", "tunnel", "bars", "title", "solid", "test", "gen"}   # gen: sketch from visuals :8110

lock = threading.Lock()
clients = []            # queue.Queue per connected page
frame_clients = set()   # the ones that asked for output frames (/api/events?frames=1: the Stage view)
layout = None
screen = {"w": 1920, "h": 1080}
last_state = b"null"


def code_version():
    """Changes whenever a page file changes, so open pages know to reload after a deploy."""
    h = hashlib.sha1()
    for f in sorted(WEB.rglob("*")):
        if f.is_file():
            st = f.stat()
            h.update(f"{f.name}{st.st_mtime_ns}{st.st_size}".encode())
    return h.hexdigest()[:12]


def log(msg):
    print(time.strftime("%X"), msg, flush=True)


def coord(v):
    return max(-0.5, min(1.5, float(v)))     # a little overscan allowed for alignment


def clean_layout(d):
    """Validate and normalise a layout coming from the editor."""
    out = json.loads(json.dumps(DEFAULT_LAYOUT))
    for k in ("edit", "test"):
        if k in d:
            out[k] = bool(d[k])
    out["selected"] = d.get("selected") if isinstance(d.get("selected"), str) else None
    out["lead_ms"] = int(max(0, min(500, d.get("lead_ms", out["lead_ms"]))))
    out["brightness"] = float(max(0.0, min(1.0, d.get("brightness", out["brightness"]))))
    rs = float(d.get("render_scale", 0) or 0)
    out["render_scale"] = 0 if rs <= 0 else max(0.25, min(1.0, rs))
    surfaces = []
    for s in d.get("surfaces", [])[:32]:
        c = s.get("corners", [])
        if len(c) != 4:
            continue
        surfaces.append({
            "id": str(s.get("id") or f"s{len(surfaces) + 1}")[:24],
            "name": str(s.get("name", ""))[:40],
            "content": s.get("content") if s.get("content") in CONTENTS else "show",
            "opacity": float(max(0.0, min(1.0, s.get("opacity", 1.0)))),
            "hue_shift": float(max(-1.0, min(1.0, s.get("hue_shift", 0.0)))),
            "radius": float(max(0.0, min(0.5, s.get("radius", 0.0)))),              # corner radius, surface heights
            "border": float(max(0.0, min(0.15, s.get("border", 0.0)))),             # border band width
            "border_bright": float(max(0.0, min(2.0, s.get("border_bright", 1.0)))),
            "border_sat": float(max(0.0, min(1.0, s.get("border_sat", 0.0)))),      # 0 white .. 1 show colour
            "border_pulse": float(max(0.0, min(1.0, s.get("border_pulse", 0.0)))),  # beat flash on the border
            "corners": [[coord(x), coord(y)] for x, y in c],
        })
    out["surfaces"] = surfaces
    masks = []
    for m in d.get("masks", [])[:32]:
        pts = m.get("points", [])
        if len(pts) >= 3:
            masks.append({"id": str(m.get("id") or f"m{len(masks) + 1}")[:24],
                          "points": [[coord(x), coord(y)] for x, y in pts[:64]]})
    out["masks"] = masks
    return out


def load_layout():
    global layout
    LAYOUTS.mkdir(exist_ok=True)
    try:
        layout = clean_layout(json.loads((LAYOUTS / "current.json").read_text()))
    except (OSError, ValueError):
        layout = clean_layout(DEFAULT_LAYOUT)


def save_layout():
    (LAYOUTS / "current.json").write_text(json.dumps(layout, indent=1))


def push(data, only=None):
    with lock:
        for q in list(clients if only is None else only):
            try:
                q.put_nowait(data)
            except queue.Full:
                pass


def broadcast(obj):
    push(("data: " + json.dumps(obj, separators=(",", ":")) + "\n\n").encode())


def state_pump():
    """Poll showbrain and push its state to every connected page. Its recent output frames go
    separately, each frame once, only to pages that asked for them (they're most of the bytes)."""
    global last_state
    last_frame_t = 0.0
    while True:
        t0 = time.time()
        new = []
        try:
            with urllib.request.urlopen(SHOWBRAIN, timeout=0.3) as r:
                s = json.loads(r.read())
            frames = s.pop("frames", None) or []
            s.pop("preview", None)                         # per-LED colours: the frames stream carries them
            last_state = json.dumps(s, separators=(",", ":")).encode()
            payload = b'{"t":"state","s":' + last_state + b"}"
            if frames and frames[-1][0] < last_frame_t - 5:
                last_frame_t = 0.0                         # showbrain's clock jumped back (no RTC)
            new = [f for f in frames if f[0] > last_frame_t]
            if new:
                last_frame_t = new[-1][0]
        except Exception:
            payload = b'{"t":"state","s":null}'
        push(b"data: " + payload + b"\n\n")
        if new and frame_clients:
            push(b"data: " + json.dumps({"t": "frames", "f": new}, separators=(",", ":")).encode() + b"\n\n", only=frame_clients)
        time.sleep(max(0.0, 1 / STATE_HZ - (time.time() - t0)))


SAFE_NAME = re.compile(r"^[A-Za-z0-9 _.-]{1,40}$")


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
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
        if path == "/api/state":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(last_state)))
            self.end_headers()
            self.wfile.write(last_state)
            return
        if path == "/api/layout":
            with lock:
                return self._json(200, dict(layout, screen=screen))
        if path == "/api/layouts":
            names = sorted(p.stem for p in LAYOUTS.glob("*.json") if p.stem != "current")
            return self._json(200, {"presets": names})
        m = re.match(r"^/api/layouts/([^/]+)$", path)
        if m:
            name = urllib.parse.unquote(m.group(1))
            f = LAYOUTS / f"{name}.json"
            if SAFE_NAME.match(name) and f.is_file():
                return self._json(200, json.loads(f.read_text()))
            return self._json(404, {"error": "no such preset"})
        if path == "/api/stage":
            f = LAYOUTS / "stage.json"
            return self._json(200, json.loads(f.read_text()) if f.is_file() else {"fixtures": None})
        if path == "/edit":
            self.path = "/edit.html"
        if path == "/stage":
            self.path = "/stage.html"
        return super().do_GET()

    def do_POST(self):
        global layout, screen
        path = self.path.split("?", 1)[0]
        try:
            if path == "/api/layout":
                with lock:
                    layout = clean_layout(self._body())
                    save_layout()
                    snap = dict(layout)
                broadcast({"t": "layout", "layout": snap})
                return self._json(200, {"ok": True})
            if path == "/api/stage":
                d = self._body()
                if not isinstance(d.get("fixtures"), list) or len(d["fixtures"]) > 200:
                    return self._json(400, {"error": "fixtures must be a list (max 200)"})
                body = json.dumps(d)
                if len(body) > 500_000:
                    return self._json(400, {"error": "stage design too large"})
                LAYOUTS.mkdir(exist_ok=True)
                with lock:
                    (LAYOUTS / "stage.json").write_text(body)
                broadcast({"t": "stage", "stage": d})
                return self._json(200, {"ok": True})
            if path == "/api/screen":
                d = self._body()
                screen = {"w": int(d.get("w", 1920)), "h": int(d.get("h", 1080))}
                for k in ("fps", "scale"):
                    if k in d:
                        screen[k] = round(float(d[k]), 2)
                if "gpu" in d:
                    screen["gpu"] = str(d["gpu"])[:80]
                broadcast({"t": "screen", "screen": screen})
                return self._json(200, {"ok": True})
            m = re.match(r"^/api/layouts/([^/]+?)(/load)?$", path)
            if m:
                name = urllib.parse.unquote(m.group(1))
                if not SAFE_NAME.match(name) or name == "current":
                    return self._json(400, {"error": "bad name"})
                f = LAYOUTS / f"{name}.json"
                if m.group(2):
                    if not f.is_file():
                        return self._json(404, {"error": "no such preset"})
                    with lock:
                        layout = clean_layout(json.loads(f.read_text()))
                        save_layout()
                        snap = dict(layout)
                    broadcast({"t": "layout", "layout": snap})
                else:
                    with lock:
                        f.write_text(json.dumps(layout, indent=1))
                return self._json(200, {"ok": True})
        except (ValueError, KeyError, TypeError) as e:
            return self._json(400, {"error": str(e)})
        self._json(404, {"error": "not found"})

    def _events(self):
        wants_frames = "frames=1" in self.path
        q = queue.Queue(maxsize=150 if wants_frames else 60)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        with lock:
            clients.append(q)
            if wants_frames:
                frame_clients.add(q)
            first = ("data: " + json.dumps({"t": "hello", "version": code_version()}) + "\n\n"
                     "data: " + json.dumps({"t": "layout", "layout": layout}) + "\n\n"
                     "data: " + json.dumps({"t": "screen", "screen": screen}) + "\n\n").encode()
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
                frame_clients.discard(q)


if __name__ == "__main__":
    load_layout()
    threading.Thread(target=state_pump, daemon=True).start()
    log(f"projector up on :{PORT} ({len(layout['surfaces'])} surfaces), serving {WEB}")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
