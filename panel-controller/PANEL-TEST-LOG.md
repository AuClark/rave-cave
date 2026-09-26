# Panel test log (rave-box)

## Hardware under test
- Pi: Raspberry Pi 3 Model A+ (`rave-box`, 192.168.20.36 on FT Hangar Wi‑Fi), user `raver`, SSH key auth (`ssh rave-box`)
- Replaced a BeagleBone controller that was dead (no power LED, no Ethernet link)
- Driver: genuine Adafruit RGB Matrix Bonnet (ADA3211, Core Electronics) — no HAT EEPROM on i2c-1 (expected)
- Library: hzeller/rpi-rgb-led-matrix on Pi at `~/rpi-rgb-led-matrix`, mapping `adafruit-hat`, `--led-slowdown-gpio=2`
- Panels: 4× outdoor HUB75 `YR PH6-8S-V1.2` (P6, 1/8 scan), 192×96 mm, 32×16 px, ~13–18 mm thick, labelled A–D, daisy-chained — treat modules as **32×16** unless proven otherwise
- Power: 5V brick into Bonnet barrel / LED board (not Mac microUSB). Throttle went from active undervolt `0x50005` to historical-only `0x50000` once on proper brick, **but undervoltage warnings still showed after the switch to the barrel jack** — power is not yet proven clean.

## Software commands that worked
```bash
cd ~/rpi-rgb-led-matrix/examples-api-use
# rotating square
sudo ./demo --led-rows=16 --led-cols=32 --led-chain=1 --led-gpio-mapping=adafruit-hat --led-slowdown-gpio=2 -D0
# full wash (custom)
sudo ./rgb-wash --led-rows=16 --led-cols=32 --led-chain=1 --led-gpio-mapping=adafruit-hat --led-slowdown-gpio=2 --led-brightness=40
```
Note: demos were often run with `--led-chain=1` while multiple panels were physically daisy-chained — remapped/half-looking output can be config, not just faults. **To fix:** set `--led-chain=N` to the number of panels physically connected (4 for the full chain → 128×16 logical), and keep `--led-rows=16 --led-cols=32`.

## Session observations (2026-09-15)
Solid R / G / B washes: dead regions in the **same places** across colours → not single-colour LED dies or software; points to interconnects (ribbons, IDC connectors), row/column drivers, traces, or old tiles.
- Horizontal black lines (esp. first/left panel) → row path (decoder / row FETs / cracked row trace).
- Vertical notches / dark columns → column shift-register / IDC pin / ribbon.
- Bottom half often OK while top half dies further down chain → suspect daisy ribbon or first panel OUT / `R2G2B2` upper-half data path; also verify chain length in software.
- Rainbow wash top≠bottom colour is partly normal (per-row hue); trust solids for fault mapping.

Bonnet+Pi path: **works**. Old PH6 tiles: some salvageable, some maybe turf.

## Next steps (summary)
1. Better bracket, off the ground.
2. Reseat every ribbon and connector.
3. Inject 5V power per panel.
4. Bring up one panel at a time; swap chain order to isolate the bad tile or cable.
5. Correct chain/rows/cols in software before judging chained output.

## Careful bring-up guide (do this next)
Goal: get as many of the 4 panels honest as possible; turf only after isolated proof.

1. **Mechanical** — off the floor on a proper bracket; strain-relief ribbons; label panels A–D and both ribbon ends IN/OUT.
2. **Power** — 5V to **each** panel's pads (or inject every panel). Confirm `vcgencmd get_throttled` is `0x0` (or only historical bits) before judging LEDs. Multimeter ≥4.9V on Pi 5V pin under load.
3. **One panel alone** — Bonnet → panel A only. Run solid R, G, B, white at brightness ~40. Photograph. Record dead rows/cols on a sketch.
4. **Swap order** — put B in the first slot alone. If dead row moves with the panel → panel fault. If it stays "first position" → cable/Bonnet/power.
5. **Add second panel** — set `--led-chain=2`. Reseat daisy IDC. Solids again. If upper half of panel 2 dies, reseat/replace daisy cable before condemning panel 2.
6. **Chain 3 then 4** — only after 1–2 look sane. Use `--led-chain=N` matching physical count.
7. **Turf criteria** — whole rows/cols dead when tested **alone** with known-good cable + good 5V → candidate scrap. Cosmetic single pixels OK for stage.

## Panel scorecard (fill in later)
| ID | Alone solids OK? | Dead rows | Dead cols | Notes | Keep? |
|----|------------------|-----------|-----------|-------|-------|
| A  |                  |           |           |       |       |
| B  |                  |           |           |       |       |
| C  |                  |           |           |       |       |
| D  |                  |           |           |       |       |

## Out of scope for now
- Pi Camera Rev 1.3 / OV5647: enumerates on I2C, CSI capture times out — likely ribbon or undervoltage. Parked. Fix: reseat the ribbon; no need to reflash the SD card.
- Chrome `ERR_ADDRESS_UNREACHABLE` to :8080 while Safari works — use Safari.
- Web UI MJPEG stream auto-start wedged the browser — stream now stays off until "Start stream" is pressed.
