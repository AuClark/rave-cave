"""Write cloud-init files for flashing the Rave Cave CM4 (Raspberry Pi OS Trixie).

Takes the Wi-Fi SSID/password from RAVE_WIFI_SSID / RAVE_WIFI_PASSWORD (environment or the repo's
git-ignored .env), otherwise asks in the terminal (password hidden), and writes
user-data + network-config to ~/tools/rpi/cloudinit/, outside the repo so
the password never gets committed.

    python3 brain/provision/make_cloudinit.py

Then flash with:

    "/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager" --cli \
      --cloudinit-userdata ~/tools/rpi/cloudinit/user-data \
      --cloudinit-networkconfig ~/tools/rpi/cloudinit/network-config \
      ~/tools/rpi/2026-09-15-raspios-trixie-arm64-lite.img.xz /dev/diskN
"""
import getpass
import json
import os
from pathlib import Path

# Site values from the repo-root .env (git-ignored), found by walking up to .env.example.
_root = next((p for p in Path(__file__).resolve().parents if (p / ".env.example").exists()), None)
if _root and (_root / ".env").is_file():
    for _line in (_root / ".env").read_text().splitlines():
        if "=" in _line and not _line.lstrip().startswith("#"):
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))

HOSTNAME = "ravecave"
USER = "pi"
TIMEZONE = "Australia/Sydney"
COUNTRY = os.environ.get("RAVE_WIFI_COUNTRY", "AU")
PUBKEY = Path.home() / ".ssh" / "id_ed25519.pub"
OUT = Path.home() / "tools" / "rpi" / "cloudinit"

USER_DATA = """#cloud-config
hostname: {hostname}
manage_etc_hosts: true
timezone: {timezone}
keyboard:
  model: pc105
  layout: us
packages:
  - avahi-daemon
apt:
  conf: |
    Acquire {{
      Check-Date "false";
    }};
users:
  - name: {user}
    groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
    shell: /bin/bash
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - {pubkey}
ssh_pwauth: false
runcmd:
  - [rfkill, unblock, wifi]
  - [sh, -c, 'for f in /var/lib/systemd/rfkill/*:wlan ; do echo 0 > "$f"; done']
  - [systemctl, enable, --now, ssh]
"""

NETWORK_CONFIG = """network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      optional: true
  wifis:
    renderer: NetworkManager
    wlan0:
      dhcp4: true
      optional: true
      regulatory-domain: "{country}"
      access-points:
        {ssid}:
          password: {password}
"""


def main():
    pubkey = PUBKEY.read_text().strip()
    ssid = os.environ.get("RAVE_WIFI_SSID") or input("Wi-Fi SSID: ").strip()
    password = os.environ.get("RAVE_WIFI_PASSWORD") or getpass.getpass("Wi-Fi password (hidden): ")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "user-data").write_text(USER_DATA.format(
        hostname=HOSTNAME, timezone=TIMEZONE, user=USER, pubkey=pubkey))
    # json.dumps gives a safely quoted YAML scalar for odd characters.
    (OUT / "network-config").write_text(NETWORK_CONFIG.format(
        country=COUNTRY, ssid=json.dumps(ssid), password=json.dumps(password)))
    (OUT / "network-config").chmod(0o600)
    print(f"Wrote {OUT}/user-data and {OUT}/network-config")
    print(f"Host {HOSTNAME}, user {USER}, key {PUBKEY.name}, Wi-Fi configured ({COUNTRY}), Ethernet DHCP too.")


if __name__ == "__main__":
    main()
