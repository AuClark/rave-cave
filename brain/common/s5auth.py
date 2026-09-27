"""Admin PIN for the Sektor5 rig's Python services (showbrain, projector, visuals).

Anyone can look; changing anything (POST) needs admin. Entering the PIN once gives the browser a
signed cookie (s5_admin) valid for 5 years. The cookie is per host, not per port, so one unlock
covers every page on the same address. deckdash (Java) implements the same scheme in Auth.java.

The PIN hash and signing key live in /srv/rave/auth.json (group rave, mode 640), written by
brain/tools/set_pin.py. With no auth file, auth is off and everyone is admin.

Usage in a BaseHTTPRequestHandler:
    if s5auth.handle(self): return          # serves GET/POST /api/auth and /api/auth/logout
    if not s5auth.guard(self): return       # at the top of do_POST: 401 unless admin
"""
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
from pathlib import Path

AUTH_FILE = Path(os.environ.get("S5_AUTH_FILE", "/srv/rave/auth.json"))
COOKIE = "s5_admin"
MAX_AGE = 5 * 365 * 86400
FAIL_WINDOW, FAIL_LIMIT, LOCKOUT = 600, 8, 600

_lock = threading.Lock()
_cache = {"mtime": None, "data": None}
_fails = []
_locked_until = 0.0


def _load():
    try:
        m = AUTH_FILE.stat().st_mtime
    except OSError:
        _cache.update(mtime=None, data=None)
        return None
    if m != _cache["mtime"]:
        try:
            _cache.update(mtime=m, data=json.loads(AUTH_FILE.read_text()))
        except (OSError, ValueError):
            _cache.update(mtime=m, data=None)
    return _cache["data"]


def enabled():
    d = _load()
    return bool(d and d.get("pin_hash") and d.get("key"))


def _sign(key_hex, msg):
    return hmac.new(bytes.fromhex(key_hex), msg.encode(), hashlib.sha256).hexdigest()


def make_token():
    d = _load()
    ts = int(time.time())
    return f"v1.{ts}.{_sign(d['key'], f'v1.{ts}')}"


def valid_token(tok):
    d = _load()
    if not d or not tok:
        return False
    try:
        ver, ts, sig = tok.split(".")
        ts = int(ts)
    except ValueError:
        return False
    if ver != "v1" or not hmac.compare_digest(sig, _sign(d["key"], f"v1.{ts}")):
        return False
    return int(d.get("not_before", 0)) <= ts <= time.time() + 60 and time.time() - ts < MAX_AGE


def check_pin(pin):
    d = _load()
    if not d:
        return False
    h = hashlib.pbkdf2_hmac("sha256", str(pin).encode(), bytes.fromhex(d["salt"]), int(d["iterations"])).hex()
    return hmac.compare_digest(h, d["pin_hash"])


def cookie(headers):
    for part in (headers.get("Cookie") or "").split(";"):
        k, _, v = part.strip().partition("=")
        if k == COOKIE:
            return v
    return None


def is_admin(headers):
    return (not enabled()) or valid_token(cookie(headers))


def _reply(handler, code, obj, set_cookie=None):
    body = json.dumps(obj).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(body)))
    if set_cookie:
        handler.send_header("Set-Cookie", set_cookie)
    handler.end_headers()
    handler.wfile.write(body)


def _cookie_header(value, max_age):
    secure = "; Secure" if handler_is_https.get() else ""
    return f"{COOKIE}={value}; Path=/; Max-Age={max_age}; HttpOnly; SameSite=Lax{secure}"


class _Https(threading.local):
    def get(self):
        return getattr(self, "v", False)


handler_is_https = _Https()


def handle(handler):
    """Serve the auth endpoints. Returns True if the request was handled."""
    global _locked_until
    path = handler.path.split("?", 1)[0]
    if path not in ("/api/auth", "/api/auth/logout"):
        return False
    handler_is_https.v = (handler.headers.get("X-Forwarded-Proto") or "").lower() == "https"
    method = handler.command
    if method == "GET" and path == "/api/auth":
        _reply(handler, 200, {"enabled": enabled(), "admin": is_admin(handler.headers)})
        return True
    if method != "POST":
        _reply(handler, 405, {"error": "POST only"})
        return True
    if path == "/api/auth/logout":
        _reply(handler, 200, {"ok": True, "admin": not enabled()}, _cookie_header("", 0))
        return True
    if not enabled():
        _reply(handler, 200, {"ok": True, "enabled": False, "admin": True})
        return True
    now = time.time()
    with _lock:
        _fails[:] = [t for t in _fails if now - t < FAIL_WINDOW]
        if now < _locked_until:
            _reply(handler, 429, {"error": "too many attempts", "retry_s": int(_locked_until - now)})
            return True
    try:
        n = int(handler.headers.get("Content-Length", 0))
        pin = json.loads(handler.rfile.read(n) or b"{}").get("pin", "")
    except (ValueError, AttributeError):
        pin = ""
    if pin and check_pin(pin):
        with _lock:
            _fails.clear()
        _reply(handler, 200, {"ok": True, "admin": True}, _cookie_header(make_token(), MAX_AGE))
        return True
    with _lock:
        _fails.append(now)
        if len(_fails) >= FAIL_LIMIT:
            _locked_until = now + LOCKOUT
    time.sleep(0.5)
    _reply(handler, 401, {"error": "wrong PIN"})
    return True


def guard(handler, allow=()):
    """For mutating requests: True if allowed, else sends 401 and returns False."""
    path = handler.path.split("?", 1)[0]
    if path in allow or is_admin(handler.headers):
        return True
    _reply(handler, 401, {"error": "admin PIN required", "view_only": True})
    return False


def new_auth_file(pin, iterations=200_000):
    """Contents for a fresh auth.json (used by brain/tools/set_pin.py)."""
    salt = secrets.token_hex(16)
    return {"version": 1, "iterations": iterations, "salt": salt,
            "pin_hash": hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(salt), iterations).hex(),
            "key": secrets.token_hex(32), "not_before": 0, "set_at": int(time.time())}
