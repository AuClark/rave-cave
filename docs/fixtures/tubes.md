# Floor tubes

Two 103 cm standing RGB tubes (STAR LIGHTING `XSD-DD15`), each converted to an ESP32 running WLED so the brain can drive every pixel over Wi-Fi. Code and tools: [`fixtures/tubes/`](../../fixtures/tubes/). Enclosure: [tube-enclosure.md](tube-enclosure.md).

| Tube | Hostname | Controller | LEDs |
|---|---|---|---|
| 1 | `rave-tube-1.local` | **ESP32-C3 SuperMini**, WLED 16.0.1 (ESP32-C3 build), data on **GPIO 10** (since 3 Oct 2026; see [the C3](#the-esp32-c3-supermini)) | 60 × WS2812-type, GRB |
| 2 | `rave-tube-2.local` | Moving to an ESP32-C3 too. Its old ESP-32S board is now Pyramid R's controller ([leg-pyramids.md](leg-pyramids.md)), so tube 2 is offline until its C3 is fitted. | same |

The tubes' original ESP-32S NodeMCU boards (38-pin, CP2102) now run the [leg pyramids](leg-pyramids.md). The sections below on the ESP-32S still apply to those boards.

## How a tube is built

### 1. The stock tube

- 5 V over USB-C. The USB is power only; there's no data interface on the cable.
- A round controller board in the end cap: a Lenze ST17H66T Bluetooth SoC, a 3.3 V regulator, an electret mic, an IR receiver and a slide switch.
- **Three wires to the strip**, labelled on the board: **V** (orange, 5 V), **C** (grey, data), **G** (white, GND). The strip is addressable (WS2812-type), 60 LEDs.

### 2. Wiring the ESP32

Move the three strip wires from the stock board to the ESP32. Keep the stock board, ideally with a connector rather than cutting, so it can be reverted.

| Strip wire | ESP32 pin (ESP-32S NodeMCU) |
|---|---|
| C, data | **GPIO13** (`P13`), with a 330 Ω series resistor for permanent installs |
| G, GND | `GND` between `P12` and `P13` |
| V, 5 V | `5V`, at the bottom of the `3V3`/`EN` header |

- These three pins are on one header. The board's labels are printed on the back, so it's mirrored compared with vendor front-view pinouts.
- **Don't use the pin labelled `GND` next to `5V`.** On the reference design that pin is GPIO11 (flash CMD); the label is a silkscreen error.
- Avoid GPIO 0/2/5/12/15 (they affect boot), 6–11 (flash) and 34–39 (input only). GPIO 14/25/26/27/32/33 also work for data.
- 3.3 V data drives the strip fine over a short lead. Use a 74AHCT125 or an SP901E for long data runs.
- Connect ground first, and never plug or unplug the strip while it's powered (it can kill the first LED).

**Power:** plug the tube's USB-C supply into the ESP32 and take the strip's 5 V from the ESP32's `5V` pin. All LED current then passes through the board's USB input (typically about 1 A), so WLED's current limit is set to **850 mA**. For more headroom, split the 5 V feed before the ESP32 and raise the limit to match the supply. Never power it from USB and a separate 5 V feed at the same time.

### 3. Flashing WLED (from a Mac)

WLED release assets contain only the application. A blank chip also needs the bootloader and partition table, which come from [wled/WLED-WebInstaller](https://github.com/wled/WLED-WebInstaller) `bin/boot/`:

```bash
pip install esptool
esptool --port /dev/cu.usbserial-0001 --chip esp32 erase-flash
esptool --port /dev/cu.usbserial-0001 --chip esp32 --baud 460800 write-flash \
  --flash-mode dio --flash-size 4MB \
  0x1000  bootloader_esp32_8m.bin \
  0x8000  partitions_c3_4m.bin \
  0xe000  boot_app0.bin \
  0x10000 WLED_16.0.1_ESP32.bin
```

`bootloader_esp32_8m.bin` is re-flagged to 4 MB by esptool. `partitions_c3_4m.bin` is the shared 4 MB table. Or just use [install.wled.me](https://install.wled.me) in Chrome.

### The ESP32-C3 SuperMini

The tubes' controllers since October 2026: smaller, so they fit the new mounts.

| Strip wire | C3 pin |
|---|---|
| C, data | **GPIO 10**, with a 330 Ω series resistor |
| G, GND | `GND` |
| V, 5 V | `5V` (the tube's USB-C supply goes into the C3) |

Pins to leave alone on the C3: **8** (a strapping pin, and the board's blue LED; WLED often defaults to it), **9** (the BOOT button), **2** (strapping), **18 / 19** (native USB: using them breaks USB flashing and serial) and **20 / 21** (the UART). 4, 5, 6, 7 and 10 are clean.

**Flashing** (the C3 is native USB: `/dev/cu.usbmodem*`; if it isn't detected, hold BOOT while plugging it in). The bootloader goes at **0x0** on a C3 (0x1000 on the ESP32). Boot files from [wled/WLED-WebInstaller](https://github.com/wled/WLED-WebInstaller) `bin/boot/`, the app from the WLED release:

```bash
esptool --chip esp32c3 --port /dev/cu.usbmodem1101 erase-flash
esptool --chip esp32c3 --port /dev/cu.usbmodem1101 --baud 460800 write-flash \
  --flash-mode dio --flash-size 4MB \
  0x0     bootloaders/esp32-c3/bootloader_c3_8m.bin \
  0x8000  partitions/partitions_c3_4m.bin \
  0xe000  boot_app0.bin \
  0x10000 WLED_16.0.1_ESP32-C3.bin
```

Then Wi-Fi over USB with `fixtures/tubes/scripts/wled_wifi_serial.py "SSID" "password" /dev/cu.usbmodem1101` (or from `.env`), and the settings below with GPIO 10 instead of 13. A fresh C3 boots with 30 LEDs on GPIO 2 and a button on GPIO 0: change the output, and set the button to none. On the C3, `{"rb":true}` does restart it (unlike the ESP-32S boards).

### 4. Wi-Fi and settings

- **Wi-Fi over USB serial:** put the SSID and password in the repo's `.env` (see [`.env.example`](../../.env.example)), then run `fixtures/tubes/scripts/wled_wifi_serial.py`. It uses WLED's Improv serial protocol and prints the address WLED joins at.
- **LED settings** (WLED → Config → LED Preferences, or `POST /json/cfg`): GPIO 13, type WS281x, colour order GRB, length 60, max current 850 mA.
- **Name:** `curl -X POST http://<ip>/json/cfg -d '{"id":{"mdns":"rave-tube-N","name":"Rave Tube N"}}'`, then reboot (`{"rb":true}` to `/json/state`). The mDNS name doubles as the network hostname.
- **Idle look:** Aurora effect, Party palette. WLED shows it whenever the brain isn't streaming.

### 5. Adding it to the show

Add a `strip` fixture to [`brain/showbrain/config.json`](../../brain/showbrain/config.json) with the tube's hostname and `"leds": 60`, then run `brain/deploy.sh showbrain`. The brain streams DDP (UDP 4048) at 50 fps and re-resolves the hostname every 30 s, so a new IP at a venue is picked up automatically.

## Power banks

Measured by WLED's estimate during a show: about 260 mA for the LEDs in groove, with peaks around 470 mA, plus 100–150 mA for the ESP32 on Wi-Fi. Drops hit the 850 mA cap. Plan on about **0.45 A average at 5 V**.

| Bank (as advertised) | Usable at 5 V | Runtime |
|---|---|---|
| 2 000 mAh | ~1.25 Ah | ~2.5–3 h |
| 5 000 mAh | ~3.1 Ah | ~6–7 h |
| 10 000 mAh | ~6.3 Ah | ~12–14 h |

Choose banks with at least 2 A output from brands that rate capacity honestly. Lowering WLED's limit to 600 mA stretches runtime.

## Tools

In [`fixtures/tubes/scripts/`](../../fixtures/tubes/scripts/). Run with a venv that has `bleak` (the Bluetooth tools) or plain Python 3 (the WLED tools).

| Script | Purpose |
|---|---|
| `wled_wifi_serial.py` | Give a USB-connected WLED board Wi-Fi credentials (from `.env`) |
| `wled_markers.py` | Marker pixels (0 white, every 10th red, every 50th blue) to check order and colour |
| `wled_count.py` | Light pixels one by one to find the strip length |
| `ddp_demo.py` | Beat-synced DDP demo reel |
| `presence.py`, `adv_watch.py`, `scan_adv.py`, `inspect_device.py`, `gatt_dump.py` | Bluetooth discovery and inspection (used to identify the stock controller) |
| `probe_notify.py`, `test_led_families.py`, `test_miracles_star.py`, `test_power_on.py` | Protocol probes against the stock controller |

## Background: why not the stock Bluetooth controller

We tried to control the tubes over Bluetooth first, without opening them. Summary:

- The stock controller advertises as **`STARLIGHT`** (service `0x3515`, manufacturer data `ffff1140fd7166ff030400`). An unplug test confirmed that's the tube. A Tuya device (`TY_HS_STACK`) sat nearby at the same signal strength but wasn't the tube.
- Its only Bluetooth interface: service `fff0` with a write characteristic `fff3` and a notify characteristic `fff4`. `fff4` never replied to anything.
- No visible response to the ELK-BLEDOM, ELK `7e07`, LED Lamp `7eff`, Triones or Zengge command families, nor to the Miracles Star format.
- The manual's app (**Miracles Star**, `com.weifeng.lightbar` v1.0.3) was decompiled. It only talks to devices named `Miracles_Star` on service `e0ff`/`ffe1`, so it's built for different firmware. Its plain-byte protocol (`00` off, `01 RR GG BB brightness mode speed`) also did nothing on `fff3`. duoCo Strip and Magic Lantern don't recognise `STARLIGHT` either, nor do two other Lenze apps.
- The paper manual is generic safety text ([manuals/xsd-dd15-tube-manual.pdf](../manuals/xsd-dd15-tube-manual.pdf)).

Swapping in an ESP32 was faster and gives per-pixel control, which the stock firmware never would. Remaining options, if a tube ever needs to stay stock: read the ST17H66 flash over UART (it's a PHY6222 clone; see pvvx/PHY62x2), or capture Bluetooth traffic from a phone app that works.

macOS notes for the Bluetooth tools: `bleak` needs a venv (Homebrew Python refuses a bare `pip install`). On Python 3.14, `BleakScanner.discover(return_adv=True)` crashes; use a `detection_callback`. macOS shows per-machine UUIDs instead of MAC addresses, so scan by name.
