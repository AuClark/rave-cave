import asyncio
from bleak import BleakScanner
seen = {}
def cb(d, adv):
    n = d.name or adv.local_name
    if not n: return
    seen[d.address] = (n, adv.rssi, {k: v.hex() for k, v in adv.manufacturer_data.items()},
                       list(adv.service_uuids), {k: v.hex() for k, v in adv.service_data.items()})
async def main():
    async with BleakScanner(detection_callback=cb):
        await asyncio.sleep(12)
    for a, v in sorted(seen.items(), key=lambda x: -x[1][1]):
        print(a, *v)
asyncio.run(main())
