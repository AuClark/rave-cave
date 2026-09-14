# Rave Cave

**Generative DJ-synced stage lighting for Sydney. Vibe-coded in a weekend.**

Jonathan Clark's beat-synced lighting rig: Raspberry Pi 4B pulls live mix data from Engine DJ decks via StageLinQ (BPM, beat position, faders, crossfader, waveforms) and drives generative lighting code. Outputs: ESP32 WLED pixel strips (stage L/R, backdrop), cheap USB-DMX ALIEN laser, optional BLE tubes, optional smoke relay. MAX open data, NOT proprietary fixture puppets.

## What's Inside

**[PLAN.md](PLAN.md)**: Full project plan—architecture (mermaid diagram), StageLinQ data map (what we get / what we infer), hardware map (already ordered vs still-buy), power budget, Pi 4B setup (network, USB-DMX on Linux), endpoints (WLED, laser DMX, tubes BLE, smoke relay), weekend build order (Fri/Sat/Sun), risks, open questions.

**[panel-controller/](panel-controller/)**: Separate HUB75 LED panel + Pi Camera rig (`rave-box`, Pi 3 Model A+ with Adafruit RGB Matrix Bonnet). Flask web server for live camera feed and hardware status. See [panel-controller/README.md](panel-controller/README.md).

## Architecture

```
Engine DJ decks (SC5000/SC6000/Prime)
  --ethernet StageLinQ (UDP 51337)-->  Raspberry Pi 4B (show brain)
                                         |-- WiFi/ethernet DDP/Art-Net --> ESP32 + WLED + SP901E --> WS2815 strips (10m, 600 LEDs)
                                         |-- USB-DMX (cheap Ali FT232) --> ALIEN SLP-RGB500 laser (10ch DMX, IEC 240V)
                                         |-- optional BLE/IR --> 103cm RGB CCT floor tubes (stretch)
                                         '-- optional USB HID relay --> smoke machine (mains or DMX)
```

## Quick Start

1. **Read [PLAN.md](PLAN.md)** top to bottom.
2. **Friday night**: Pi + decks on same gigabit switch, StageLinQ discovery (run Mixboard or StageLinq CLI), flash WLED on ESP32s, test USB-DMX serial port, dump StateMap+BeatInfo JSON (session zero).
3. **Saturday**: Wire WS2815 strips (SP901E level shift, 12V 10A bricks, inject both ends), wire laser (IEC AU lead, 3-pin DMX cable), code generator v0 (beat-in-bar chase: BeatInfo 0.0–1.0 → 4-beat LED chase + laser colour).
4. **Sunday**: Drop detection (waveform 3-band energy spikes), crossfader L/R segment fades, full rig run-through, vibe coding (colour palettes, hotcue re-sync, loop freeze, EQ filter colour shift).

## Stack

