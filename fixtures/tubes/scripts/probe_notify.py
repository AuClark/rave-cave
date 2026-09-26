import asyncio, time
from bleak import BleakClient, BleakScanner
W="0000fff3-0000-1000-8000-00805f9b34fb"; N="0000fff4-0000-1000-8000-00805f9b34fb"
PROBES = [
 ("triones status", "ef0177"),
 ("elk status?", "7e0000000000000000ef"),
 ("elk brightness 100", "7e0001640000000000ef"),
 ("elk7 brightness 100", "7e0401640000000000ef"),
 ("zengge status", "81 8a 8b 96".replace(" ","")),
 ("keepsmile query", "7e0704ff00010201ef"),
]
async def main():
    d = await BleakScanner.find_device_by_name("STARLIGHT", timeout=10)
    async with BleakClient(d, timeout=15) as c:
        await c.start_notify(N, lambda h, b: print(f"   NOTIFY {b.hex()}"))
        for label, hx in PROBES:
            for resp in (False, True):
                print(f"{time.strftime('%X')} {label} resp={resp} {hx}")
                try: await c.write_gatt_char(W, bytes.fromhex(hx), response=resp)
                except Exception as e: print("   ERR", e)
                await asyncio.sleep(1.5)
        await asyncio.sleep(3)
asyncio.run(main())
