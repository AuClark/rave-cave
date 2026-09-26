"""Beat-synced demo reel streamed to a WLED tube over DDP (UDP 4048).

This is the same path the Pi show brain will use: we compute every pixel
ourselves and push frames; WLED just displays them. When the stream stops,
WLED falls back to its own effect after a couple of seconds.

    python3 fixtures/tubes/scripts/ddp_demo.py rave-tube-1.local [bpm] [leds]
"""
import colorsys
import math
import os
import random
import socket
import sys
import time

HOST = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RAVE_TUBE1_HOST", "rave-tube-1.local")
BPM = float(sys.argv[2]) if len(sys.argv) > 2 else 128.0
N = int(sys.argv[3]) if len(sys.argv) > 3 else 60
FPS = 60
MAX = 0.6  # global brightness cap, keeps USB power sane

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
seq = 0


def send(pixels):
    """pixels: list of (r, g, b) floats 0..1, index 0 = controller end."""
    global seq
    seq = (seq % 15) + 1
    data = bytearray()
    for r, g, b in pixels:
        data += bytes(max(0, min(255, int(c * MAX * 255))) for c in (r, g, b))
    header = bytes([0x41, seq, 0x01, 0x01, 0, 0, 0, 0, len(data) >> 8, len(data) & 0xFF])
    sock.sendto(header + data, (HOST, 4048))


def hsv(h, s=1.0, v=1.0):
    return colorsys.hsv_to_rgb(h % 1.0, s, max(0.0, min(1.0, v)))


def kick_pulse(beat, t):
    """Whole tube thumps on every beat; hue steps each bar."""
    phase = beat % 1
    level = math.exp(-phase * 5)
    hue = (int(beat) // 4) * 0.13
    return [hsv(hue + i / N * 0.08, 1, level) for i in range(N)]


def comet(beat, t):
    """A comet shoots up then down, one pass per beat."""
    phase = beat % 1
    up = int(beat) % 2 == 0
    head = phase * (N + 12) if up else (1 - phase) * (N + 12) - 12
    hue = beat * 0.05
    out = []
    for i in range(N):
        d = (head - i) if up else (i - head)
        v = math.exp(-d / 4) if d >= 0 else 0
        out.append(hsv(hue - d * 0.01, 1 - 0.6 * math.exp(-d), v))
    return out


def plasma(beat, t):
    """Flowing sine plasma, brightness pumps on the beat like a sidechain."""
    pump = 0.35 + 0.65 * (1 - math.exp(-(beat % 1) * 4))
    out = []
    for i in range(N):
        x = i / N
        h = 0.5 * math.sin(x * 6 + t * 1.3) + 0.5 * math.sin(x * 3.1 - t * 0.7)
        out.append(hsv(0.6 + h * 0.25, 1, pump))
    return out


def build_and_drop(beat, t, start):
    """4-bar build: fill rises, snare strobe accelerates; then a white hit and
    a fast rainbow scroll for the drop."""
    b = beat - start
    if b < 16:
        fill = b / 16
        rate = 1 if b < 8 else 2 if b < 12 else 4 if b < 14 else 8
        strobe = 1.0 if (b * rate) % 1 < 0.35 else 0.15
        lit = int(fill * N)
        return [hsv(0.95 - fill * 0.2, 1 - fill * 0.8, strobe) if i < lit else (0, 0, 0)
                for i in range(N)]
    d = b - 16
    if d < 0.25:
        return [(1, 1, 1)] * N
    flash = math.exp(-(d % 1) * 6)
    return [hsv(i / N + d * 0.5, 1, 0.5 + 0.5 * flash) for i in range(N)]


sparks = []


def sparkle(beat, t):
    """Random white sparks over a deep purple bed; bursts on each beat."""
    global sparks
    if int(beat * 4) != int((beat - 1 / FPS * BPM / 60) * 4):
        sparks += [[random.randrange(N), 1.0] for _ in range(6 if beat % 1 < 0.25 else 2)]
    bed = [hsv(0.78, 1, 0.25) for _ in range(N)]
    for s in sparks:
        i, v = s
        r, g, bl = bed[i]
        bed[i] = (max(r, v), max(g, v), max(bl, v))
        s[1] *= 0.85
    sparks = [s for s in sparks if s[1] > 0.05]
    return bed


SCENES = [  # (name, beats)
    ("KICK PULSE", 16),
    ("COMET", 16),
    ("PLASMA + SIDECHAIN PUMP", 16),
    ("SPARKLE", 16),
    ("BUILD ... AND DROP", 32),
]


def main():
    spb = 60 / BPM
    t0 = time.time()
    scene_start = 0
    for name, beats in SCENES:
        print(f"{time.strftime('%X')}  {name}  ({beats} beats @ {BPM:g} BPM)", flush=True)
        while True:
            t = time.time() - t0
            beat = t / spb
            if beat >= scene_start + beats:
                break
            if name.startswith("KICK"):
                frame = kick_pulse(beat, t)
            elif name == "COMET":
                frame = comet(beat, t)
            elif name.startswith("PLASMA"):
                frame = plasma(beat, t)
            elif name == "SPARKLE":
                frame = sparkle(beat, t)
            else:
                frame = build_and_drop(beat, t, scene_start)
            send(frame)
            time.sleep(1 / FPS)
        scene_start += beats
    send([(0, 0, 0)] * N)
    print("done", flush=True)


if __name__ == "__main__":
    main()
