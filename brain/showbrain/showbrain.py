#!/usr/bin/env python3
"""Rave Cave show brain: read-ahead lighting driven by the decks.

Inputs:  deckdash feed (UDP 127.0.0.1:9100: beats + 20 Hz status) and
         per-track timelines (http://127.0.0.1:8080/api/timeline/N).
Outputs: DDP frames to every configured fixture (WLED tube, HUB75 panel...).
Control: Commander page + JSON API on :8090.

Scene flow (see docs/show-engine.md):
  IDLE -> INTRO/GROOVE <-> BREAKDOWN -> BUILD (-> HOLD while looping)
       -> PRE-DROP (blackout, last beat) -> DROP -> GROOVE ... -> OUTRO

    python3 brain/showbrain/showbrain.py [config.json]
"""
import bisect
import colorsys
import json
import math
import random
import socket
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from ddp import DDPOutput
from dmx import UDMX
import looks

HERE = Path(__file__).parent
import envcfg
envcfg.load_env()
CONFIG = json.loads(envcfg.expand((Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "config.json").read_text()))


# ---------------------------------------------------------------- deck feed

class Decks:
    """Latest deck status and beat events from deckdash, plus track timelines."""

    def __init__(self):
        self.lock = threading.Lock()
        self.status = {}        # player -> dict (+ "_rx" local receive time)
        self.master = 0
        self.beats = {}         # player -> (rx_time, bwb, bpm)
        self.mixer = None       # latest DJM message from brain/mixer (+ "_rx")
        self.timelines = {}     # ref -> timeline dict
        self.fetching = set()
        threading.Thread(target=self._listen, daemon=True).start()

    def _listen(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("127.0.0.1", CONFIG.get("feed_port", 9100)))
        while True:
            msg = json.loads(s.recv(65536))
            now = time.time()
            with self.lock:
                if msg["t"] == "status":
                    self.master = msg.get("master", 0)
                    seen = set()
                    for p in msg["players"]:
                        p["_rx"] = now
                        self.status[p["n"]] = p
                        seen.add(p["n"])
                        ref = p.get("ref")
                        if ref and ref not in self.timelines and ref not in self.fetching:
                            self.fetching.add(ref)
                            threading.Thread(target=self._fetch, args=(p["n"], ref), daemon=True).start()
                    for n in list(self.status):
                        if n not in seen and now - self.status[n]["_rx"] > 3:
                            del self.status[n]
                elif msg["t"] == "beat":
                    self.beats[msg["player"]] = (now, msg["bwb"], msg["bpm"])
                elif msg["t"] == "mixer":
                    msg["_rx"] = now
                    self.mixer = msg

    def _fetch(self, player, ref):
        for _ in range(30):
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:8080/api/timeline/{player}", timeout=3) as r:
                    t = json.loads(r.read())
                if t.get("ref") == ref:
                    with self.lock:
                        self.timelines[ref] = t
                        self.fetching.discard(ref)
                    log(f"timeline: {t.get('title')} - drops at bars {[d['bar'] for d in t.get('drops', [])]}")
                    return
            except Exception:
                pass
            time.sleep(1)
        with self.lock:
            self.fetching.discard(ref)

    def snapshot(self):
        with self.lock:
            return dict(self.status), self.master, dict(self.beats), self.timelines

    def mixer_state(self):
        with self.lock:
            m = self.mixer
        if not m or not m.get("connected") or time.time() - m["_rx"] > 1.0:
            return None
        return m


# ---------------------------------------------------------------- helpers

def log(msg):
    print(time.strftime("%X"), msg, flush=True)


def hsv(h, s=1.0, v=1.0):
    return colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def key_hue(key):
    """Camelot key like '9B' -> hue, so each track gets its own colour."""
    try:
        return ((int(key[:-1]) - 1) / 12 + (0.04 if key[-1] in "Bb" else 0)) % 1.0
    except (TypeError, ValueError):
        return 0.83


# ---------------------------------------------------------------- engine

