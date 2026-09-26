"""With the tube switched OFF by its button, send 'power on' from each known
protocol family. Whichever step lights it up identifies the protocol.

    ~/.venvs/ble/bin/python scripts/tubes/test_power_on.py
"""
import asyncio
import time

from bleak import BleakClient, BleakScanner

FFF3 = "0000fff3-0000-1000-8000-00805f9b34fb"
STEPS = [
    ("1 ELK-BLEDOM on", ["7e0004f00001ff00ef"]),
    ("2 ELK 7e04 on", ["7e0404f00001ff00ef"]),
    ("3 LED Lamp 7eff on", ["7eff0401ffffffffef"]),
    ("4 Triones on", ["cc2333"]),
    ("5 Miracles Star white", ["01ffffffff0000"]),
    ("6 Miracles Star mode 1", ["010000006401 32".replace(" ", "")]),
    ("7 Zengge on", ["cc2333", "71230fa3"]),
]


async def main():
    d = await BleakScanner.find_device_by_name("STARLIGHT", timeout=10)
    async with BleakClient(d, timeout=15) as c:
        for label, pkts in STEPS:
            print(time.strftime("%X"), label, flush=True)
            for p in pkts:
                await c.write_gatt_char(FFF3, bytes.fromhex(p), response=True)
                await asyncio.sleep(0.2)
            await asyncio.sleep(5)


asyncio.run(main())