- **Brain**: Raspberry Pi 4B (Raspberry Pi OS, Python or Node)
- **Data source**: StageLinQ (reverse-engineered Engine DJ protocol: StateMap, BeatInfo, FileTransfer waveforms)
- **Libraries**: [chrisle/StageLinq](https://github.com/chrisle/StageLinq) (TypeScript, fullest), [PyStageLinQ](https://github.com/Jaxc/PyStageLinq) (Python, StateMap only), [Mixboard](https://github.com/LaokeQwQ/Mixboard) (live dashboard)
- **Pixels**: ESP32-WROOM-32 + WLED (DDP or Art-Net from Pi) + SP901E pixel amp (3.3V→5V level shift) + 12V WS2815 60 LED/m (10m = 600 LEDs, dual-data, IP67)
- **Laser**: ALIEN SLP-RGB500 (500mW RGB, 10ch DMX, IEC C14 240V inlet) via cheap USB-DMX (FT232-based, 3-pin XLR, `/dev/ttyUSB0`, QLC+ or Python pyserial)
- **Stretch**: 103cm RGB CCT floor tubes (BLE/IR, bleak Python or lirc), smoke machine (DMX or mains relay)

## Why Not SoundSwitch?

- **Closed ecosystem**: Micro DMX + SoundSwitch Pro licence (US$7.99/mo, $79.99/yr, $199.99 perpetual). Basic = Hue/Nanoleaf only, no DMX.
- **Fixture puppet mode**: Patch RGB PARs, autoscript writes canned cues. Lasers need Attribute Cues. No raw BPM/beat/waveform API. No live-coding.
- **VID/PID locked USB**: Only SoundSwitch hardware works on decks. Can't plug cheap Ali USB-DMX into deck USB.
- **WLED = 1 DRGB fixture**: SoundSwitch treats strip as single RGB unit (whole strip same colour). No per-pixel chases (300 LEDs = 900 DMX channels).

**Pi + StageLinQ = open data**: StateMap (BPM, faders, crossfader, play state), BeatInfo (beat 0.0–1.0), FileTransfer (3-band waveform zlib blobs). Python/Node can infer drops (energy spike detection), map crossfader to L/R segment brightness, sync pixel chases to beat-in-bar. Cheap USB-DMX on Pi for laser. WLED DDP/Art-Net for per-pixel control. Vibe-code it Saturday/Sunday.

## Already Ordered (AliExpress, Sep 2026)

- ESP32-WROOM-32 USB-C CP2102 × 2
- 12V 10A AU bricks × 2
- ALIEN SLP-RGB500 laser (Brazil plug SKU, IEC inlet = same unit, use AU IEC C13 kettle lead)
- WS2815 12V 60 LED/m IP67 white PCB 5m × 2 (10m total, 600 LEDs)
- SP901E pixel amp × 2 (12V in, 5V data out, 2048 px)
- SN74AHCT125N DIP chips (backup level shifter)

## Still Need

- Cheap USB-DMX (FT232-based, 3-pin XLR, ~AU$20–40 Ali/eBay)
- 3-pin DMX cable (3m+, ~AU$10–15 Jaycar/DJ City)
- Gigabit switch (if decks not already on LAN with Pi, ~AU$20–30)
- IEC C13 AU kettle lead (laser mains, ~AU$5–10)
- USB HID relay or ESP32 mains relay (if smoke is switched-only, ~AU$10–30, **mains-rated SSR in enclosure**)

## Risks

- **StageLinQ firmware drift**: Pin Engine OS version. Test Friday with Mixboard.
- **Cheap USB-DMX**: Buy FT232 (FTDI), not CH340 (flaky). Test `/dev/ttyUSB0` Friday.
- **Laser safety (Class 3B/4 if 500mW real)**: Aerials/wall/ceiling only, never audience. Mount back/up. AU typically needs laser safety officer for entertainment use.
- **WS2815 60 LED/m power**: 12A/5m at full white exceeds 10A brick. Power inject both ends, WLED brightness cap 50–80%, colours (not white) = 1/3 current.
- **Mains relay for smoke**: If DIY, **mains-rated SSR in IP box, fused, strain relief**. Do NOT use 5V toy relay modules for 240V. If unsure, trigger manually.
- **BLE tubes**: Reverse-engineering unknown protocol. Stretch goal; skip if not working by Sunday lunch.

## References

- [StageLinq (chrisle, TypeScript, fullest)](https://github.com/chrisle/StageLinq) — Discovery, StateMap, BeatInfo, FileTransfer, waveform decode
- [StageLinq protocol notes](https://github.com/honusz/stagelinq-js/blob/main/docs/PROTOCOL.md)
- [PyStageLinQ (Python, StateMap only)](https://github.com/Jaxc/PyStageLinq)
- [Mixboard (live dashboard, debug)](https://github.com/LaokeQwQ/Mixboard)
- [WLED install](https://install.wled.me/)
- [WLED DDP protocol](https://github.com/Aircoookie/WLED/wiki/UDP-Realtime-Control)
- [WS2815 datasheet](https://www.led-stuebchen.de/download/WS2815_V10_EN.pdf)
- [74AHCT125 datasheet](https://www.ti.com/lit/ds/symlink/sn74ahct125.pdf)

---

**Done when:** Friday StageLinQ live, Saturday strips + laser beat-synced, Sunday drops trigger white strobes. Vibe-code it, don't puppet it.
