"""Passive Pro DJ Link listener: decode device announcements and beat packets.

Receive-only -- it never sends anything onto the DJ network, so it can't
disturb the players. Binds UDP 50000 (keep-alive announcements) and 50001
(beats, mixer on-air) and prints what it hears.

Packet layouts follow Deep Symmetry's protocol analysis ("dysentery"):
https://djl-analysis.deepsymmetry.org/

    python3 brain/tools/prodj_listen.py [seconds]
"""
import select
import socket
import sys
import time

MAGIC = b"Qspt1WmJOL"


def name_at(pkt, off):
    return pkt[off:off + 20].split(b"\x00", 1)[0].decode("ascii", "replace")


def listen(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    return s


def main(duration):
    socks = {listen(50000): 50000, listen(50001): 50001}
    devices, beats, other = {}, {}, {}
    end = time.time() + duration
    while time.time() < end:
        ready, _, _ = select.select(list(socks), [], [], 0.5)
        for s in ready:
            pkt, (src, _) = s.recvfrom(2048)
            if not pkt.startswith(MAGIC) or len(pkt) < 0x20:
                continue
            port, kind = socks[s], pkt[0x0a]
            if port == 50000 and kind == 0x06 and len(pkt) >= 0x30:
                num = pkt[0x24]
                if num not in devices:
                    mac = ":".join(f"{b:02x}" for b in pkt[0x26:0x2c])
                    ip = ".".join(str(b) for b in pkt[0x2c:0x30])
                    devices[num] = (name_at(pkt, 0x0c), ip, mac)
                    print(f"{time.strftime('%X')}  device #{num:<3} {devices[num][0]:<20} {ip:<16} {mac}", flush=True)
            elif port == 50001 and kind == 0x28 and len(pkt) >= 0x5d:
                num = pkt[0x21]
                pitch = (int.from_bytes(pkt[0x55:0x58], "big") - 0x100000) / 0x100000 * 100
                bpm = int.from_bytes(pkt[0x5a:0x5c], "big") / 100
                bar = pkt[0x5c]
                first = num not in beats
                beats[num] = beats.get(num, 0) + 1
                if first or beats[num] % 16 == 0:
                    print(f"{time.strftime('%X')}  beat  #{num:<3} {name_at(pkt, 0x0b):<20} "
                          f"track {bpm:6.2f} BPM  pitch {pitch:+5.2f}%  "
                          f"effective {bpm * (1 + pitch / 100):6.2f}  beat {bar}/4", flush=True)
            else:
                key = (port, kind)
                if key not in other:
                    print(f"{time.strftime('%X')}  other packet port {port} type 0x{kind:02x} "
                          f"len {len(pkt)} from {src} ({name_at(pkt, 0x0b)!r})", flush=True)
                other[key] = other.get(key, 0) + 1
    print("\nSummary:")
    for num, (name, ip, mac) in sorted(devices.items()):
        print(f"  #{num:<3} {name:<20} {ip:<16} {mac}  beats heard: {beats.get(num, 0)}")
    for (port, kind), n in sorted(other.items()):
        print(f"  other: port {port} type 0x{kind:02x} x{n}")


if __name__ == "__main__":
    main(float(sys.argv[1]) if len(sys.argv) > 1 else 20)
