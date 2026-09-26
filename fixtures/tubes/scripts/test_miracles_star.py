import asyncio, time
from bleak import BleakClient, BleakScanner
W="0000fff3-0000-1000-8000-00805f9b34fb"
TESTS = [("OFF (00)","00"),("RED 01ff0000ff0000","01ff0000ff0000"),("OFF","00"),("BLUE 010000ffff0000","010000ffff0000")]
async def main():
    d = await BleakScanner.find_device_by_name("STARLIGHT", timeout=10)
    async with BleakClient(d, timeout=15) as c:
        for label, hx in TESTS:
            print(time.strftime('%X'), label, flush=True)
            await c.write_gatt_char(W, bytes.fromhex(hx), response=True)
            await asyncio.sleep(6)
asyncio.run(main())
