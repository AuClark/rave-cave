"""Watch which BLE devices come and go, to identify the tube.

Run it, unplug the tube for ~60 s, then plug it back in. At the end it prints
each device's longest silence; the tube is the one with a gap matching the
unplug. Unnamed devices are included (labelled by manufacturer ID / services).

    ~/.venvs/ble/bin/python fixtures/tubes/scripts/presence.py [seconds]
"""
import asyncio
import sys
import time

from bleak import BleakScanner

WINDOW = 10.0  # seconds without an advert before a device counts as gone

last_seen = {}
labels = {}
rssi = {}
longest_gap = {}
present = set()


def label(device, adv):
    name = device.name or adv.local_name
    if name:
        return name
    mfr = ",".join(f"{k:#06x}" for k in adv.manufacturer_data)
    svcs = ",".join(u[4:8] for u in adv.service_uuids)
    return f"<unnamed mfr={mfr} svc={svcs}>"


def on_adv(device, adv):
    now = time.time()
    a = device.address
    if a in last_seen:
        longest_gap[a] = max(longest_gap.get(a, 0), now - last_seen[a])
    labels[a] = label(device, adv)
    rssi[a] = adv.rssi
    last_seen[a] = now


async def main(duration):
    end = time.time() + duration
    async with BleakScanner(detection_callback=on_adv):
        while time.time() < end:
            await asyncio.sleep(1)
            now = time.time()
            live = {a for a, t in last_seen.items() if now - t < WINDOW}
            for a in live - present:
                print(f"{time.strftime('%X')}  + {labels[a]}  rssi={rssi[a]}  ({a})", flush=True)
            for a in present - live:
                print(f"{time.strftime('%X')}  - {labels[a]}  ({a})", flush=True)
            present.clear()
            present.update(live)
    print("\nLongest silence per device (strongest signal first):")
    for a in sorted(labels, key=lambda a: -rssi[a]):
        print(f"  {longest_gap.get(a, 0):6.1f}s  rssi={rssi[a]:4}  {labels[a]}  ({a})")


asyncio.run(main(float(sys.argv[1]) if len(sys.argv) > 1 else 120))
