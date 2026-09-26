import asyncio
from bleak import BleakClient, BleakScanner
async def main():
    d = await BleakScanner.find_device_by_name("STARLIGHT", timeout=10)
    async with BleakClient(d, timeout=15) as c:
        for s in c.services:
            print("SVC", s.uuid, s.description)
            for ch in s.characteristics:
                val = ""
                if "read" in ch.properties:
                    try: val = (await c.read_gatt_char(ch)).hex()
                    except Exception as e: val = f"ERR {e}"
                print("  CHR", ch.uuid, ch.handle, ch.properties, val)
                for de in ch.descriptors:
                    try: dv = (await c.read_gatt_descriptor(de.handle)).hex()
                    except Exception as e: dv = f"ERR {e}"
                    print("    DSC", de.uuid, dv)
asyncio.run(main())
