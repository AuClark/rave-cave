"""Write cloud-init files for flashing the Sektor5 CM4 (Raspberry Pi OS Trixie).

Takes the Wi-Fi SSID/password from S5_WIFI_SSID / S5_WIFI_PASSWORD (or the old RAVE_* names) (environment or the repo's
git-ignored .env), otherwise asks in the terminal (password hidden), and writes
user-data + network-config to ~/tools/rpi/cloudinit/, outside the repo so
the password never gets committed.

    python3 brain/provision/make_cloudinit.py
    python3 brain/provision/make_cloudinit.py --add-wifi    # add another network (e.g. home) to the existing files

The brain can know several Wi-Fi networks (workshop, home…) and joins whichever is in range:
S5_WIFI_SSID / S5_WIFI_PASSWORD, plus S5_WIFI2_SSID / S5_WIFI2_PASSWORD, S5_WIFI3_… in .env, or
answer the prompts. --add-wifi keeps the networks already in network-config and prompts for one more.

Then flash with:

    "/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager" --cli \
      --cloudinit-userdata ~/tools/rpi/cloudinit/user-data \
      --cloudinit-networkconfig ~/tools/rpi/cloudinit/network-config \
      ~/tools/rpi/2026-09-15-raspios-trixie-arm64-lite.img.xz /dev/diskN
"""
import getpass
import json
import os
import re
import sys
from pathlib import Path

# Site values from the repo-root .env (git-ignored), found by walking up to .env.example.
_root = next((p for p in Path(__file__).resolve().parents if (p / ".env.example").exists()), None)
if _root and (_root / ".env").is_file():
    for _line in (_root / ".env").read_text().splitlines():
        if "=" in _line and not _line.lstrip().startswith("#"):
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))

HOSTNAME = os.environ.get("S5_HOSTNAME") or os.environ.get("RAVE_HOSTNAME") or "sektor5"   # e.g. S5_HOSTNAME=sektor5-2 for a second brain
USER = "pi"
TIMEZONE = "Australia/Sydney"
COUNTRY = os.environ.get("S5_WIFI_COUNTRY", os.environ.get("RAVE_WIFI_COUNTRY", "AU"))
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
{access_points}"""

AP = """        {ssid}:
          password: {password}
"""


def env(*names):
    return next((os.environ[n] for n in names if os.environ.get(n)), None)


def networks_from_env():
    """[(ssid, password)] from S5_WIFI_* then S5_WIFI2_*, S5_WIFI3_… (old RAVE_* names too)."""
    nets = []
    for i in ["", "2", "3", "4", "5"]:
        ssid = env(f"S5_WIFI{i}_SSID", f"RAVE_WIFI{i}_SSID")
        if ssid:
            nets.append((ssid, env(f"S5_WIFI{i}_PASSWORD", f"RAVE_WIFI{i}_PASSWORD") or getpass.getpass(f"Password for {ssid} (hidden): ")))
    return nets


def networks_from_file(path):
    """The access points already in a network-config this script wrote (values are JSON-quoted)."""
    if not path.is_file():
        return []
    return [(json.loads(a), json.loads(b)) for a, b in
            re.findall(r'^\s+("(?:[^"\\]|\\.)*"):\n\s+password: ("(?:[^"\\]|\\.)*")$', path.read_text(), re.M)]


def prompt_network(first=True):
    ssid = input("Wi-Fi SSID: " if first else "Another Wi-Fi SSID (Enter to finish): ").strip()
    return (ssid, getpass.getpass(f"Password for {ssid} (hidden): ")) if ssid else None


def write_network_config(nets):
    aps = "".join(AP.format(ssid=json.dumps(s), password=json.dumps(p)) for s, p in nets)   # json.dumps: safely quoted YAML
    (OUT / "network-config").write_text(NETWORK_CONFIG.format(country=COUNTRY, access_points=aps))
    (OUT / "network-config").chmod(0o600)
    print(f"Wrote {OUT}/network-config with {len(nets)} Wi-Fi network(s): " + ", ".join(s for s, _ in nets))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if "--add-wifi" in sys.argv:
        nets = networks_from_file(OUT / "network-config")
        new = prompt_network()
        if new:
            nets = [n for n in nets if n[0] != new[0]] + [new]   # re-adding a network replaces its password
        write_network_config(nets)
        return
    pubkey = PUBKEY.read_text().strip()
    nets = networks_from_env()
    if not nets:
        n = prompt_network()
        while n:
            nets.append(n)
            n = prompt_network(first=False)
    (OUT / "user-data").write_text(USER_DATA.format(
        hostname=HOSTNAME, timezone=TIMEZONE, user=USER, pubkey=pubkey))
    print(f"Wrote {OUT}/user-data (host {HOSTNAME}, user {USER}, key {PUBKEY.name})")
    write_network_config(nets)


if __name__ == "__main__":
    main()
