#!/usr/bin/env bash
# Flash Raspberry Pi OS + the cloud-init files from make_cloudinit.py onto a microSD card (Pi 4)
# or the CM4's eMMC (after rpiboot). Only writes to an external, removable disk, and asks first.
#
#   brain/provision/flash_card.sh              # lists external disks and asks which one
#   brain/provision/flash_card.sh disk9        # that disk (still shows it and asks)
#   S5_IMAGE=~/Downloads/other.img.xz brain/provision/flash_card.sh disk9
#
# The image defaults to the newest ~/tools/rpi/*raspios*arm64-lite*.img.xz (Raspberry Pi OS Lite
# 64-bit; download from https://www.raspberrypi.com/software/operating-systems/).
set -euo pipefail
IMAGER="/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager"
CI=~/tools/rpi/cloudinit
die() { echo "flash: $*" >&2; exit 1; }

[[ -x $IMAGER ]] || die "Raspberry Pi Imager isn't installed (https://www.raspberrypi.com/software/)."
[[ -f $CI/user-data && -f $CI/network-config ]] || die "no cloud-init files in $CI. Run brain/provision/make_cloudinit.py first."
IMAGE=${S5_IMAGE:-$(ls -t ~/tools/rpi/*raspios*arm64-lite*.img.xz 2>/dev/null | head -1 || true)}
[[ -f $IMAGE ]] || die "no image. Put Raspberry Pi OS Lite 64-bit (.img.xz) in ~/tools/rpi/ or set S5_IMAGE."

external() { diskutil list external physical | awk '/^\/dev\/disk/ {sub("/dev/",""); print $1}'; }
disk=${1:-}
if [[ -z $disk ]]; then
  # Card readers behind USB hubs can drop out for a moment: give it a few seconds.
  for _ in 1 2 3 4 5 6; do [[ -n $(external) ]] && break; sleep 2; done
  [[ -n $(external) ]] || die "no external disk. Check the card is pushed in and the reader is connected (straight into the Mac is most reliable)."
  diskutil list external physical
  read -rp "Which disk (e.g. disk9)? " disk
fi
disk=${disk#/dev/}
info=$(diskutil info "/dev/$disk" 2>/dev/null) || die "/dev/$disk not found (the reader may have dropped out: reconnect it and try again)."
grep -q 'Device Location: *External' <<<"$info" || die "/dev/$disk isn't external. Refusing."
grep -Eq 'Removable Media: *(Removable|Yes)' <<<"$info" || grep -q 'Protocol: *USB' <<<"$info" || die "/dev/$disk isn't removable or USB. Refusing."
name=$(awk -F': *' '/Device \/ Media Name/ {print $2}' <<<"$info")
size=$(awk -F': *' '/Disk Size/ {print $2}' <<<"$info" | cut -d'(' -f1)
host=$(awk '/^hostname:/ {print $2}' "$CI/user-data")
nets=$(python3 -c 'import re,sys,json; print(", ".join(json.loads(m) for m in re.findall(r"^\s+(\"(?:[^\"\\]|\\.)*\"):\n\s+password:", open(sys.argv[1]).read(), re.M)))' "$CI/network-config")

echo
echo "  disk:     /dev/$disk  ($name, $size)"
echo "  image:    $(basename "$IMAGE")"
echo "  hostname: $host"
echo "  Wi-Fi:    $nets"
echo
read -rp "Erase /dev/$disk and flash it? Type yes: " ok
[[ $ok == yes ]] || die "cancelled."

diskutil unmountDisk "/dev/$disk" >/dev/null
"$IMAGER" --cli --cloudinit-userdata "$CI/user-data" --cloudinit-networkconfig "$CI/network-config" "$IMAGE" "/dev/$disk"
echo
echo "Done (Imager has ejected it). Boot the Pi from it, wait 2-3 minutes, then: ssh pi@$host.local"
