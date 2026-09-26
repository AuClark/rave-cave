"""Fill WLED pixels one by one (every 10th red, others green), logging the
index with a timestamp, so someone watching can say where the strip ends.

    python3 fixtures/tubes/scripts/wled_count.py rave-tube-1.local [max] [seconds_per_led]
"""
import json
import sys
import time
import urllib.request

host = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 200
step = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5


def post(body):
    req = urllib.request.Request(f"http://{host}/json/state", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=5).read()


post({"on": True, "bri": 80, "seg": [{"id": 0, "start": 0, "stop": top, "fx": 0,
                                      "i": [0, top, "000000"]}]})
for i in range(top):
    post({"seg": [{"id": 0, "i": [i, "FF0000" if i % 10 == 0 else "00FF00"]}]})
    print(f"{time.strftime('%X')} lit LED {i} (count {i + 1})", flush=True)
    time.sleep(step)
