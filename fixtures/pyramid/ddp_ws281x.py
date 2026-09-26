#!/usr/bin/env python3
"""DDP receiver for the WS2815 pyramid, driven from rave-box's SPI pin (GPIO10 / pin 19).

Receives DDP frames on UDP 4048 (same protocol as WLED and the panel receiver)
and writes them to the strip with rpi_ws281x over SPI (no root needed once the
user is in the `spi` group). A current limiter scales frames down so total draw
stays under --max-amps, and a dim idle animation shows when no frames arrive.

Signal path: Pi GPIO10 -> SP901E Signal In DAT 1 -> strip DI (BI tied to GND).

    ~/pyramid-venv/bin/python ddp_ws281x.py --leds 600 --max-amps 5
"""
import argparse
import colorsys
import math
import socket
import time

from rpi_ws281x import PixelStrip, ws

IDLE_S = 3.0
MA_PER_CHANNEL = 5.0      # WS2815 @ 12 V: roughly 15 mA per pixel at full white, ~5 mA per colour channel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--leds", type=int, default=600)
    ap.add_argument("--pin", type=int, default=10, help="10 = SPI MOSI (recommended), 18 = PWM (needs root)")
    ap.add_argument("--brightness", type=int, default=255)
    ap.add_argument("--max-amps", type=float, default=5.0, help="12 V current budget for the strips")
    ap.add_argument("--order", default="GRB", choices=["GRB", "RGB", "BRG", "RBG", "GBR", "BGR"])
    ap.add_argument("--port", type=int, default=4048)
    a = ap.parse_args()

    strip = PixelStrip(a.leds, a.pin, 800000, 10, False, a.brightness, 0,
                       getattr(ws, f"WS2811_STRIP_{a.order}"))
    strip.begin()
    n = a.leds
    budget_ma = a.max_amps * 1000

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
    sock.bind(("0.0.0.0", a.port))
    sock.settimeout(0.05)
    buf = bytearray(n * 3)
    last_rx, last_idle = 0.0, 0.0
    print(f"ddp_ws281x: {n} LEDs on GPIO{a.pin}, UDP {a.port}, limit {a.max_amps} A", flush=True)

    def show(data):
        # Current limiter: estimate draw from channel values, scale the whole frame if over budget.
        total = sum(data) / 255 * MA_PER_CHANNEL
        k = min(1.0, budget_ma / total) if total > 0 else 1.0
        for i in range(n):
            r, g, b = data[i * 3], data[i * 3 + 1], data[i * 3 + 2]
            if k < 1.0:
                r, g, b = int(r * k), int(g * k), int(b * k)
            strip.setPixelColorRGB(i, r, g, b)
        strip.show()

    while True:
        now = time.time()
        try:
            pkt = sock.recv(2048)
        except socket.timeout:
            pkt = None
        if pkt and len(pkt) >= 10:
            flags = pkt[0]
            hdr = 14 if flags & 0x10 else 10
            off = int.from_bytes(pkt[4:8], "big")
            ln = int.from_bytes(pkt[8:10], "big")
            data = pkt[hdr:hdr + ln]
            if off < len(buf):
                buf[off:off + len(data)] = data[:len(buf) - off]
            if flags & 0x01:
                show(buf)
                last_rx = now
        elif now - last_rx > IDLE_S and now - last_idle > 0.04:
            idle = bytearray(n * 3)
            for i in range(n):
                r, g, b = colorsys.hsv_to_rgb((i / n + now * 0.03) % 1.0, 1.0,
                                              0.06 + 0.04 * math.sin(now + i * 0.05))
                idle[i * 3:i * 3 + 3] = bytes((int(r * 255), int(g * 255), int(b * 255)))
            show(idle)
            last_idle = now


if __name__ == "__main__":
    main()
