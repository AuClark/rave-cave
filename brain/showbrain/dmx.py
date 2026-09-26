"""DMX output through an anyma uDMX (USB 16c0:05dc, libusb vendor control transfers).

Protocol (see docs/fixtures/parcan.md): bmRequestType 0x40, bRequest 2 =
SetChannelRange, wValue = channel count, wIndex = first channel (0-based),
data = values. The uDMX keeps outputting the last values it was sent.

Sending happens on a background thread so a slow or failing USB transfer never
stalls the show loop. Transient I/O errors (~1 in 10 at high rates) are
ignored; the device is reopened after repeated failures or if it's unplugged.
"""
import threading
import time

try:
    import usb.core
except ImportError:          # lets the engine run (without DMX) on machines without pyusb
    usb = None


class UDMX:
    VID, PID = 0x16C0, 0x05DC

    def __init__(self, channels=512, name="udmx"):
        self.name = name
        self.frame = bytearray(channels)
        self.sent = None
        self.dev = None
        self.fails = 0
        self.lock = threading.Lock()
        self.wake = threading.Event()
        self.last_send = 0.0
        self.status = "starting"
        threading.Thread(target=self._run, daemon=True).start()

    def set(self, values, start=1):
        """values: iterable of 0..255 starting at DMX channel `start` (1-based)."""
        with self.lock:
            for i, v in enumerate(values):
                self.frame[start - 1 + i] = max(0, min(255, int(v)))
        self.wake.set()

    def _open(self):
        if usb is None:
            self.status = "pyusb missing"
            return None
        dev = usb.core.find(idVendor=self.VID, idProduct=self.PID)
        self.status = "connected" if dev is not None else "not found"
        return dev

    def _run(self):
        while True:
            self.wake.wait(0.5)
            self.wake.clear()
            if self.dev is None:
                self.dev = self._open()
                if self.dev is None:
                    time.sleep(1)
                    continue
            with self.lock:
                used = max((i + 1 for i, v in enumerate(self.frame) if v), default=0)
                used = max(used, len(self.sent or b""))
                data = bytes(self.frame[:used])
            # Resend when changed, and at least once a second as a keep-alive.
            if data == self.sent and time.time() - self.last_send < 1.0:
                continue
            if not data:
                continue
            try:
                self.dev.ctrl_transfer(0x40, 2, len(data), 0, data, 200)
                self.sent, self.last_send, self.fails = data, time.time(), 0
                self.status = "connected"
            except Exception as e:
                self.fails += 1
                if self.fails >= 20 or "No such device" in str(e):
                    self.dev, self.status = None, f"reconnecting ({e})"
                self.wake.set()      # retry promptly
