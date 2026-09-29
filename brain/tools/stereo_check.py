#!/usr/bin/env python3
"""Is the DJM-450's USB audio really stereo per channel? Watches the mixer's live left/right figures
(brain/mixer: "stereo" in the mixer message, via the dashboard's /api/state) for a while and says,
for channel 1, channel 2 and the master, whether left and right carry different audio.

Play a stereo track on a deck with its fader up (for a clear answer, turn on the DJM's Beat FX
"PAN" for a few seconds too), then on the brain:

    python3 ~/tools/stereo_check.py            # 30 s
    python3 ~/tools/stereo_check.py 60         # longer
"""
import json
import sys
import time
import urllib.request

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 30
try:
    with urllib.request.urlopen("http://127.0.0.1:8080/api/sim", timeout=2) as r:
        if json.load(r).get("on"):
            print("the simulation is on (no real decks found), so there's no real mixer audio to check.\n"
                  "Plug the DJM-450's USB into the brain and the decks into the network; the sim turns off\n"
                  "by itself when the decks appear (or turn it off in the System view), then run this again.")
            sys.exit(1)
except OSError:
    pass
seen = {"ch1": [], "ch2": [], "master": []}
end = time.time() + secs
print(f"watching the mixer's left/right for {secs:.0f} s (play a stereo track, fader up)...", flush=True)
while time.time() < end:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/api/state", timeout=2) as r:
            m = json.load(r).get("mixer") or {}
    except Exception as e:
        print("can't read the dashboard:", e); sys.exit(1)
    if not m.get("connected"):
        print("the DJM-450 isn't connected (USB)"); sys.exit(1)
    for k, v in (m.get("stereo") or {}).items():
        if v and k in seen:
            seen[k].append(v)
    time.sleep(0.5)

def verdict(rows):
    if not rows:
        return "silent the whole time (fader down, or nothing playing on it)"
    corr = sum(r["corr"] for r in rows) / len(rows)
    width = max(r["width_db"] for r in rows)
    hw = max(r["highs"]["width_db"] for r in rows)
    swing = max(r["bal_db"] for r in rows) - min(r["bal_db"] for r in rows)
    kind = ("MONO: left and right are the same signal" if corr > 0.998 and width < -40
            else "PANNED: the same signal, louder on one side" if corr > 0.998
            else "STEREO: left and right differ")
    return (f"{kind}  (L/R alike {corr:.3f}; widest {width:.1f} dB, highs {hw:.1f} dB; balance swung {swing:.1f} dB; "
            f"{len(rows)} readings)")

for k in ("ch1", "ch2", "master"):
    print(f"  {k:6}  {verdict(seen[k])}")
