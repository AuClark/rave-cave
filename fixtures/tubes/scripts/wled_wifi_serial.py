"""Give a USB-connected WLED board Wi-Fi credentials over serial (Improv protocol).

WLED listens for Improv Serial packets, the same thing install.wled.me uses
after flashing. Handy when a board lands on a new network.

    ~/.venvs/ble/bin/python fixtures/tubes/scripts/wled_wifi_serial.py [port]

Reads RAVE_WIFI_SSID / RAVE_WIFI_PASSWORD from the environment or the repo's .env
(git-ignored, see .env.example). Passing "SSID" "password" [port] still works.

Prints the device URL WLED reports once it joins.
"""
import os
import sys
import time
from pathlib import Path

import serial

HEADER = b"IMPROV\x01"
TYPE_STATE, TYPE_ERROR, TYPE_RPC, TYPE_RESULT = 0x01, 0x02, 0x03, 0x04
CMD_WIFI = 0x01
STATES = {0x02: "ready", 0x03: "provisioning", 0x04: "provisioned"}
ERRORS = {0x01: "invalid packet", 0x02: "unknown command", 0x03: "unable to connect", 0xFF: "unknown"}


def load_env():
    """Read KEY=VALUE lines from the repo-root .env into os.environ (existing values win)."""
    root = next((p for p in Path(__file__).resolve().parents if (p / ".env.example").exists()), None)
    env = root / ".env" if root else None
    if env and env.is_file():
        for line in env.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def packet(ptype, data):
    body = HEADER + bytes([ptype, len(data)]) + data
    return body + bytes([sum(body) & 0xFF])


def wifi_rpc(ssid, password):
    s, p = ssid.encode(), password.encode()
    data = bytes([len(s)]) + s + bytes([len(p)]) + p
    return packet(TYPE_RPC, bytes([CMD_WIFI, len(data)]) + data)


def read_packets(buf):
    """Yield (type, data) for complete Improv packets in buf; return the leftover."""
    out = []
    while True:
        i = buf.find(HEADER)
        if i < 0 or len(buf) < i + 9:
            return out, buf[max(0, len(buf) - 16):] if i < 0 else buf[i:]
        ln = buf[i + 8]
        end = i + 9 + ln + 1
        if len(buf) < end:
            return out, buf[i:]
        out.append((buf[i + 7], buf[i + 9:i + 9 + ln]))
        buf = buf[end:]


def main():
    load_env()
    args = sys.argv[1:]
    if len(args) >= 2 and not args[0].startswith("/dev/"):
        ssid, password, args = args[0], args[1], args[2:]
    else:
        ssid, password = os.environ.get("RAVE_WIFI_SSID"), os.environ.get("RAVE_WIFI_PASSWORD")
    if not ssid or password is None:
        sys.exit("Set RAVE_WIFI_SSID and RAVE_WIFI_PASSWORD in .env (see .env.example)")
    port = args[0] if args else "/dev/cu.usbserial-0001"
    s = serial.Serial()
    s.port, s.baudrate, s.timeout = port, 115200, 0.2
    s.dtr = s.rts = False          # don't reset the board on open
    s.open()
    time.sleep(0.5)
    s.write(wifi_rpc(ssid, password))
    buf, deadline = b"", time.time() + 30
    while time.time() < deadline:
        buf += s.read(512)
        pkts, buf = read_packets(buf)
        for ptype, data in pkts:
            if ptype == TYPE_STATE:
                print("state:", STATES.get(data[0], data[0]))
            elif ptype == TYPE_ERROR and data and data[0]:
                print("error:", ERRORS.get(data[0], data[0]))
                return 1
            elif ptype == TYPE_RESULT:
                # [cmd, len, (strlen, str)*]
                strings, j = [], 2
                while j < len(data):
                    n = data[j]
                    strings.append(data[j + 1:j + 1 + n].decode(errors="replace"))
                    j += 1 + n
                print("joined:", ", ".join(strings) or "(no URL reported)")
                return 0
    print("timed out waiting for WLED to report a connection")
    return 2


if __name__ == "__main__":
    sys.exit(main())
