#!/usr/bin/env bash
# Turn a freshly flashed Pi (after make_cloudinit.py + first boot) into a Sektor5 brain.
# Run from the Mac, in the repo. Safe to run again: every step checks before it changes anything.
#
#   brain/provision/setup_brain.sh                      # the brain in S5_BRAIN_HOST (default sektor5.local)
#   brain/provision/setup_brain.sh sektor5-2.local      # another one
#
# Then deploy the code to it (S5_BRAIN_HOST=… brain/deploy.sh), reboot, and set the admin PIN.
# Not done here: Tailscale and collaborator accounts (see docs/brain.md).
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ -f .env ]] && set -a && . ./.env && set +a
HOST=${1:-${S5_BRAIN_HOST:-${RAVE_BRAIN_HOST:-sektor5.local}}}
BRAIN=pi@$HOST
echo "setting up $BRAIN"

# System files and the beat-link download script go over first.
ssh -o StrictHostKeyChecking=accept-new "$BRAIN" 'rm -rf /tmp/s5setup && mkdir -p /tmp/s5setup'
rsync -a brain/system/ brain/deckdash/fetch_libs.sh "$BRAIN":/tmp/s5setup/

ssh "$BRAIN" 'bash -s' <<'REMOTE'
set -euo pipefail
S=/tmp/s5setup
step() { echo "== $*"; }

step "packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install \
  openjdk-21-jdk-headless python3-numpy python3-usb python3-smbus i2c-tools ir-keytable tcpdump alsa-utils flac avahi-utils rsync curl >/dev/null

step "accounts: group rave, service user ravesvc (runs projector + visuals, no login)"
getent group rave >/dev/null || sudo groupadd rave
id ravesvc >/dev/null 2>&1 || sudo useradd --system --gid rave --home-dir /srv/rave --no-create-home --shell /usr/sbin/nologin ravesvc
id -nG pi | grep -qw rave || sudo usermod -aG rave pi

step "shared folders in /srv/rave (pi:rave, group-writable, setgid)"
for d in deckdash-web deckdash-preview projector projector/layouts visuals visuals/state recordings; do
  sudo install -d -o pi -g rave -m 2775 "/srv/rave/$d"
done
sudo chown pi:rave /srv/rave && sudo chmod 2775 /srv/rave

step "code folders and beat-link"
mkdir -p ~/deckdash/web ~/showbrain ~/mixer ~/tools
cp $S/fetch_libs.sh ~/deckdash/
[[ -f ~/deckdash/lib/beat-link-7.4.0.jar ]] || bash ~/deckdash/fetch_libs.sh >/dev/null

step "systemd units, uDMX rule, persistent logs"
for u in deckdash showbrain mixer projector visuals; do sudo install -m 644 $S/$u.service /etc/systemd/system/; done
sudo install -m 644 $S/50-udmx.rules /etc/udev/rules.d/
sudo install -d /etc/systemd/journald.conf.d && sudo install -m 644 $S/journald-rave.conf /etc/systemd/journald.conf.d/rave.conf
sudo systemctl daemon-reload
sudo systemctl enable -q deckdash showbrain mixer projector visuals
sudo udevadm control --reload
sudo systemctl restart systemd-journald

step "I2C and the IR receiver (used by an Argon ONE case: fan + power button chip at 0x1a, IR on GPIO 23); apply at the next boot"
sudo raspi-config nonint do_i2c 0
grep -q "^dtoverlay=gpio-ir," /boot/firmware/config.txt || echo "dtoverlay=gpio-ir,gpio_pin=23   # Argon ONE IR receiver" | sudo tee -a /boot/firmware/config.txt >/dev/null
sudo install -d /usr/local/lib/sektor5 && sudo install -m 755 $S/argon_fan.py /usr/local/lib/sektor5/
sudo install -m 644 $S/argon-fan.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable -q argon-fan && sudo systemctl restart argon-fan   # exits quietly without an Argon case

step "eth0: link-local only for the deck switch (never a default route); applies at the next boot"
# Later netplan files override cloud-init's 50-cloud-init.yaml (which has eth0 on DHCP).
sudo tee /etc/netplan/60-sektor5-eth0.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
      link-local: [ipv4, ipv6]
      optional: true
EOF
sudo chmod 600 /etc/netplan/60-sektor5-eth0.yaml
sudo netplan generate

step "done"
rm -rf $S
echo "$(hostname): $(tr -d '\0' < /proc/device-tree/model), $(java -version 2>&1 | head -1)"
REMOTE

echo
echo "Next: S5_BRAIN_HOST=$HOST brain/deploy.sh, then ssh pi@$HOST 'sudo reboot',"
echo "then set the PIN: ssh -t pi@$HOST 'python3 ~/tools/set_pin.py'"
