# Rave Cave

A beat-synced lighting rig driven by the DJ decks. A Raspberry Pi Compute Module 4 joins the Pioneer DJ Link network, reads what each deck is playing, analyses each loaded track ahead of time to find breakdowns, builds and drops, and drives every light in the room from one scene engine.

Status as of 27 Sep 2026: running end to end in the workshop. Two decks drive two LED tubes and a DMX par can. The LED pyramid is wired and taking test patterns, but isn't in the show yet.

## How it works

```
Pioneer XDJ-700 x2 ── Ethernet switch (Pro DJ Link, link-local) ── CM4 "ravecave"
                                                                     │
                                          deckdash (Java, beat-link) │  deck status, beat packets,
                                          dashboard  :8080           │  track metadata, waveforms,
                                          timeline analyser          │  read-ahead section/drop timeline
                                                                     │  UDP feed (localhost:9100)
                                          showbrain (Python, numpy)  │  scene engine, 50 fps
                                          Commander  :8090           ▼
            ┌──────────────────────── Wi-Fi, DDP (UDP 4048) ────────────────────┐        USB
            ▼                          ▼                          ▼             ▼          ▼
     rave-tube-1 / -2           rave-box (Pi 3 A+)          (HUB75 panel,   uDMX ──► par can
     ESP32 + WLED, 60 LEDs      SPI ──► SP901E ──► pyramid   same receiver    (DMX ch 1-10)
                                600 × WS2815 (not in         type, retired)
                                the show yet)
```

