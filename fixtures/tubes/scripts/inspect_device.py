"""Dump advertisement + GATT table for a BLE device by name prefix.

    ~/.venvs/ble/bin/python fixtures/tubes/scripts/inspect_device.py SPB-
"""
import asyncio
import sys

from bleak import BleakClient, BleakScanner

PREFIX = sys.argv[1] if len(sys.argv) > 1 else "SPB-"


async def main():
    found = asyncio.get_running_loop().create_future()

    def on_adv(d, adv):
        name = d.name or adv.local_name or ""
        if name.startswith(PREFIX) and not found.done():
            found.set_result((d, adv))

    async with BleakScanner(detection_callback=on_adv):
        d, adv = await asyncio.wait_for(found, 90)
    print("NAME", d.name or adv.local_name, "ADDR", d.address, "RSSI", adv.rssi)
    print("MFR ", {k: v.hex() for k, v in adv.manufacturer_data.items()})
    print("SVCS", adv.service_uuids)
    print("SDATA", {k: v.hex() for k, v in adv.service_data.items()})
    async with BleakClient(d, timeout=20) as c:
        for s in c.services:
            print("SVC", s.uuid, s.description)
            for ch in s.characteristics:
                val = ""
                if "read" in ch.properties:
                    try:
                        val = (await c.read_gatt_char(ch)).hex()
                    except Exception as e:
                        val = f"ERR {e}"
                print("  CHR", ch.uuid, ch.properties, val)


asyncio.run(main())
