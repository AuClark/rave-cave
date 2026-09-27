#!/usr/bin/env python3
"""Rave Cave projector host.

Serves the projection-mapping page (web/) on :8100 for the projector's Chrome,
and proxies showbrain's live state at /api/state so the page stays same-origin.

    python3 projector.py            # port 8100
    python3 projector.py 8101       # another port
"""
import sys
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB = Path(__file__).resolve().parent / "web"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8100
SHOWBRAIN = "http://127.0.0.1:8090/api/state"


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_GET(self):
        if self.path.startswith("/api/state"):
            try:
                with urllib.request.urlopen(SHOWBRAIN, timeout=0.5) as r:
                    body, code = r.read(), 200
            except Exception as e:
                body, code = f'{{"error": "showbrain unreachable: {e}"}}'.encode(), 503
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()


if __name__ == "__main__":
    print(f"projector up on :{PORT}, serving {WEB}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
