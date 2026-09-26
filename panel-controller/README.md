# Rave Cave Panel Controller

**The small HUB75 LED panel system: four PH6 panels driven by `rave-box`, plus a Flask status/camera web UI.**

This folder is separate from the main Pi 4B / StageLinQ rig. It holds the web server code for `rave-box`, the panel test log, and display build ideas.

- **[PANEL-TEST-LOG.md](PANEL-TEST-LOG.md)**: test register, fault findings, bring-up guide, panel scorecard
- **[IDEAS.md](IDEAS.md)**: display build ideas (infinity mirror, pillar, diffusers) and AU acrylic suppliers

## Current Status (Sep 2026)

- Pi + Bonnet + hzeller library: **working** (demos and RGB washes run).
- Panels: all four light up, but they show dead patches, horizontal black lines and vertical notches. The faults sit in the same places in solid R, G and B, which points to interconnects (ribbons, IDC connectors) or old tiles rather than software or single LEDs. See the test log.
- Software config: tests so far used `--led-chain=1` at 32×16 even though several panels were physically chained. **Chain/rows/cols settings need correcting** before judging the chained output.
- Power: still showing undervoltage warnings, even on the 5V brick through the barrel jack.
- Camera: enumerates, but CSI capture times out. **Parked.**
- Web UI: running on `:8080`.

## Hardware

