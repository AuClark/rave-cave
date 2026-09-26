#!/usr/bin/env python3
"""Send DMX values through an anyma uDMX. Usage: dmx.py v1 v2 ... (starting at channel 1)"""
import sys, usb.core, usb.backend.libusb1
be = usb.backend.libusb1.get_backend(find_library=lambda x: "/opt/homebrew/lib/libusb-1.0.dylib")
dev = usb.core.find(idVendor=0x16c0, idProduct=0x05dc, backend=be)
if dev is None: sys.exit("uDMX not found")
vals = bytes(int(v) for v in sys.argv[1:])
start = 0
# cmd_SetChannelRange = 2; wValue = count, wIndex = first channel (0-based)
n = dev.ctrl_transfer(0x40, 2, len(vals), start, vals, 1000)
print(f"sent {n} channels: {list(vals)}")
