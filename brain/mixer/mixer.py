#!/usr/bin/env python3
"""DJM-450 mixer bridge: post-fader channel levels, master level and MIDI over USB.

The DJM-450's USB sound card exposes capture sources (ALSA card "DJM450"):
  Input 1 -> capture ch 1/2   set to "Post Fader"  (mixer channel 1, after its fader)
  Input 2 -> capture ch 3/4   set to "Post Fader"  (mixer channel 2, after its fader)
  Input 3 -> capture ch 5/6   set to "Rec Out"     (the master mix)
It only streams capture while a playback stream is open (implicit feedback), so we
also play silence to it. The decks' channels are on LINE, so that silence isn't heard.

Every 50 ms it sends a JSON "mixer" message over UDP to deckdash (:9101) and showbrain
(:9100) with RMS/peak dB per channel, each channel's share of the mix, and recent MIDI.

    python3 brain/mixer/mixer.py
"""
import json
import socket
import subprocess
import threading
import time

import numpy as np

CARD = "DJM450"
RATE, CH, BLOCK_S = 48000, 8, 0.05
TARGETS = [("127.0.0.1", 9101), ("127.0.0.1", 9100)]
SOURCES = {"Input 1": "Post Fader", "Input 2": "Post Fader", "Input 3": "Rec Out"}
SILENCE_DB = -70.0

midi_log = []          # recent MIDI messages (hex strings), newest last
midi_lock = threading.Lock()
midi_count = 0


def log(msg):
    print(time.strftime("%X"), msg, flush=True)


def card_present():
    try:
        return CARD in open("/proc/asound/cards").read()
    except OSError:
        return False


def set_sources():
    for ctl, val in SOURCES.items():
        subprocess.run(["amixer", "-c", CARD, "-q", "sset", ctl, val], check=False)


def midi_reader():
    """Collect raw MIDI from the DJM (amidi -d prints hex bytes)."""
    global midi_count
    while True:
        port = None
        try:
            out = subprocess.run(["amidi", "-l"], capture_output=True, text=True).stdout
            port = next((l.split()[1] for l in out.splitlines() if "DJM-450" in l), None)
        except OSError:
            pass
        if not port:
            time.sleep(3)
            continue
        p = subprocess.Popen(["amidi", "-p", port, "-d"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        for line in p.stdout:
            line = line.strip()
            if not line:
                continue
            with midi_lock:
                midi_count += 1
                midi_log.append({"t": round(time.time(), 2), "hex": line})
                del midi_log[:-20]
        time.sleep(1)


def db(x):
    return float(20 * np.log10(x + 1e-9))


def run():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    threading.Thread(target=midi_reader, daemon=True).start()
    while True:
        if not card_present():
            msg = json.dumps({"t": "mixer", "ts": int(time.time() * 1000), "connected": False})
            for tgt in TARGETS:
                sock.sendto(msg.encode(), tgt)
            time.sleep(2)
            continue
        set_sources()
        dev = f"hw:{CARD},0"
        play = subprocess.Popen(["aplay", "-D", dev, "-f", "S24_3LE", "-c", str(CH), "-r", str(RATE), "-t", "raw", "-q", "/dev/zero"],
                                stderr=subprocess.DEVNULL)
        time.sleep(0.3)
        cap = subprocess.Popen(["arecord", "-D", dev, "-f", "S24_3LE", "-c", str(CH), "-r", str(RATE), "-t", "raw", "-q"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        log("capturing from DJM-450")
        blk = int(RATE * BLOCK_S) * CH * 3
        peak_hold = np.full(3, SILENCE_DB)
        try:
            while True:
                b = cap.stdout.read(blk)
                if len(b) < blk:
                    break
                a = np.frombuffer(b, np.uint8).reshape(-1, 3).astype(np.int32)
                s = a[:, 0] | (a[:, 1] << 8) | (a[:, 2] << 16)
                s = np.where(s >= 1 << 23, s - (1 << 24), s).reshape(-1, CH) / float(1 << 23)
                # Stereo pairs -> ch1, ch2, master
                pairs = [s[:, 0:2], s[:, 2:4], s[:, 4:6]]
                rms = np.array([np.sqrt((p ** 2).mean()) for p in pairs])
                pk = np.array([np.abs(p).max() for p in pairs])
                rms_db = np.array([db(x) for x in rms])
                pk_db = np.array([db(x) for x in pk])
                peak_hold = np.maximum(pk_db, peak_hold - 0.6)      # ~12 dB/s fall
                e = rms[:2] ** 2
                share = (e / e.sum()).tolist() if e.sum() > 1e-10 else [0.0, 0.0]
                with midi_lock:
                    midi = {"count": midi_count, "recent": list(midi_log[-8:])}
                names = ["ch1", "ch2", "master"]
                msg = {"t": "mixer", "ts": int(time.time() * 1000), "connected": True, "model": "DJM-450",
                       "channels": {n: {"rms_db": round(float(rms_db[i]), 1), "peak_db": round(float(pk_db[i]), 1),
                                        "peak_hold_db": round(float(peak_hold[i]), 1),
                                        "active": bool(rms_db[i] > SILENCE_DB)} for i, n in enumerate(names)},
                       "share": {"ch1": round(share[0], 3), "ch2": round(share[1], 3)},
                       "midi": midi}
                data = json.dumps(msg).encode()
                for tgt in TARGETS:
                    sock.sendto(data, tgt)
        finally:
            for p in (cap, play):
                p.kill()
        log("capture stopped, retrying")
        time.sleep(2)


if __name__ == "__main__":
    run()
