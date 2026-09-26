# Floor Tubes: Control Findings

> **Status (2026-09-26): Tube 1 runs WLED on an ESP32.** The stock controller's data wire was moved to an ESP-32S (GPIO13), and the strip is **60 addressable LEDs**, GRB. WLED 16.0.1 runs at `192.168.0.110` (`wled-b782e4`), and the Mac streams beat-synced frames to it over DDP (`scripts/tubes/ddp_demo.py`). The Bluetooth notes below are kept for tubes still on the stock controller.

Notes from reverse-engineering the standing LED floor tubes so they can be driven from our own code instead of the vendor app. **Status: we can connect and write commands, but no command has been visually confirmed to change the tube yet.**

## Hardware

- **Brand / model:** STAR LIGHTING, model `XSD-DD15` (Zhongshan Xiaoshidai).
- ~103 cm RGB tube on a stand, 5V USB powered.
- Inline 3-button controller on the cable; QR code on the label reads "STAR LIGHTING".
- FCC ID `2BE9I-XSD-DD15`. The manual lists three control paths: the inline buttons, an **IR remote**, and the **"Miracles Star"** app (Android package `com.weifeng.lightbar`, Lenze Technologies). It defaults to a 7-colour cycle on power-up and has a microphone/sound mode.
- **USB is power only.** With the tube plugged into the MacBook Air and running, `ioreg -p IOUSB` and `system_profiler SPUSBDataType` show no device on either bus, so there is no data interface to talk to over the cable. Control has to go over BLE (or IR).

## What advertises over BLE

Seen by a phone BLE scan (Pixel) and again from the MacBook Air with `bleak`:

| Advertised name | What it looks like | Notes |
|---|---|---|
| `STARLIGHT` | LED BLE controller | **Confirmed to be the tube** (2026-09-26): it was the only device to go silent (~40 s, 07:59:41-08:00:23) while the tube was unplugged, and it came back on replug. Connects without pairing. |
| `TUYA_` / `TY_HS_STACK` | Tuya BLE device (Smart Life ecosystem) | Same RSSI as `STARLIGHT` (-59) on 2026-09-26, so probably in the same unit or right next to it. Direct control needs Smart Life pairing plus the device's local key. |
| `SPB-20250520-189`, `SPB-20250520-198` | Two devices, service `ff00`, RSSI about -97 | Far away and too weak to connect from the Mac. Not the tube on the Mac. |

macOS **System Settings, Bluetooth** does not list any of these. That is expected: they are BLE GATT devices, not classic Bluetooth, so you need a BLE scanner (`bleak`, nRF Connect, LightBlue).

