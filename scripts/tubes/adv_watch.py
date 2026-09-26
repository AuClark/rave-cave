"""Log every change in what nearby strong BLE devices advertise.

Use it to see whether a button press / power-up combo puts the tube into a
different mode (new name, new manufacturer data, new service UUIDs).

    ~/.venvs/ble/bin/python scripts/tubes/adv_watch.py [seconds] [min_rssi]
"""
import asyncio
import sys
import time

from bleak import BleakScanner

MIN_RSSI = int(sys.argv[2]) if len(sys.argv) > 2 else -75

state = {}


def on_adv(device, adv):
    if adv.rssi < MIN_RSSI:
        return
    snap = (
        device.name or adv.local_name,
        tuple(sorted((k, v.hex()) for k, v in adv.manufacturer_data.items())),
        tuple(sorted(adv.service_uuids)),
        tuple(sorted((k, v.hex()) for k, v in adv.service_data.items())),
    )
    if state.get(device.address) != snap:
        state[device.address] = snap
        name, mfr, svcs, sdata = snap
        print(f"{time.strftime('%X')} rssi={adv.rssi:4} {name}  mfr={dict(mfr)}  "
              f"svcs={list(svcs)}  sdata={dict(sdata)}  ({device.address})", flush=True)


async def main(duration):
    async with BleakScanner(detection_callback=on_adv):
        await asyncio.sleep(duration)


asyncio.run(main(float(sys.argv[1]) if len(sys.argv) > 1 else 180))
