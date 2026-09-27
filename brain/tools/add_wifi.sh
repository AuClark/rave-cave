#!/usr/bin/env bash
# Add a Wi-Fi network to a running brain, so it joins it whenever it's in range (the network
# doesn't need to be in range now). cloud-init only reads network-config on the first boot, so
# after that, add networks with this instead of reflashing.
#
#   ssh -t pi@sektor5.local '~/tools/add_wifi.sh "Home Wi-Fi"'     # asks for the password (hidden)
#   ssh pi@sektor5.local 'nmcli -f NAME,TYPE,AUTOCONNECT con show'  # what it knows
set -euo pipefail
ssid=${1:-}
[[ -n $ssid ]] || { read -rp "Wi-Fi name (SSID): " ssid; }
read -rsp "Password for $ssid (hidden): " psk; echo
[[ ${#psk} -ge 8 ]] || { echo "WPA passwords are at least 8 characters." >&2; exit 1; }
name="wifi-$ssid"
sudo nmcli con delete "$name" >/dev/null 2>&1 || true
sudo nmcli con add type wifi ifname wlan0 con-name "$name" ssid "$ssid" \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" connection.autoconnect yes >/dev/null
echo "Added $ssid. Known Wi-Fi networks:"
nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /wireless/ {print "  " $1}'