MacOS gives each device a per-Mac UUID instead of a MAC address (e.g. `STARLIGHT` showed as `C9F2FF71-7650-5E84-7624-67243B77B2E2` on Jonathan's Mac). Scan by name rather than hard-coding it.

### Advertisement data (2026-09-26, from the Mac)

- `STARLIGHT`: manufacturer ID `0xFFFF` (unassigned/test ID), data `ffff1140fd7166ff030400`; advertises service UUID `0x3515`.
- `TY_HS_STACK`: service `0xFD50` (Tuya) with service data.

`BleakScanner(detection_callback=...)` returns this data on Python 3.14 without hitting the `return_adv=True` crash described below.

## GATT layout

### `STARLIGHT`

| UUID | Properties | Role |
|---|---|---|
| Service `0000fff0-0000-1000-8000-00805f9b34fb` | | Vendor LED service |
| `0000fff3-0000-1000-8000-00805f9b34fb` | write, write-without-response | **Command channel** |
| `0000fff4-0000-1000-8000-00805f9b34fb` | notify | Subscribed on 2026-09-26: **silent**. No reply to status queries from the Triones, ELK, Zengge or Keepsmile families. |

Those are the only characteristics: no Device Information service, nothing readable. Writes with `response=True` are ACKed too, so the chip accepts the packets. That tells us nothing about whether it understood them.

### `TUYA_`

| UUID | Properties |
|---|---|
| Service `0000fd50-0000-1000-8000-00805f9b34fb` | Tuya BLE |
| `00000001-0000-1001-8001-00805f9b07d0` | write, write-without-response |
| `00000002-0000-1001-8001-00805f9b07d0` | notify |
| `00000003-0000-1001-8001-00805f9b07d0` | read (returned empty) |

Tuya BLE traffic is encrypted with a per-device key, so raw writes won't work without pairing in Smart Life and extracting the key (TinyTuya / LocalTuya style). Treat this as the secondary path.

## Commands sent to `STARLIGHT` (unconfirmed)

Written to `FFF3` with write-without-response. **Every write was accepted with no error, but we never confirmed the tube changed.** At the time it was running its built-in rainbow pulse animation.

| Meaning (guessed) | Bytes (hex) |
|---|---|
| Power on | `7e0004f00001ff00ef` |
| Power off | `7e0004000000ff00ef` |
| Red | `7e000503ff000000ef` |
| Green | `7e00050300ff0000ef` |
| Blue | `7e0005030000ff00ef` |
| White | `7e000503ffffff00ef` |
| Static mode (guess) | `7e0004f00000ff00ef` |

Not tried yet (other common cheap-LED families):

| Meaning (guessed) | Bytes (hex) |
|---|---|
| Power on | `cc2333` |
| Power off | `cc2433` |
| Red | `56ff000000f0aa` |

## Paper manual

`docs/0b440e824be583c960dcebd75fe3d62d.pdf` (33 pages) is generic multilingual safety/maintenance boilerplate with no app, protocol or remote details. Its QR code decodes to `https://docs.temu.com/instructions.html?goods_id=601103017443377` (Temu listing; the page itself is empty).

## Miracles Star APK (decompiled 2026-09-26)

Pulled v1.0.3 (`20230923`) with `apkeep -a com.weifeng.lightbar`, decompiled with jadx 1.5.6 (both installed outside Homebrew because an untrusted `mongodb/brew` tap blocks `brew install`). Working copy: `~/tools/apk/src/`.

**This app build does not target our tube's firmware.** It only scans for the exact name `Miracles_Star` (`ScanFilter.setDeviceName` in `ble/TGBluetoothScanner.java`) and talks to service `0000e0ff-3c17-d293-8e48-14fe2e4da212`, characteristic `ffe1`. Our tube advertises `STARLIGHT` on service `fff0` / characteristic `fff3`. So either the tube ships with firmware for a different app, or it pairs with a different Miracles Star release.

Its protocol is still worth recording, because it is plain unframed bytes with no checksum or encryption (`utils/OrderUtils.java`, `utils/Agmt.java`):

| Command | Bytes |
|---|---|
| Off | `00` |
| Colour / mode | `01 RR GG BB brightness mode speed`. The colour page sends `mode` 0 (static colour). The mode page sends RGB `000000` with `mode` 1-N (built-in animations, picked from a wheel) and brightness/speed 0-100 from sliders. |
| Sync clock | `02 weekday HH MM SS` (weekday 1-7, Monday = 1) |
| Timer on / off | `03 ...` / `04 ...` (weekday mask, HH, MM) |

Sent to `STARLIGHT` `FFF3` twice (off, red, off, blue): **no visible reaction**. The ELK-BLEDOM, ELK `7e07`, LED Lamp `7eff` and Triones families in `scripts/tubes/test_led_families.py` also produced no reaction on the rerun.

### Other apps checked

- **duoCo Strip** (`shy.smartled`): uses the same `fff0`/`fff3` UUIDs but only accepts names starting `ELK-`, `ELK~`, `ELK_`, `LED LIGHT STRIP`, and has its own name-encryption layer. No `STARLIGHT`.
- **Magic Lantern** (`wl.smartled.rgb`): no `STARLIGHT`.

## Controller board (photo 2026-09-26)

Round PCB in the tube's end cap:

- **MCU: Lenze `ST17H66T`**, a BLE SoC with a 16 MHz crystal and PCB trace antenna. Lenze also publishes the Miracles Star app, so the firmware is probably built on Lenze's SDK, but the protocol on this unit does not match that app build.
- **3.3V LDO** (SOT-23 marked `662K`, likely XC6206 3.3V). The MCU drives the strip at 3.3V logic, so an ESP32's 3.3V GPIO should drive it the same way.
- **Electret microphone** (sound-reactive mode), a **slide switch**, a **USB-C** input, and a 3-legged part potted in grey glue that looks like the **IR receiver** for the remote.
- **Three wires (orange, white, grey) leave the board toward the strip.** No bank of three MOSFETs is visible, so this points to an **addressable strip (5V / data / GND)**. Still to be confirmed with a multimeter.

## Plan B: ESP32 + WLED inside the tube (recommended)

Replace the tube's stock controller with an ESP32 running WLED, the same stack as the stage strips. The tube then takes DDP/Art-Net from the Pi like every other pixel output: per-pixel, beat-synced, no vendor protocol.

1. Open the tube's end cap or controller and look at the LED strip's wires:
   - **3 wires (5V, DIN/data, GND)**: addressable (WS2812B/WS2811 style). Best case. ESP32 GPIO to DIN via a 330 ohm resistor. A level shifter (e.g. 74AHCT125) helps but 3.3V data usually works over a short lead at 5V.
   - **4 wires (5V/+, R, G, B)**: analog RGB, whole tube one colour. WLED can still drive it with 3 logic-level MOSFETs on PWM pins.
   - **5-6 wires**: RGB + CCT (warm/cool white), analog. Same as above with more MOSFETs.
2. Power the ESP32 from the tube's 5V USB feed. Set WLED's current limiter to about 1500 mA if it stays on a USB port.
3. Flash with install.wled.me, set the LED count, add it to the Pi's DDP targets.

### Wiring for our boards (ESP-32S NodeMCU, 38-pin, CP2102, USB-C)

| Strip wire | ESP32 pin | Notes |
|---|---|---|
| Data (DIN) | **GPIO13** (`P13`), 330 ohm series resistor recommended for the permanent install | Same header as 5V and GND, so all three wires land together. GPIO14/25/26/27/32/33 also work. Avoid GPIO0/2/5/12/15 (strapping), 6-11 (`SD*`/`CLK`/`CMD`, flash) and 34-39 (input only). |
| GND | the `GND` between `P12` and `P13` | Common ground is mandatory. **Don't use the pin labelled `GND` next to `5V`**: the vendor pinout says it is GPIO11 (flash CMD), so it is probably a silkscreen error. |
| 5V | `5V` (bottom of the `3V3`/`EN` header) | See power options below. |

Board labels are on the back, so the headers are mirrored relative to the vendor's front-view pinout diagram.

Power options:
- **Simple:** plug the tube's USB power into the ESP32's USB-C, and run strip 5V from the ESP32's `5V` pin. All LED current then passes through the board's USB input path (often a ~1 A diode), so cap WLED's current limit at **850 mA**.
- **Better:** split the 5V feed before the ESP32: USB 5V goes to the strip's 5V **and** the ESP32's `5V` pin in parallel. Set the WLED limit to what the supply can deliver (e.g. 1500-2000 mA on a 2-3 A charger).

Don't power it from both the ESP32's USB (from the Mac) and a separate 5V feed at the same time. Flash first, then move to the tube supply.

WLED settings (LED Preferences): GPIO 13, type WS281x (try GRB colour order first; switch if red/green are swapped), length = LED count, max current as above.

Keep the stock controller intact if possible (cut-and-connector, not cut-and-solder) so it can be reverted.

## Tube 1 on WLED (working)

- Board: ESP-32S NodeMCU (MAC `90:15:06:b7:82:e4`, 4MB flash), hostname `wled-b782e4`, IP `192.168.0.110`.
- Flashed from the Mac with esptool (files in `~/tools/wled/`, sources from `wled/WLED-WebInstaller` `bin/boot/` and the WLED v16.0.1 release): `0x1000 bootloader_esp32_8m.bin` (esptool re-flags it to 4MB), `0x8000 partitions_c3_4m.bin`, `0xe000 boot_app0.bin`, `0x10000 WLED_16.0.1_ESP32.bin`, `--flash-mode dio --flash-size 4MB`.
- Stock board pad labels: **V** = orange (5V), **C** = grey (data), **G** = white (GND).
- WLED config: GPIO13, WS281x (type 22), GRB, 60 LEDs, 850 mA limit (powered through the ESP32's USB). Idle look: Aurora effect, Party palette.
- DDP: UDP 4048, 10-byte header (`41 seq 01 01` + 32-bit offset + 16-bit length) then RGB bytes. WLED drops back to its own effect a few seconds after the stream stops.

## Tube 2 on WLED

- Same board and setup as Tube 1: ESP-32S, MAC `90:15:06:b7:68:00`, WLED 16.0.1, name "Tube 2", `192.168.20.96` on FT Hangar.
- GPIO13, WS281x, GRB, 60 LEDs, 850 mA. Wi-Fi pushed over serial with `scripts/tubes/wled_wifi_serial.py`.
- Listed in `pi/showbrain/config.json` as `tube2`.

## Scripts

Everything lives in `scripts/tubes/`. Run with `~/.venvs/ble/bin/python`.

| Script | Purpose |
|---|---|
| `presence.py` | Log BLE devices appearing and disappearing, plus each device's longest silence. Used for the unplug test. |
| `scan_adv.py` | One-shot scan printing manufacturer data, service UUIDs and service data. |
| `inspect_device.py` | Advertisement plus GATT dump for a name prefix. |
| `gatt_dump.py` | GATT dump for `STARLIGHT`. |
| `probe_notify.py` | Subscribe to `FFF4` and send status queries. |
| `test_led_families.py` | One colour per common protocol family. |
| `test_miracles_star.py` | Miracles Star command format on `FFF3`. |
| `test_power_on.py` | Power-on packets per protocol family, sent with the tube switched off. |
| `adv_watch.py` | Log changes in what strong BLE devices advertise. |
| `wled_markers.py` | WLED marker pixels (0 white, every 10th red, every 50th blue). |
| `wled_count.py` | Fill pixels one by one with timestamps, to find the strip length. |
| `ddp_demo.py` | Beat-synced DDP demo reel (kick pulse, comet, plasma pump, sparkle, build and drop). |

## Mac setup

`bleak` is a Python package, not a Homebrew formula (`brew install bleak` just suggests `black`). Homebrew's Python also refuses a bare `pip install` (PEP 668, "externally managed environment"). Use a virtual environment:

```bash
python3 -m venv ~/.venvs/ble
~/.venvs/ble/bin/pip install bleak
```

`~/.venvs/ble` now exists on Jonathan's Mac (created 2026-09-26). The old `/tmp/ble-scan-venv` had lost `bleak`.

On Python 3.14, `BleakScanner.discover(return_adv=True)` crashed with `AttributeError: 'Swift.__StringStorage' object has no attribute 'name'`. Plain `BleakScanner.discover(timeout=12)` works.

The first scan may trigger a macOS prompt to allow Terminal to use Bluetooth.

## Minimal example

```python
import asyncio
from bleak import BleakClient, BleakScanner

FFF3 = "0000fff3-0000-1000-8000-00805f9b34fb"
BLUE = bytes.fromhex("7e0005030000ff00ef")  # unconfirmed

async def main():
    devices = await BleakScanner.discover(timeout=8)
    tube = next((d for d in devices if d.name == "STARLIGHT"), None)
    if not tube:
        print("STARLIGHT not found")
        return
    async with BleakClient(tube.address, timeout=15) as client:
        await client.write_gatt_char(FFF3, BLUE, response=False)

asyncio.run(main())
```

Run it with `~/.venvs/ble/bin/python tube_blue.py`.

## Next steps

1. Rerun the solid-blue write while someone watches the tube.
2. If nothing changes, subscribe to `FFF4` notifications and try the other packet families above.
3. If guessing stalls, pull the protocol straight out of the vendor app: download the Miracles Star APK (`com.weifeng.lightbar`), decompile it with `jadx`, and search for writes to `fff3` and the byte-array builders around them. No Bluetooth capture needed.
4. Or capture it live: enable Bluetooth HCI snoop log on the Pixel, drive the tube from the official app, then read the log in Wireshark.
5. Once a colour command works, wrap it in a small script or module the show brain (Pi 4B) or the Mac can call.
6. `TUYA_` path only if `STARLIGHT` turns out not to control the tube.
