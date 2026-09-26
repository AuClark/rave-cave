"""Light WLED marker pixels to count LEDs and check colour order.

Pixel 0 white, every 10th red, every 50th blue, the rest off.

    python3 fixtures/tubes/scripts/wled_markers.py rave-tube-1.local [total]
"""
import json
import sys
import urllib.request

host = sys.argv[1]
total = int(sys.argv[2]) if len(sys.argv) > 2 else 200


def post(path, body):
    req = urllib.request.Request(f"http://{host}{path}", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=10).read().decode()


pixels = []
for i in range(total):
    if i == 0:
        c = "FFFFFF"
    elif i % 50 == 0:
        c = "0000FF"
    elif i % 10 == 0:
        c = "FF0000"
    else:
        c = "000000"
    pixels += [i, c]

print(post("/json/state", {"on": True, "bri": 80,
                           "seg": [{"id": 0, "start": 0, "stop": total, "fx": 0, "i": pixels}]}))
