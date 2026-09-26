"""DDP output (UDP 4048), with frames split across packets.

Works for WLED devices and the rave-box panel receiver. Frames are lists of
(r, g, b) floats 0..1; `send` scales by brightness and packs 8-bit RGB.
"""
import socket
import threading
import time

MAX_PAYLOAD = 1440          # multiple of 3, fits comfortably in one Ethernet/Wi-Fi frame


class DDPOutput:
    def __init__(self, host, count, port=4048, brightness=1.0, name=None):
        # Hostnames (e.g. rave-tube-1.local) are resolved once, then refreshed every 30 s in the
        # background, so a changed IP is picked up without a per-frame DNS/mDNS lookup.
        self.host, self.port = host, port
        self.addr = None
        self._resolve()
        threading.Thread(target=self._refresh, daemon=True).start()
        self.count = count
        self.brightness = brightness
        self.name = name or host
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.seq = 0

    def _resolve(self):
        try:
            self.addr = (socket.gethostbyname(self.host), self.port)
        except OSError:
            pass                     # keep the last good address (or None until first success)

    def _refresh(self):
        while True:
            time.sleep(30 if self.addr else 3)
            self._resolve()

    def send_array(self, rgb):
        """rgb: numpy float array (..., 3) in 0..1, pixel order already flattened row-major."""
        import numpy as np
        a = np.clip(rgb.reshape(-1, 3)[: self.count] * (255 * self.brightness), 0, 255).astype(np.uint8)
        self.send_raw(a.tobytes())

    def send(self, pixels):
        k = 255 * self.brightness
        data = bytearray(self.count * 3)
        for i, (r, g, b) in enumerate(pixels[: self.count]):
            j = i * 3
            data[j] = max(0, min(255, int(r * k)))
            data[j + 1] = max(0, min(255, int(g * k)))
            data[j + 2] = max(0, min(255, int(b * k)))
        self.send_raw(bytes(data))

    def send_raw(self, data):
        if self.addr is None:
            return
        self.seq = (self.seq % 15) + 1
        for off in range(0, len(data), MAX_PAYLOAD):
            chunk = data[off: off + MAX_PAYLOAD]
            last = off + MAX_PAYLOAD >= len(data)
            header = bytes([0x41 if last else 0x40, self.seq, 0x01, 0x01]) + off.to_bytes(4, "big") + len(chunk).to_bytes(2, "big")
            try:
                self.sock.sendto(header + chunk, self.addr)
            except OSError:
                pass