class Engine:
    def __init__(self, decks):
        self.decks = decks
        self.mode = "auto"              # auto | manual | blackout
        self.follow = 0                 # 0 = auto, else player number
        self.lead_ms = CONFIG.get("lead_ms", 40)
        self.intensity = CONFIG.get("intensity", 0.8)
        self.hold = False
        self.strobe = False
        self.forced = None              # {"kind": "build"|"drop", "player", "start", "drop"} in beats
        self.overrides_path = HERE / "overrides.json"
        try:
            self.overrides = json.loads(self.overrides_path.read_text())
        except (OSError, ValueError):
            self.overrides = {}         # title -> {"skip": [beats], "add": [beats]}
        self.state = {}
        self.sparks = []
        self.last_live = None
        self.frozen_progress = 0.0
        self.playing_since = {}         # player -> time it started playing (for hand-over)
        self.share_smooth = {}          # player -> smoothed share of the mix (from the DJM)
        self.dominant_since = {}        # player -> time its share went above the take-over threshold
        self.live_reason = ""
        self.outro_since = None
        self.last_beat_seen = {}        # player -> rx time of the last beat packet we measured
        self.phase_err = []             # recent (model - packet) errors in ms, for the diagnostic

    # --- position model ------------------------------------------------
    def position(self, p, t):
        """Track position in ms at time t for status p (interpolated while playing)."""
        pos = p.get("pos", -1)
        if pos is None or pos < 0:
            return None
        if p.get("playing"):
            pos += (t - p["_rx"]) * 1000 * (1 + p.get("pitch", 0) / 100)
        return pos

    @staticmethod
    def beat_at(tl, pos):
        """Fractional beat number (1-based) at track position pos, using the beat grid."""
        bm = tl["beatMs"]
        i = bisect.bisect_right(bm, pos)
        if i == 0:
            return 1.0 + (pos - bm[0]) / max(1, bm[1] - bm[0])
        if i >= len(bm):
            return float(len(bm))
        return i + (pos - bm[i - 1]) / max(1, bm[i] - bm[i - 1])

    @staticmethod
    def bar_of(tl, beat):
        fb = tl["barFirstBeat"]
        i = bisect.bisect_right(fb, int(beat))
        bar = max(1, i)
        return bar, int(beat) - fb[bar - 1] + 1    # (bar, beat within bar 1..)

    def section_of(self, p, t, timelines):
        """(section type, beat) for a deck right now, or (None, None) without a timeline."""
        tl = timelines.get(p.get("ref"))
        pos = self.position(p, t)
        if not tl or pos is None:
            return None, None
        beat = self.beat_at(tl, pos)
        sec = next((s for s in tl["sections"] if s["startBeat"] <= beat <= s["endBeat"] + 0.999), None)
        return (sec["type"] if sec else None), beat

    def mixer_pick(self, status, t):
        """Live deck from the DJM's post-fader levels. Returns a player, None (nothing audible),
        or False (no mixer data: fall back to the deck-state rules)."""
        m = self.decks.mixer_state()
        if m is None:
            return False
        cfg = CONFIG.get("mixer", {})
        chmap = {int(k): v for k, v in cfg.get("channels", {"1": 1, "2": 2}).items()}   # mixer ch -> player
        take, hold_s, alpha = cfg.get("takeover_share", 0.7), cfg.get("takeover_s", 2.0), cfg.get("smoothing", 0.15)
        silent = cfg.get("silent_db", -60.0)
        shares = {}
        for ch, player in chmap.items():
            raw = m.get("share", {}).get(f"ch{ch}", 0.0)
            if m.get("channels", {}).get(f"ch{ch}", {}).get("rms_db", -200) < silent:
                raw = 0.0
            prev = self.share_smooth.get(player, raw)
            shares[player] = prev + alpha * (raw - prev)
        self.share_smooth = shares
        if all(v < 0.05 for v in shares.values()):
            self.live_reason = "mixer: nothing audible"
            return self.last_live if self.last_live in status else None
        for player, v in shares.items():
            if v >= take:
                self.dominant_since.setdefault(player, t)
            else:
                self.dominant_since.pop(player, None)
        cur = self.last_live
        for player, since in self.dominant_since.items():
            if player != cur and player in status and t - since >= hold_s:
                self.live_reason = f"mixer: deck {player} holds {shares[player]:.0%} of the mix"
                return player
        if cur in shares and cur in status:
            self.live_reason = f"mixer: staying on deck {cur} ({shares[cur]:.0%})"
            return cur
        best = max(shares, key=shares.get)
        self.live_reason = f"mixer: deck {best} loudest"
        return best if best in status else None

    def live_deck(self, status, master, timelines=None, t=None):
        """Which deck the lights follow. Sticky: cueing or previewing another deck never steals it.

        Priority: manual follow > mixer on-air flags (if a DJM is on the link) > stay on the current
        deck while it plays > hand over when the current deck stops/ends/sits in its outro, or when
        the incoming deck hits a drop while the outgoing one is already in its outro.
        """
        timelines = timelines or {}
        t = t or time.time()
        if self.follow and self.follow in status:
            self.live_reason = "locked in Commander"
            return self.follow
        pick = self.mixer_pick(status, t)
        if pick is not False:
            return pick
        playing = {n: p for n, p in status.items() if p.get("playing")}
        on_air = [n for n, p in playing.items() if p.get("onAir")]
        self.live_reason = "deck state (no mixer data)"
        if on_air:                                   # real fader data wins when we have it
            cur = self.last_live if self.last_live in on_air else on_air[0]
            return cur
        cur = self.last_live
        if cur not in playing or status[cur].get("atEnd"):
            # Current deck stopped: take the deck that has been playing longest.
            if not playing:
                return None
            self.playing_since = {n: v for n, v in self.playing_since.items() if n in playing}
            for n in playing:
                self.playing_since.setdefault(n, t)
            return min(playing, key=lambda n: self.playing_since[n])
        for n in playing:
            self.playing_since.setdefault(n, t)
        for n in list(self.playing_since):
            if n not in playing:
                del self.playing_since[n]
        others = [n for n in playing if n != cur]
        if not others:
            return cur
        sec_cur, _ = self.section_of(status[cur], t, timelines)
        if sec_cur == "outro":
            self.outro_since = self.outro_since or t
        else:
            self.outro_since = None
        for n in others:
            sec_in, _ = self.section_of(status[n], t, timelines)
            # Incoming deck drops while outgoing is winding down: follow the drop.
            if sec_in == "drop" and sec_cur in ("outro", None):
                return n
            # Outgoing has been in its outro for 16+ s with the new deck running for 30+ s: mix is done.
            if self.outro_since and t - self.outro_since > 16 and t - self.playing_since.get(n, t) > 30:
                return n
        return cur

    # --- scene decision --------------------------------------------------
    def decide(self, t):
        status, master, beats, timelines = self.decks.snapshot()
        live = self.live_deck(status, master, timelines, t)
        ctx = {"t": t, "live": live, "scene": "IDLE", "hue": 0.83, "frac": 0.0, "bwb": 1, "bar": 0,
               "beat": 0.0, "progress": 0.0, "since_drop": 0.0, "beats_to_drop": None, "title": None,
               "bpm": 0.0, "section": None, "next_drop_bar": None,
               "section_progress": 0.0, "energy": 0.5}
        if live is None:
            self.last_live = None
            return ctx
        if live != self.last_live:
            if self.last_live is not None:
                log(f"live deck -> {live}")
            self.last_live = live
            self.forced = None
        p = status[live]
        ctx.update(title=p.get("title"), bpm=p.get("bpm", 0), hue=key_hue(p.get("key")))
        tl = timelines.get(p.get("ref"))
        pos = self.position(p, t + self.lead_ms / 1000)

        if tl is None or pos is None:
            # No timeline yet: follow beat events only.
            b = beats.get(live)
            if b:
                period = 60 / max(1, b[2])
                ctx["frac"] = ((t + self.lead_ms / 1000 - b[0]) / period) % 1.0
                ctx["bwb"] = b[1]
            ctx["scene"] = "GROOVE" if p.get("playing") else "PAUSED"
            return ctx

        beat = self.beat_at(tl, pos)
        bar, bwb = self.bar_of(tl, beat)
        ctx.update(beat=beat, frac=beat % 1.0, bar=bar, bwb=bwb)

        # Diagnostic: at each real beat packet, where did the position model think we were?
        b = beats.get(live)
        if b and p.get("playing") and b[0] != self.last_beat_seen.get(live):
            self.last_beat_seen[live] = b[0]
            mpos = self.position(p, b[0])
            if mpos is not None:
                ph = self.beat_at(tl, mpos) % 1.0
                err = (ph if ph < 0.5 else ph - 1.0) * 60000 / max(1.0, b[2])
                self.phase_err = (self.phase_err + [err])[-32:]
        cal = self.overrides.get("_calibration", [])
        if cal:
            ds = sorted(c["delta_beats"] for c in cal)
            ctx["calibration"] = {"marks": len(ds), "median_delta_beats": ds[len(ds) // 2]}
        if self.phase_err:
            srt = sorted(self.phase_err)
            ctx["phase_err_ms"] = round(srt[len(srt) // 2], 1)
        if not p.get("playing"):
            ctx["scene"] = "PAUSED"
            return ctx

        section = next((s for s in tl["sections"] if s["startBeat"] <= beat <= s["endBeat"] + 0.999), None)
        ctx["section"] = section["type"] if section else None
        if section:
            span = max(1.0, section["endBeat"] + 1 - section["startBeat"])
            ctx["section_progress"] = max(0.0, min(1.0, (beat - section["startBeat"]) / span))
        en = tl.get("energy") or []
        ctx["energy"] = en[bar - 1] / 100 if 0 < bar <= len(en) else 0.5
        drops = self.drops_for(p.get("title"), tl)
        ctx["drops"] = [{"bar": d["bar"], "manual": bool(d.get("manual"))} for d in drops]

        # Forced events from the Commander take priority.
        if self.forced and self.forced["player"] == live:
            f = self.forced
            if f["kind"] == "build" and beat < f["drop"]:
                return self._build(ctx, beat, f["start"], f["drop"], p)
            if beat - f["drop"] < CONFIG.get("drop_bars", 16) * 4:
                return self._drop(ctx, beat - f["drop"])
            self.forced = None

        if self.mode == "manual":
            ctx["scene"] = "GROOVE"
            return ctx

        nxt = next((d for d in drops if d["beat"] > beat - CONFIG.get("drop_bars", 16) * 4), None)
        if nxt:
            ctx["next_drop_bar"] = nxt["bar"]
            if beat < nxt["beat"]:
                ctx["beats_to_drop"] = nxt["beat"] - beat
            if nxt["buildStartBeat"] <= beat < nxt["beat"]:
                return self._build(ctx, beat, nxt["buildStartBeat"], nxt["beat"], p)
            if nxt["beat"] <= beat:
                return self._drop(ctx, beat - nxt["beat"])
        ctx["scene"] = {"intro": "INTRO", "breakdown": "BREAKDOWN", "outro": "OUTRO"}.get(ctx["section"], "GROOVE")
        return ctx

    def drops_for(self, title, tl):
        """Timeline drops with this track's saved overrides applied."""
        ov = self.overrides.get(title or "", {}) if title != "_calibration" else {}
        skip = set(ov.get("skip", []))
        drops = [d for d in tl["drops"] if d["beat"] not in skip]
        fb = tl["barFirstBeat"]
        for beat in ov.get("add", []):
            bar = max(1, bisect.bisect_right(fb, beat))
            start_bar = max(1, bar - 8)
            drops.append({"bar": bar, "beat": beat, "ms": 0, "confidence": 1.0, "cue": False, "manual": True,
                          "buildStartBar": start_bar, "buildStartBeat": fb[start_bar - 1]})
        return sorted(drops, key=lambda d: d["beat"])

    def save_overrides(self):
        self.overrides_path.write_text(json.dumps(self.overrides, indent=1))

    def _build(self, ctx, beat, start, drop, p):
        ctx["beats_to_drop"] = drop - beat
        if drop - beat <= 1.0:
            ctx["scene"] = "PREDROP"
            return ctx
        progress = (beat - start) / max(1.0, (drop - 1) - start)
        if p.get("looping") or self.hold:
            ctx["scene"] = "HOLD"
            progress = self.frozen_progress
        else:
            self.frozen_progress = progress
            ctx["scene"] = "BUILD"
        ctx["progress"] = max(0.0, min(1.0, progress))
        return ctx

    def _drop(self, ctx, since):
        ctx["scene"] = "DROP"
        ctx["since_drop"] = since
        return ctx

    # --- commands --------------------------------------------------------
    def command(self, c):
        cmd = c.get("cmd")
        status, master, _, timelines = self.decks.snapshot()
        live = self.last_live
        t = time.time()
        if cmd == "mode":
            self.mode = c.get("value", "auto")
        elif cmd == "follow":
            self.follow = int(c.get("value", 0))
        elif cmd == "lead_ms":
            self.lead_ms = int(c.get("value", 40))
        elif cmd == "intensity":
            self.intensity = float(c.get("value", 0.8))
        elif cmd == "hold":
            self.hold = not self.hold
        elif cmd == "strobe":
            self.strobe = bool(c.get("value", not self.strobe))
        elif cmd in ("drop_now", "build") and live:
            p = status[live]
            tl = timelines.get(p.get("ref"))
            pos = self.position(p, t)
            if tl is None or pos is None:
                return {"ok": False, "error": "no timeline for live deck"}
            beat = self.beat_at(tl, pos)
            if cmd == "drop_now":
                self.forced = {"kind": "drop", "player": live, "start": beat, "drop": beat}
            else:
                bars = int(c.get("value", 4))
                bar, _ = self.bar_of(tl, beat)
                fb = tl["barFirstBeat"]
                drop = fb[min(len(fb) - 1, bar + bars - 1)]
                self.forced = {"kind": "build", "player": live, "start": beat, "drop": drop}
        elif cmd in ("skip_drop", "mark_drop") and live:
            p = status[live]
            tl = timelines.get(p.get("ref"))
            pos = self.position(p, t)
            if not tl or pos is None:
                return {"ok": False, "error": "no timeline for live deck"}
            beat = self.beat_at(tl, pos)
            ov = self.overrides.setdefault(p.get("title") or "", {"skip": [], "add": []})
            if cmd == "skip_drop":
                nxt = next((d for d in self.drops_for(p.get("title"), tl) if d["beat"] > beat), None)
                if not nxt:
                    return {"ok": False, "error": "no drop ahead"}
                if nxt.get("manual"):
                    ov["add"].remove(nxt["beat"])
                else:
                    ov["skip"].append(nxt["beat"])
            else:
                # Snap to the nearest bar line.
                fb = tl["barFirstBeat"]
                i = bisect.bisect_left(fb, beat)
                cands = [fb[k] for k in (i - 1, i) if 0 <= k < len(fb)]
                marked = min(cands, key=lambda b: abs(b - beat))
                # Calibration: how far was the nearest automatic prediction from the real drop?
                auto = [d for d in tl["drops"] if abs(d["beat"] - marked) <= 64]
                if auto:
                    near = min(auto, key=lambda d: abs(d["beat"] - marked))
                    delta = near["beat"] - marked          # + = predicted late
                    cal = self.overrides.setdefault("_calibration", [])
                    cal.append({"title": p.get("title"), "predicted": near["beat"], "actual": marked, "delta_beats": delta})
                    log(f"calibration: predicted beat {near['beat']} vs actual {marked} ({delta:+d} beats)")
                    if near["beat"] not in ov["skip"]:
                        ov["skip"].append(near["beat"])     # replace the wrong prediction with the mark
                ov["add"].append(marked)
            self.save_overrides()
        elif cmd == "clear":
            self.forced, self.hold, self.strobe, self.mode = None, False, False, "auto"
        log(f"command {c}")
        return {"ok": True}


# ---------------------------------------------------------------- outputs

UDMX_DEVICES = {}      # one UDMX per process, shared by every DMX fixture


class Fixture:
    def __init__(self, cfg, index=0, group=1):
        self.cfg = cfg
        self.kind = cfg["kind"]             # strip | panel | dmx_par
        self.role = dict(cfg.get("role", {}), index=index, group=group)
        self.state = {}
        self.delay = cfg.get("delay_ms", 0) / 1000.0
        self.queue = []                      # (time, frame) for delay compensation
        if self.kind == "dmx_par":
            self.dmx = UDMX_DEVICES.setdefault("udmx", UDMX())
            self.addr = cfg.get("address", 1)
            self.chans = cfg["channels"]    # name -> offset (1-based within the fixture)
            self.extra = set(cfg.get("verified_extra", []))   # e.g. ["w", "uv"] once tested
            self.out = None
            return
        self.w = cfg.get("width", 128)
        self.h = cfg.get("height", 16)
        count = cfg["leds"] if self.kind == "strip" else self.w * self.h
        self.out = DDPOutput(cfg["host"], count, brightness=cfg.get("brightness", 0.6), name=cfg.get("name"))

    @property
    def always(self):
        """DMX holds its last value, so keep rendering it even when the show is idle."""
        return self.kind == "dmx_par"

    def render(self, ctx, intensity, strobe):
        if self.kind == "dmx_par":
            frame = self._par_frame(ctx, intensity, strobe)
        elif self.kind == "strip":
            px = looks.strip(ctx, self.cfg["leds"], self.role, self.state)
            if self.cfg.get("reverse"):
                px = px[::-1]
            if strobe:
                px = px * 0 + (1.0 if (ctx["t"] * 12) % 1.0 < 0.5 else 0.0)
            frame = px * intensity
        else:
            px = looks.panel(ctx, self.w, self.h, self.role, self.state)
            if strobe:
                px = px * 0 + (1.0 if (ctx["t"] * 12) % 1.0 < 0.5 else 0.0)
            frame = px * intensity
        # Delay compensation: fast outputs (USB DMX) wait so they land with the Wi-Fi fixtures.
        now = time.time()
        if self.delay > 0:
            self.queue.append((now, frame))
            while len(self.queue) > 1 and self.queue[1][0] <= now - self.delay:
                self.queue.pop(0)
            if self.queue[0][0] > now - self.delay:
                return
            frame = self.queue[0][1]
        self._send(frame)

    def _par_frame(self, ctx, intensity, strobe):
        v = looks.par(ctx, self.role, self.state)
        if strobe:
            on = 1.0 if (ctx["t"] * 12) % 1.0 < 0.5 else 0.0
            v = dict(dimmer=1.0, r=on, g=on, b=on, w=on if "w" in self.extra else 0.0, a=0.0, uv=0.0)
        k = intensity * self.cfg.get("brightness", 1.0)
        n = max(self.chans.values())
        ch = [0] * n
        for name, off in self.chans.items():
            if name == "dimmer":
                ch[off - 1] = int(255 * v["dimmer"])
            elif name in ("r", "g", "b"):
                ch[off - 1] = int(255 * min(1.0, v[name] * k))
            elif name in ("w", "a", "uv"):
                ch[off - 1] = int(255 * min(1.0, v[name] * k)) if name in self.extra else 0
            else:
                ch[off - 1] = 0             # strobe / program / speed: never let the fixture run its own programs
        return ch

    def _send(self, frame):
        if self.kind == "dmx_par":
            self.dmx.set(frame, start=self.addr)
        else:
            self.out.send_array(frame)


# ---------------------------------------------------------------- commander

def make_handler(engine):
    page = (HERE / "commander.html")

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code, body, ctype="application/json"):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith("/api/state"):
                self._send(200, json.dumps(engine.state).encode())
            else:
                self._send(200, page.read_bytes(), "text/html; charset=utf-8")

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            try:
                res = engine.command(json.loads(self.rfile.read(n) or b"{}"))
                self._send(200, json.dumps(res).encode())
            except Exception as e:
                self._send(400, json.dumps({"ok": False, "error": str(e)}).encode())
    return H


# ---------------------------------------------------------------- main

def main():
    decks = Decks()
    engine = Engine(decks)
    strips = [c for c in CONFIG["fixtures"] if c["kind"] == "strip"]
    fixtures = [Fixture(c, strips.index(c) if c in strips else 0, len(strips)) for c in CONFIG["fixtures"]]
    port = CONFIG.get("commander_port", 8090)
    threading.Thread(target=ThreadingHTTPServer(("0.0.0.0", port), make_handler(engine)).serve_forever,
                     daemon=True).start()
    log(f"showbrain up: {len(fixtures)} fixtures, commander on :{port}")
    fps = CONFIG.get("fps", 50)
    last_scene = None
    idle_since = None
    fps_meas, frames, fps_t = 0.0, 0, time.time()
    while True:
        t0 = time.time()
        frames += 1
        if t0 - fps_t >= 2:
            fps_meas, frames, fps_t = frames / (t0 - fps_t), 0, t0
        ctx = engine.decide(t0)
        if engine.mode == "blackout":
            ctx["scene"] = "PREDROP"
        engine.state = {k: v for k, v in ctx.items()} | {
            "mode": engine.mode, "follow": engine.follow, "lead_ms": engine.lead_ms,
            "intensity": engine.intensity, "hold": engine.hold, "strobe": engine.strobe,
            "forced": engine.forced, "fixtures": [f.cfg.get("name") for f in fixtures],
            "fps": round(fps_meas, 1),
            "live_reason": engine.live_reason,
            "mixer_share": {str(k): round(v, 3) for k, v in engine.share_smooth.items()},
            "dmx": {k: d.status for k, d in UDMX_DEVICES.items()}}
        if ctx["scene"] != last_scene:
            extra = f" ({ctx['beats_to_drop']:.1f} beats to drop)" if ctx.get("beats_to_drop") else ""
            log(f"scene {last_scene} -> {ctx['scene']}  deck {ctx['live']} bar {ctx['bar']}{extra}")
            last_scene = ctx["scene"]
        # IDLE: stop streaming so WLED / the panel fall back to their own idle looks.
        if ctx["scene"] == "IDLE":
            idle_since = idle_since or t0
        else:
            idle_since = None
        streaming = idle_since is None or t0 - idle_since < 0.5
        for fx in fixtures:
            if streaming or fx.always:
                fx.render(ctx, engine.intensity, engine.strobe)
        time.sleep(max(0.0, 1 / fps - (time.time() - t0)))


if __name__ == "__main__":
    main()
