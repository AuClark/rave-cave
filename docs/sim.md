# Synthetic rig (working without the hardware)

`brain/sim/run.sh` runs the whole app on your computer against a **synthetic rig**, so you can work on it with the decks, mixer, lights and brain switched off.

```bash
brain/sim/run.sh               # an endless auto-mixed set at 126 BPM
brain/sim/run.sh --bpm 132     # faster
brain/sim/run.sh --no-auto     # nothing mixes itself; load and play from the dashboard
```

It opens the Decks page. The other pages are at the usual ports on `localhost`:

| Page | Address |
|---|---|
| Decks | http://localhost:8080 |
| Lighting (Commander) | http://localhost:8090 |
| Projection | http://localhost:8100/edit |
| Stage | http://localhost:8100/stage.html |
| Visuals | http://localhost:8110 |

Press Ctrl-C to stop everything. Each service's log is in `brain/sim/logs/`. Edits to the pages show when you refresh; edits to the Python services need a restart.

## What's real and what's synthetic

- **Real:** showbrain, the projector service and the visuals service. They're the actual code from the repo, unchanged, doing exactly what they do on the brain.
- **Synthetic:** `brain/sim/fakerig.py` stands in for deckdash (the Java service that talks to the XDJs) and the DJM mixer bridge.
  - It speaks the same protocols: the dashboard API on :8080, and showbrain's UDP feed on :9100 (deck status 20×/s, a packet per beat, and mixer messages).
  - It plays an endless DJ set of 40 generated tracks. Each track has a real phrase structure: intro, grooves, breakdowns, 8–16 bar builds, drops, outro.
  - For each track it provides what the real deckdash would: a timeline with drops, sections, energy and a beat grid; overview and detailed waveforms; and library entries. Playlists are Warm up, Peak time and Trance.
  - **Auto-mix:** the next track starts on the outgoing track's outro, synced to its tempo. Its fader comes up over 8 bars, then the bass and tempo master swap. The old track fades out over 8 bars, and the next track is loaded behind it.
  - **Mixer:** channel levels, share, bass-out (in breakdowns and on the bass swap) and kicks all follow what's playing.
  - **Dashboard controls:** load, play (it starts on the other deck's next beat), stop, SYNC, MASTER and seek all work. With `--no-auto`, you run the set yourself.
- **Not simulated:**
  - Light output: showbrain sends to 127.0.0.1, so nothing lights up. Use the Commander's fixture preview or the Stage view instead.
  - The admin PIN: it's off locally, so everyone is admin.
  - Tempo-master control, album art, set recording and the System view's Pi stats.

## Requirements

- Python 3 with `numpy`: `python3 -m pip install --user numpy`
- Ports 8080, 8090, 8100 and 8110 must be free. The script checks and names any that are taken.

**About `s5auth.js`:** on the brain, `deploy.sh` copies it next to each service. Locally, `run.sh` links it into place instead. The links are git-ignored.

## On the brain

The brain can run the same synthetic rig, so a Pi on the bench (or at home, with no decks) shows the whole app working, and the real lights follow the generated set.

- **When no decks are found**, every page shows a strip at the bottom: **No decks found · Start simulation**. Starting it needs admin (the PIN).
- **While it runs**, the strip says **SIMULATION** with **Back to real decks**. Everything else is real: showbrain, the lights, projection, visuals, the Stage view, the admin PIN and the System view.
- **Nothing sticks:** stopping it, restarting deckdash or rebooting goes back to the real decks.
- API: `GET /api/sim`, `POST /api/sim {"on": true|false, "bpm": 126}` (admin). Also in `/api/system` as `sim`.

How it works: deckdash ([`Sim.java`](../brain/deckdash/Sim.java)) runs `fakerig.py` (copied to `~/sim/` by `brain/deploy.sh deckdash`) on port 8079, passes the deck data API through to it (`/api/state`, `/api/events`, timelines, waveforms, library, `/api/deck`, `/api/tempo`), and stops sending its own deck feed to showbrain while fakerig sends the synthetic one. The mixer service is paused meanwhile, because with no DJM it would keep telling showbrain the mixer is unplugged. Its log is `/tmp/fakerig.log`.
