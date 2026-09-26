import asyncio, time
from bleak import BleakClient, BleakScanner
W="0000fff3-0000-1000-8000-00805f9b34fb"
TESTS = [
 ("A ELK-BLEDOM -> RED",      ["7e0004f00001ff00ef", "7e000503ff000000ef"]),
 ("B ELK 7e07 -> GREEN",      ["7e0404f00001ff00ef", "7e07050300ff0010ef"]),
 ("C LEDLamp 7eff -> BLUE",   ["7eff0401ffffffffef", "7eff05030000ffffef"]),
 ("D Triones -> YELLOW",      ["cc2333", "56ffff0000f0aa"]),
]
async def main():
    d = await BleakScanner.find_device_by_name("STARLIGHT", timeout=10)
    async with BleakClient(d, timeout=15) as c:
        for label, pkts in TESTS:
            print(time.strftime('%X'), label, flush=True)
            for p in pkts:
                await c.write_gatt_char(W, bytes.fromhex(p), response=True)
                await asyncio.sleep(0.3)
            await asyncio.sleep(8)
asyncio.run(main())