1. **Deck data.** `deckdash` uses [beat-link](https://github.com/Deep-Symmetry/beat-link) to join the Pro DJ Link network as virtual player 7. It receives beat packets and player status (play state, tempo master, BPM, pitch, beat position) and pulls track metadata, artwork, beat grids and detailed colour waveforms from the rekordbox export on the USB stick.
2. **Read-ahead.** When a track loads, `deckdash` works out bass and energy for every bar from the detailed waveform and labels the track: intro, groove, breakdown, build, drop, outro. Drops are found where bass returns strongly after a low-bass stretch, then refined to the exact bar.
3. **Scenes.** `showbrain` follows one "live" deck and runs a scene state machine: GROOVE → BREAKDOWN → BUILD (holds while the DJ loops) → PRE-DROP (blackout on the last beat) → DROP. Everything is scheduled in beats, so pitch changes and loops are handled. Each fixture renders its own look for the current scene and is delay-compensated so drops land together.
4. **Output.** Frames go to the LED fixtures over DDP and to the par can over USB DMX.

## Hardware

| Part | Role | Notes |
|---|---|---|
| 2 × Pioneer XDJ-700 (fw 1.13) | Decks | Linked through an unmanaged switch. No DJM mixer is on the link, so there's no fader or on-air data. |
| Raspberry Pi CM4 (4 GB, 32 GB eMMC, Wi-Fi) on a carrier, with fan | Show brain, hostname `ravecave` | Ethernet to the deck switch (link-local only), Wi-Fi to the fixtures. Raspberry Pi OS Lite (Debian 13). |
| 2 × 103 cm RGB floor tubes (XSD-DD15) | `rave-tube-1`, `rave-tube-2` | Stock Bluetooth controller bypassed. ESP32 running WLED 16.0.1, data on GPIO13, 60 addressable LEDs each. See [TUBES.md](TUBES.md). |
| Raspberry Pi 3 A+ | `rave-box` | Drives the pyramid over SPI (GPIO10) through an SP901E signal amplifier. Previously drove the HUB75 panels. |
| 2 × 5 m WS2815 12 V strip, 60 LED/m | LED pyramid (600 LEDs) | Frame built. Pixel map not done yet. |
| Battery RGBWA+UV uplight | Par can, 10-channel DMX at address 1 | Driven by an anyma uDMX on the CM4. See [parcan/DMX-light-setup.md](parcan/DMX-light-setup.md). |
| 4 × 32×16 HUB75 panels | Retired for now | Faults on three of four panels. See [panel/PANELS.md](panel/PANELS.md). |

## Software

| Component | Where | What it does |
|---|---|---|
| `deckdash` | [pi/deckdash/](pi/deckdash/) | Java service on the CM4. Pro DJ Link client (beat-link 7.4.0), web dashboard on **:8080** (deck cards, artwork, waveforms with predicted sections and drops, stacked scrolling two-deck waveform), timeline analyser (`/api/timeline/N`), local UDP feed for `showbrain`. |
| `showbrain` | [pi/showbrain/](pi/showbrain/) | Python scene engine on the CM4. Numpy looks for strips, panels and the par can. Commander control page on **:8090**. Fixtures are listed in `config.json`. |
| Commander | `http://ravecave.local:8090` | Phone control: DROP NOW, BUILD, HOLD, STROBE, BLACKOUT, skip or mark drops (saved per track), follow deck 1/2/auto, intensity, output latency. |
| Pyramid receiver | [pyramid/](pyramid/) | DDP receiver on `rave-box`, drives WS2815 via `rpi_ws281x` over SPI, with a current limiter. `setup_rave_box.sh` does the one-time Pi setup. |
| Panel receiver and test | [panel/](panel/) | DDP receiver for the HUB75 chain and a per-panel health test. |
| Tube tooling | [scripts/tubes/](scripts/tubes/) | BLE investigation scripts, WLED Wi-Fi over serial, LED counting, DDP demo reel. |
| Tube base enclosure | [cad/tube_base/](cad/tube_base/) | Parametric build123d model: tripod mount, tube socket, vertical ESP32 pod. STEP/STL in `out/`. |
| CM4 provisioning | [pi/provision/](pi/provision/) | Generates cloud-init files for flashing Raspberry Pi OS. |

## Using it

- Dashboard: `http://ravecave.local:8080` (or the CM4's IP on Android).
- Commander: `http://ravecave.local:8090`.
- Deploy code changes from this repo to the Pi: `pi/deploy.sh` (both services), `pi/deploy.sh showbrain`, `pi/deploy.sh deckdash`, `pi/deploy.sh panel`.
- Add a fixture: add an entry to [pi/showbrain/config.json](pi/showbrain/config.json) (`strip`, `panel` or `dmx_par`) and run `pi/deploy.sh showbrain`.
- Both CM4 services start on boot and restart on failure. WLED devices fall back to their own idle effect when the stream stops.

## Which deck drives the lights

Without mixer data the lights can't see fader positions, so the live deck is chosen by rules:

1. A deck locked in the Commander ("follow deck 1/2").
2. Mixer on-air flags, if a Pioneer DJM is ever on the link.
3. Otherwise, stay on the current deck while it plays. Cueing or previewing the other deck doesn't move the lights.
4. Hand over when the current deck stops or ends, when it has been in its outro for 16 s while the other has played for 30 s, or when the incoming deck hits a predicted drop while the outgoing one is in its outro.

## Known limitations

- **Drop detection** is waveform-based and tested on a limited number of tracks. It can be up to a bar out, and psytrance produces many candidates. Enabling rekordbox phrase analysis would give exact section labels. Commander marks correct individual tracks and are logged for calibration.
- **No fader data** (no DJM on the link). See the rules above.
- **rave-box Wi-Fi** has dropped several times. The pyramid shows an idle animation when frames stop.
- **The par can's W / Amber / UV channels** are unverified and kept off. Strobe, program and speed channels are always 0.
- **The Pi has no RTC.** The clock is wrong until it syncs after boot. Services handle this, but log timestamps before the sync are off.

## Repository layout

```
pi/          CM4 services (deckdash, showbrain), provisioning, deploy script
pyramid/     WS2815 pyramid receiver and rave-box setup
panel/       HUB75 panel receiver, health test, fault log
panel-controller/  rave-box panel web UI and earlier test log
parcan/      DMX uplight notes and uDMX sender
scripts/tubes/     floor tube BLE and WLED tooling
cad/         tube base enclosure
docs/        SHOW_BRAIN.md (scene engine design), tube manual
TUBES.md     floor tube findings and WLED setup
PLAN.md      original weekend plan (written for Engine DJ / StageLinQ; the decks turned out to be Pioneer)
```

## Next

- Pyramid pixel map and pyramid looks in the scene engine.
- Projector visuals synced to the same scenes.
- Calibrate drop prediction from marked drops.
- Laser and smoke outputs. Smoke will have hardware-enforced off-by-default, burst limits and arming, per [docs/SHOW_BRAIN.md](docs/SHOW_BRAIN.md).
