#!/usr/bin/env python3
"""DDP receiver for the rave-box HUB75 panel (4x 32x16 chained = 128x16).

Listens on UDP 4048 for DDP frames (same protocol WLED uses) and pipes each
completed frame into rpi-rgb-led-matrix's `ledcat`. Pixel order: row-major,
top-left first, RGB, 128 x 16. When no stream arrives for IDLE_S seconds it
shows a dim idle animation so you can see the box is alive.

    python3 ~/panel-controller/ddp_panel.py [--brightness 50]
"""
import argparse
import colorsys
import math
import os
import socket
import subprocess
import time

W, H = 128, 16
FRAME = W * H * 3
IDLE_S = 3.0
LEDCAT = os.path.expanduser("~/rpi-rgb-led-matrix/examples-api-use/ledcat")


def start_ledcat(brightness):
    return subprocess.Popen(
        [LEDCAT, "--led-gpio-mapping=adafruit-hat", "--led-slowdown-gpio=2",
         "--led-rows=16", "--led-cols=32", "--led-chain=4",
         f"--led-brightness={brightness}", "--led-no-hardware-pulse", "--led-no-drop-privs"],
        stdin=subprocess.PIPE, bufsize=0)


def idle_frame(t):
    out = bytearray(FRAME)
    for x in range(W):
        r, g, b = colorsys.hsv_to_rgb((x / W + t * 0.05) % 1.0, 1.0, 0.12 + 0.06 * math.sin(t + x * 0.1))
        px = bytes((int(r * 255), int(g * 255), int(b * 255)))
        for y in range(H):
            i = (y * W + x) * 3
            out[i:i + 3] = px
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--brightness", type=int, default=50)
    ap.add_argument("--port", type=int, default=4048)
    args = ap.parse_args()

    cat = start_ledcat(args.brightness)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
    sock.bind(("0.0.0.0", args.port))
    sock.settimeout(0.05)
    buf = bytearray(FRAME)
    last_rx = 0.0
    last_idle = 0.0
    frames = 0
    print(f"ddp_panel: listening on UDP {args.port}, {W}x{H}", flush=True)
    while True:
        now = time.time()
        try:
            pkt = sock.recv(2048)
        except socket.timeout:
            pkt = None
        if pkt and len(pkt) >= 10:
            flags = pkt[0]
            hdr = 14 if flags & 0x10 else 10          # timecode present
            off = int.from_bytes(pkt[4:8], "big")
            ln = int.from_bytes(pkt[8:10], "big")
            data = pkt[hdr:hdr + ln]
            if off < FRAME:
                buf[off:off + len(data)] = data[:FRAME - off]
            if flags & 0x01:                          # push: frame complete
                cat.stdin.write(bytes(buf))
                last_rx = now
                frames += 1
        elif now - last_rx > IDLE_S and now - last_idle > 0.05:
            cat.stdin.write(idle_frame(now))
            last_idle = now
        if cat.poll() is not None:                    # ledcat died: restart it
            print("ledcat exited, restarting", flush=True)
            time.sleep(1)
            cat = start_ledcat(args.brightness)


if __name__ == "__main__":
    main()
