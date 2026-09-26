#!/usr/bin/env bash
# One-time setup to turn rave-box (Pi 3 A+) from HUB75 panel driver into the WS2815 pyramid driver.
# Run ON rave-box as the normal user (it will ask for the sudo password once):
#
#   bash ~/pyramid/setup_rave_box.sh
#
# Then reboot. The Bonnet must be removed; signal goes GPIO10 (pin 19) -> SP901E DAT 1.
set -euo pipefail
CFG=/boot/firmware/config.txt
CMD=/boot/firmware/cmdline.txt

echo "== Stopping the old panel software"
pkill -f "[d]dp_panel.py" || true
pkill -f "examples-api-use/[l]edcat" || true
pkill -f "[s]olids.sh" || true
( crontab -l 2>/dev/null | grep -v ddp_panel ) | crontab - || true

echo "== Enabling SPI and fixing the core clock (Pi 3 needs a fixed core clock for stable SPI LED timing)"
sudo sed -i 's/^#\?dtparam=spi=.*/dtparam=spi=on/' "$CFG"
grep -q '^dtparam=spi=on' "$CFG" || echo 'dtparam=spi=on' | sudo tee -a "$CFG" >/dev/null
grep -q '^core_freq=250' "$CFG" || printf '\n# WS281x over SPI needs a fixed core clock on Pi 3\ncore_freq=250\ncore_freq_min=250\n' | sudo tee -a "$CFG" >/dev/null

echo "== Enlarging the SPI buffer (600 LEDs need more than the 4 KB default)"
grep -q 'spidev.bufsiz' "$CMD" || sudo sed -i 's/$/ spidev.bufsiz=32768/' "$CMD"

echo "== Groups for SPI/GPIO access without root"
sudo usermod -aG spi,gpio "$USER"

echo "== Installing build tools and rpi_ws281x into ~/pyramid-venv"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-dev build-essential
python3 -m venv ~/pyramid-venv
~/pyramid-venv/bin/pip install -q rpi_ws281x

echo "== Installing the pyramid service (starts on boot)"
sudo tee /etc/systemd/system/pyramid.service >/dev/null <<EOF
[Unit]
Description=Rave Cave pyramid (WS2815 via SPI, DDP receiver)
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/pyramid
ExecStart=$HOME/pyramid-venv/bin/python -u ddp_ws281x.py --leds 600 --max-amps 5
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable pyramid

echo
echo "Done. Reboot now for SPI, the core clock and the buffer size to take effect:  sudo reboot"
