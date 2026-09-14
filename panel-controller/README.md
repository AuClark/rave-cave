# Rave Cave Panel Controller

**Live camera feed + hardware status for the HUB75 LED panel rig.**

Simple Flask web server for `rave-box` (Raspberry Pi 3 Model A+) with Adafruit RGB Matrix Bonnet (ADA3211) and Pi Camera (OV5647 / Camera Module v1). Check camera feed, Pi model, Bonnet detection, and system health from any browser on the LAN.

## Hardware

- **Pi**: Raspberry Pi 3 Model A+ (`rave-box`, 192.168.0.36)
- **Bonnet**: Adafruit RGB Matrix Bonnet (ADA3211) — may not have HAT EEPROM, detection is best-effort
- **Camera**: Pi Camera Module v1 (OV5647, shows in device tree)
- **Panels**: 1–4 HUB75 panels (PH6 outdoor + optional P2.5) — **not yet connected**

## Quick Start

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

Open in a browser: **http://192.168.0.36:8080/** or **http://rave-box.local:8080/**

- **`GET /`** — Status page with live MJPEG camera feed (dark theme)
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

Detection will be best-effort:
- Probe via device tree and i2c (both likely fail)
- Later: confirm GPIO pins in use when `rpi-rgb-led-matrix` is running

The web UI will show `? Best-effort` / `No EEPROM (expected)` — this is fine.

## HUB75 Panels (Coming Soon)

**Panels not yet connected.** When wiring them up, use [hzeller/rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix):

```bash
git clone https://github.com/hzeller/rpi-rgb-led-matrix.git
cd rpi-rgb-led-matrix
make -C examples-api-use
sudo examples-api-use/demo -D0 --led-gpio-mapping=adafruit-hat --led-rows=32 --led-cols=64
```

Key flags for Adafruit Bonnet:
- `--led-gpio-mapping=adafruit-hat`
- `--led-rows=32` / `--led-cols=64` (or whatever your panels are)
- `-D0` (no daemon, test mode)

See [rpi-rgb-led-matrix docs](https://github.com/hzeller/rpi-rgb-led-matrix) for Python bindings and more.

## Files

- **`server.py`** — Flask app (MJPEG stream, status page, JSON API)
- **`hw.py`** — Hardware probing (Pi model, HAT/Bonnet, camera, uptime, memory)
- **`requirements.txt`** — Python deps (prefer system packages)
- **`systemd/rave-panel-controller.service`** — systemd unit for auto-start
- **`PANEL-TEST-LOG.md`** — Panel testing register: commands that worked, session observations, bring-up guide, scorecard
- **`README.md`** — This file

## Troubleshooting

**Camera not detected:**
- Check ribbon cable (blue tab towards Ethernet port)
- Enable camera: `sudo raspi-config nonint do_camera 0 && sudo reboot`
- Test: `rpicam-hello --list-cameras` or `libcamera-hello --list-cameras`

**Server crashes on start:**
- Check `python3-picamera2` installed: `dpkg -l | grep picamera2`
- Check camera not in use: `sudo fuser /dev/video0`

**Bonnet shows "Not Found":**
- Expected! Bonnet has no EEPROM. GPIO detection later when running matrix code.

**Can't access from browser:**
- Check Pi is on network: `ping 192.168.0.36` or `ping rave-box.local`
- Check server running: `sudo systemctl status rave-panel-controller.service`
- Check firewall: Pi OS Lite usually has no firewall, but `sudo ufw allow 8080` if needed

## References

- [Adafruit RGB Matrix Bonnet](https://www.adafruit.com/product/3211)
- [rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix)
- [picamera2 docs](https://datasheets.raspberrypi.com/camera/picamera2-manual.pdf)
- [Raspberry Pi Camera setup](https://www.raspberrypi.com/documentation/computers/camera_software.html)

---

**User:** `raver`  
**Hostname:** `rave-box`  
**IP:** 192.168.0.36  
**URL:** http://rave-box.local:8080/