### Panels
- **Model**: YR PH6-8S-V1.2 outdoor HUB75 modules
- **Size**: 192 × 96 mm, about 13–18 mm thick
- **Resolution**: 32 × 16 pixels, 6 mm pitch, 1/8 scan
- **Count**: four, labelled **A–D**, daisy-chained (IN → OUT ribbons)
- Combined as a 4-panel chain: 128 × 16 px logical (`--led-chain=4`), whatever the physical arrangement
- (The original PR also mentioned an optional P2.5 panel; it isn't part of the current build.)

### Controller: `rave-box`
- **Pi**: Raspberry Pi 3 Model A+
- **Bonnet**: genuine Adafruit RGB Matrix Bonnet (ADA3211), bought from Core Electronics. No HAT EEPROM, so detection is best-effort (see below).
- **Replaced**: a BeagleBone, which was dead (no power LED, no Ethernet link).
- **Network**: `192.168.20.36` (DHCP) on the FT Hangar workshop Wi‑Fi; Nimbitz kept as a fallback profile. Use `rave-box.local` if the IP changes
- **Access**: user `raver`, SSH key auth via the `rave-box` Host entry in `~/.ssh/config` (`ssh rave-box`). No password is kept in this repo.
- **Power**: 5V brick into the Bonnet barrel jack (not the Pi's micro-USB). Undervoltage warnings still appeared after the switch, so check `vcgencmd get_throttled` before trusting any panel test.

### Camera
- **Pi Camera Rev 1.3** (OV5647 / Camera Module v1). It enumerates (shows in the device tree / I2C), but CSI capture times out. Likely the ribbon or undervoltage.
- **Parked.** Next step: reseat the ribbon (blue tab towards the Ethernet/USB side). No need to reflash the SD card.

## Software

- **hzeller/rpi-rgb-led-matrix** is installed on the Pi at `~/rpi-rgb-led-matrix`. Use mapping `adafruit-hat` and `--led-slowdown-gpio=2`.
- **panel-controller Flask UI** (this folder) runs on port **8080**: status page, JSON API, MJPEG camera stream.

### Web UI tips
- **Use Safari.** Chrome often fails to reach the LAN IP (`ERR_ADDRESS_UNREACHABLE`) while Safari works.
- On the deployed UI the MJPEG stream stays **off until you press "Start stream"**, because auto-streaming wedged the browser. Note: `server.py` as committed in this PR still embeds `/stream.mjpg` straight away, so the repo copy needs the same change if it isn't already synced from the Pi.

### Panel config (correct settings)

For four 32×16 panels in one chain:

```bash
cd ~/rpi-rgb-led-matrix/examples-api-use
sudo ./demo -D0 --led-gpio-mapping=adafruit-hat --led-slowdown-gpio=2 \
  --led-rows=16 --led-cols=32 --led-chain=4 --led-brightness=40
```

- `--led-chain` must match the number of panels physically connected (1 while testing a single panel).
- If the image looks split or interleaved on these 1/8-scan outdoor tiles, try the `--led-multiplexing=` options before blaming hardware.
- Commands that have worked so far are in [PANEL-TEST-LOG.md](PANEL-TEST-LOG.md).

## Quick Start (web server)

### 1. Install Dependencies

Prefer system packages (faster, tested on Raspberry Pi OS):

```bash
sudo apt update
sudo apt install -y python3-flask python3-picamera2 python3-pil i2c-tools
```

Or pip fallback (if system packages unavailable):

```bash
pip3 install -r requirements.txt
```

### 2. Enable Camera + I2C

```bash
# Enable camera (libcamera stack, Bookworm default)
sudo raspi-config nonint do_camera 0

# Enable i2c (for HAT EEPROM probing, optional)
sudo raspi-config nonint do_i2c 0

# Reboot
sudo reboot
```

### 3. Test Hardware Probing

```bash
cd /home/raver/panel-controller
python3 hw.py
```

Should show Pi model, HAT/Bonnet info (may be empty — Bonnet often has no EEPROM), and camera details.

### 4. Run the Server

```bash
python3 server.py
```

Open in Safari: **http://192.168.20.36:8080/** or **http://rave-box.local:8080/**

- **`GET /`** — Status page with MJPEG camera feed (dark theme)
- **`GET /api/status`** — JSON: hostname, model, camera, bonnet, uptime, memory
- **`GET /stream.mjpg`** — Raw MJPEG stream

### 5. Install as systemd Service (Optional)

Run automatically on boot:

```bash
sudo cp systemd/rave-panel-controller.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rave-panel-controller.service
sudo systemctl start rave-panel-controller.service
sudo systemctl status rave-panel-controller.service
```

Logs:

```bash
sudo journalctl -u rave-panel-controller.service -f
```

## Bonnet Detection Notes

The Adafruit RGB Matrix Bonnet (ADA3211) typically **does NOT have a HAT EEPROM**, so `hw.py` won't find it via `/proc/device-tree/hat` or `i2cdetect -y 1` at address 0x50. This is **expected and normal**.

Detection is best-effort:
- Probe via device tree and i2c (both likely fail)
- Later: confirm GPIO pins in use when `rpi-rgb-led-matrix` is running

The web UI will show `? Best-effort` / `No EEPROM (expected)`. That's fine.

## Files

- **`server.py`** — Flask app (MJPEG stream, status page, JSON API)
- **`hw.py`** — Hardware probing (Pi model, HAT/Bonnet, camera, uptime, memory)
- **`requirements.txt`** — Python deps (prefer system packages)
- **`systemd/rave-panel-controller.service`** — systemd unit for auto-start
- **`PANEL-TEST-LOG.md`** — Panel testing register: commands that worked, session observations, bring-up guide, scorecard
- **`IDEAS.md`** — Display build ideas and supplier notes
- **`README.md`** — This file

## Troubleshooting

**Camera not detected / capture times out:**
- Reseat the ribbon cable at both ends (blue tab towards the Ethernet/USB side)
- Fix undervoltage first (`vcgencmd get_throttled`)
- Enable camera: `sudo raspi-config nonint do_camera 0 && sudo reboot`
- Test: `rpicam-hello --list-cameras` or `libcamera-hello --list-cameras`

**Server crashes on start:**
- Check `python3-picamera2` installed: `dpkg -l | grep picamera2`
- Check camera not in use: `sudo fuser /dev/video0`

**Bonnet shows "Not Found":**
- Expected! Bonnet has no EEPROM. GPIO detection later when running matrix code.

**Can't access from browser:**
- Use Safari (Chrome often can't reach the LAN IP)
- Check Pi is on network: `ping 192.168.20.36` or `ping rave-box.local`
- Check server running: `sudo systemctl status rave-panel-controller.service`
- Check firewall: Pi OS Lite usually has no firewall, but `sudo ufw allow 8080` if needed

**Browser hangs on the status page:**
- Leave the stream off and only press "Start stream" when you need the camera.

## References

- [Adafruit RGB Matrix Bonnet](https://www.adafruit.com/product/3211)
- [rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix)
- [picamera2 docs](https://datasheets.raspberrypi.com/camera/picamera2-manual.pdf)
- [Raspberry Pi Camera setup](https://www.raspberrypi.com/documentation/computers/camera_software.html)

---

**User:** `raver` (SSH key auth, `ssh rave-box`)  
**Hostname:** `rave-box`  
**IP:** 192.168.20.36 (FT Hangar Wi‑Fi, DHCP)  
**URL:** http://rave-box.local:8080/ (use Safari)
