#!/usr/bin/env python3
"""Save the waveform and beat grid of a track on the decks, to test waveform sketches at home.

Run it on the brain, or on a laptop on the rig's network, with a track loaded:

    python3 brain/visuals/tools/capture_wave.py http://<brain IP>:8080 [player]

It writes brain/visuals/state/wave-sample.bin and wave-sample.json (not in git). The visuals
service uses them, looped, whenever no deck is live. The player defaults to whichever deck
is playing, else the first with a track.
"""
import json
import sys
import urllib.request
from pathlib import Path

STATE = Path(__file__).resolve().parent.parent / "state"


def get(url):
    with urllib.request.urlopen(url, timeout=10) as r:
        return r.read()


def main():
    base = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080").rstrip("/")
    players = json.loads(get(f"{base}/api/state")).get("players", [])
    if len(sys.argv) > 2:
        n = int(sys.argv[2])
    else:
        loaded = [p for p in players if p.get("track")]
        playing = [p for p in loaded if (p.get("status") or {}).get("playing")]
        if not loaded:
            sys.exit("no deck has a track loaded")
        n = (playing or loaded)[0]["number"]
    detail = get(f"{base}/api/wavedetail/{n}")
    tl = json.loads(get(f"{base}/api/timeline/{n}"))
    STATE.mkdir(exist_ok=True)
    (STATE / "wave-sample.bin").write_bytes(detail)
    (STATE / "wave-sample.json").write_text(json.dumps({"title": tl.get("title"), "beatMs": tl["beatMs"]}))
    print(f"saved deck {n}: {tl.get('title')!r}, {len(tl['beatMs'])} beats, {len(detail) // 4} frames -> {STATE}")


if __name__ == "__main__":
    main()
