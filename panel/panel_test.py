#!/usr/bin/env python3
"""HUB75 panel health test for ONE 32x16 panel (chain of 1) via ledcat.

Steps (each announced on stdout with a timestamp):
  1-3  full red / green / blue          -> dead colour channel, whole-panel faults
  4    full white                       -> power / brightness sag
  5-7  top half then bottom half, R G B -> R1G1B1 vs R2G2B2 data lines
  8    row walk (white, one row at a time)         -> row address lines A/B/C
  9    column walk per colour (one column at a time) -> driver chip channels
 10    checkerboard                     -> shorts between neighbouring lines

    python3 panel_test.py [--step N] [--hold S] [--brightness B] [--chain C]
"""
import argparse
import os
import subprocess
import sys
import time

W, H = 32, 16
LEDCAT = os.path.expanduser("~/rpi-rgb-led-matrix/examples-api-use/ledcat")
R, G, B, WH = (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)


def frame(fn, w):
    out = bytearray()
    for y in range(H):
        for x in range(w):
            out += bytes(fn(x, y))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", type=int, default=0, help="run only this step (0 = all)")
    ap.add_argument("--hold", type=float, default=4.0, help="seconds per static step")
    ap.add_argument("--brightness", type=int, default=40)
    ap.add_argument("--chain", type=int, default=1)
    a = ap.parse_args()
    w = W * a.chain

    cat = subprocess.Popen([LEDCAT, "--led-gpio-mapping=adafruit-hat", "--led-slowdown-gpio=2",
                            "--led-rows=16", "--led-cols=32", f"--led-chain={a.chain}",
                            f"--led-brightness={a.brightness}", "--led-no-hardware-pulse", "--led-no-drop-privs"],
                           stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def show(f, secs):
        end = time.time() + secs
        while time.time() < end:
            cat.stdin.write(f)
            cat.stdin.flush()
            time.sleep(0.05)

    def say(n, msg):
        print(f"{time.strftime('%X')}  step {n}: {msg}", flush=True)

    steps = []
    steps.append((1, "FULL RED", lambda: show(frame(lambda x, y: R, w), a.hold)))
    steps.append((2, "FULL GREEN", lambda: show(frame(lambda x, y: G, w), a.hold)))
    steps.append((3, "FULL BLUE", lambda: show(frame(lambda x, y: B, w), a.hold)))
    steps.append((4, "FULL WHITE", lambda: show(frame(lambda x, y: WH, w), a.hold)))

    def halves(c, name):
        def run():
            print(f"           top half {name} ...", flush=True)
            show(frame(lambda x, y: c if y < 8 else (0, 0, 0), w), a.hold)
            print(f"           bottom half {name} ...", flush=True)
            show(frame(lambda x, y: c if y >= 8 else (0, 0, 0), w), a.hold)
        return run
    steps.append((5, "RED: top half, then bottom half", halves(R, "red")))
    steps.append((6, "GREEN: top half, then bottom half", halves(G, "green")))
    steps.append((7, "BLUE: top half, then bottom half", halves(B, "blue")))

    def rows():
        for r in range(H):
            print(f"           row {r}", flush=True)
            show(frame(lambda x, y: WH if y == r else (0, 0, 0), w), 0.6)
    steps.append((8, f"ROW WALK: white rows 0..{H - 1}, top to bottom", rows))

    def cols():
        for c, name in ((R, "red"), (G, "green"), (B, "blue")):
            print(f"           {name} columns 0..{w - 1}, left to right", flush=True)
            for col in range(w):
                show(frame(lambda x, y: c if x == col else (0, 0, 0), w), 0.25)
    steps.append((9, "COLUMN WALK: red, then green, then blue", cols))

    steps.append((10, "CHECKERBOARD (white/black), then inverted",
                  lambda: (show(frame(lambda x, y: WH if (x + y) % 2 else (0, 0, 0), w), a.hold),
                           show(frame(lambda x, y: (0, 0, 0) if (x + y) % 2 else WH, w), a.hold))))

    try:
        for n, name, run in steps:
            if a.step and n != a.step:
                continue
            say(n, name)
            run()
        say("-", "done (panel blank)")
        show(frame(lambda x, y: (0, 0, 0), w), 0.5)
    finally:
        cat.stdin.close()
        cat.wait(timeout=5)


if __name__ == "__main__":
    sys.exit(main())
