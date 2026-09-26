# DMX light control setup (Mac + uDMX + wireless DMX uplight)

Written 26 Sep 2026. Everything below was verified on this Mac unless marked "unverified".

## Hardware chain
MacBook Air (Apple Silicon, macOS, Python 3.13 at /Library/Frameworks/Python.framework)
  then UGREEN USB-C multiport hub (GenesysLogic hub, VID 0x05e3; also has card reader + ASIX AX88179B ethernet)
  then **anyma uDMX** USB-to-DMX adapter (silver stick in the hub's USB 3.0 port)
      - Manufacturer: www.anyma.ch, Product: uDMX, Serial: ilLUTZminator001
      - USB VID 0x16c0, PID 0x05dc, USB 1.1 low speed
      - NOT a serial port (no /dev/cu.* device). Must be driven with libusb vendor control transfers.
  then DMX cable into the light.

## The light
Battery-powered wireless DMX uplight (black box, "WIRELESS DMX CODE" button, IR receiver, colour LCD, buttons MENU / UP / DOWN / ENTER).
Main menu: Dmx512, Shows, Sound, Color, Set, Help.
Current setting: **Dmx512 mode, address A001, 10CH mode.** (Wired DMX works; wireless DMX not tested.)

## Channel map (10CH, address 1)
| Ch | Function | Status |
|----|----------|--------|
| 1 | Master dimmer | verified (needed at 255 for output) |
| 2 | Red | verified |
| 3 | Green | unverified (assumed) |
| 4 | Blue | verified |
| 5 | White | unverified |
| 6 | Amber | unverified |
| 7 | UV | unverified |
| 8 | Strobe | unverified |
| 9 | Program / macro | unverified |
| 10 | Program speed | unverified |
Unverified labels are the typical layout for RGBWA+UV battery uplights; test and correct.

## uDMX protocol (what works)
- Control transfer, bmRequestType 0x40 (vendor, device, host-to-device)
- bRequest 2 = SetChannelRange: wValue = number of channels, wIndex = first channel (0-based), data = channel values (bytes)
- bRequest 1 = SetSingleChannel: wValue = value, wIndex = channel (0-based)
- The uDMX keeps outputting the last values it was sent.

## Software installed on the Mac
- `brew install libusb` (at /opt/homebrew/lib/libusb-1.0.dylib)
- Python venv at `~/.udmx-venv` with `pyusb`
- `dmx.py`: command-line sender, e.g. `~/.udmx-venv/bin/python dmx.py 255 0 0 255 0 0 0 0 0 0` (blue)

## Light Control app (this folder, `~/Lights`)
- **Double-click `Light Control.command`** to (re)start the server and open http://localhost:8765
- `server.py`: 40 fps output engine (fades + effects), auto-reconnects to the uDMX, and saves state and scenes to `lights.json`
  - Run with `--lan` to control it from a phone on the same Wi-Fi (it prints the address)
  - The uDMX throws an occasional transient USB I/O error (~1 in 10 transfers at high rates). The server tolerates these and only drops the handle after 20 failures in a row or "no such device".
- `index.html`: the UI. Live preview orb, brightness, 12 colour presets, hue/saturation pad (pastels go to the white LED), W/Amber/UV sliders, effects (Rainbow, Breathe, Strobe, Candle, Police, Party) with speed, fade time, named scenes, raw channel sliders.
- Keys: Space = blackout, 1-0 = presets, Up/Down = brightness, E = next effect, Esc = stop effect
- API: `GET /state`, `GET /events` (server-sent events), `POST /api` with JSON such as
  `{"patch":{"1":255}, "fade":500}`, `{"values":[...10]}`, `{"effect":"rainbow","speed":0.5}`, `{"blackout":"toggle"}`,
  `{"save_scene":"Name"}`, `{"recall_scene":"Name"}`, `{"delete_scene":"Name"}`. The old `POST /set` with a 10-value array still works.
- The original v1 is still in `~/udmx`.

## Ideas for next steps
- Verify channels 3 and 5 to 10 (use "All channels" in the UI)
- Multiple fixtures at different addresses
- Sound-reactive mode (mic input), timers/schedules
- Alternatively use QLC+ (supports uDMX natively)

## On the rave brain (added 26 Sep 2026)

The uDMX now plugs into the CM4 (`ravecave`) and the par can is a fixture in the show engine.
- The Pi sees the stick as `16c0:05dc`. `python3-usb` is installed, and a udev rule (`/etc/udev/rules.d/50-udmx.rules`) gives the `plugdev` group access, so the `pi` user can drive it without root.
- Show engine: `pi/showbrain/dmx.py` (a background sender that tolerates transient USB errors, reconnects, and resends every second as a keep-alive) plus the `par` look in `pi/showbrain/looks.py`.
- Fixture config (`pi/showbrain/config.json`): `"kind": "dmx_par"`, `"address": 1`, the channel map above, and `"delay_ms": 35`. USB DMX is near-instant, so it's delayed to land with the Wi-Fi fixtures.
- Channels 8 (strobe), 9 (program) and 10 (speed) are always sent as 0, so the light never runs its own programs.
- W / Amber / UV (channels 5-7) stay at 0 until verified. Once tested, list them in `"verified_extra": ["w", "a", "uv"]` for that fixture.
- Only one program can own the uDMX at a time. Stop showbrain (`sudo systemctl stop showbrain`) before using `dmx.py` or the Light Control app against it.
