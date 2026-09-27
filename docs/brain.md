# The brain (`sektor5`)

The computer that reads the decks and runs the show. Code: [`brain/`](../brain/).

- **Hardware:** a Raspberry Pi with 4 GB RAM and Wi-Fi. `sektor5` is a Compute Module 4 (32 GB eMMC) on a carrier board with heatsink and fan; `sektor5-2` is a Raspberry Pi 4 Model B on a microSD card. Power either from a solid 5 V / 3 A USB-C supply: a bad cable caused brownouts. The CM4's fan runs flat out from 5 V: at full load the CPU stays under 40 °C.
- **OS:** Raspberry Pi OS Lite 64-bit (Debian 13), user `pi`, SSH key login only.
- **Network:** Ethernet to the deck switch (link-local only, never the default route), Wi-Fi to the fixtures and the rest of the network.
- **Services:** `deckdash` (dashboard :8080), `showbrain` (Commander :8090), `mixer` (DJM-450 USB bridge) `projector` (projection mapping :8100, opened in Chrome on the projector) and `visuals` (generative visuals control :8110, see [visuals.md](visuals.md)). All start on boot and restart on failure.

## Set up a new brain

From a blank card to a working brain in about 30 minutes, mostly waiting. Everything runs from the Mac, in this repo, on a clean `main`.

**You need:** a Pi 4 (4 GB) and a microSD card of 32 GB or more in a card reader, or a CM4 with eMMC on its carrier; a 5 V / 3 A USB-C supply; [Raspberry Pi Imager](https://www.raspberrypi.com/software/); Raspberry Pi OS Lite 64-bit (`.img.xz`) in `~/tools/rpi/`; your SSH key in `~/.ssh/id_ed25519.pub`. The Mac must be on the same Wi-Fi as the brain for the `.local` names to work.

1. **Write the first-boot config.** Pick a name that isn't already on the network (`sektor5` is taken):
   ```bash
   S5_HOSTNAME=sektor5-2 python3 brain/provision/make_cloudinit.py
   ```
   It asks for every Wi-Fi network the brain should know (workshop, home…) and joins whichever is in range. Passwords are typed hidden and stay in `~/tools/rpi/cloudinit/`, outside the repo. Forgot one? `python3 brain/provision/make_cloudinit.py --add-wifi`.
2. **Flash it.** Pi 4: put the card in the reader. CM4: set the boot jumper and run `rpiboot` first (see step 1 below).
   ```bash
   brain/provision/flash_card.sh
   ```
   It only offers external, removable disks, shows the disk, image, hostname and Wi-Fi networks, and asks you to type `yes`. Imager ejects the card when it's done.
3. **Boot it.** Card in the Pi (or remove the CM4's jumper), power on, wait 2–3 minutes, then `ssh pi@sektor5-2.local`.
4. **Set it up** (packages, accounts, folders, services, deck Ethernet):
   ```bash
   brain/provision/setup_brain.sh sektor5-2.local
   ```
5. **Deploy the code** and reboot:
   ```bash
   S5_BRAIN_HOST=sektor5-2.local brain/deploy.sh
   ssh pi@sektor5-2.local 'sudo reboot'
   ```
6. **Set the admin PIN** (typed hidden): `ssh -t pi@sektor5-2.local 'python3 ~/tools/set_pin.py'`
7. **Check it.** Open `http://sektor5-2.local:8080/` and click the logo: the System view should show every service running and no under-voltage. With no decks connected, the strip at the bottom offers **Start simulation**, which runs the whole rig on a synthetic DJ set ([sim.md](sim.md#on-the-brain)).
8. **Optional:** [Tailscale](#remote-access-tailscale) for remote access and a public link (set the PIN first), and [accounts for collaborators](#access-for-collaborators).

To work on it from the Mac, put `S5_BRAIN_HOST=sektor5-2.local` in front of `brain/deploy.sh …`, or in `.env`.

### If something goes wrong

- **The card doesn't show up on the Mac.** Card readers behind USB hubs and docks drop out (the hub's USB 3 side disconnects). Plug the reader straight into the Mac and push the card fully in; `diskutil list external` should list it.
- **A card with only `recovery.bin`, `pieeprom.bin` and `vl805.bin` on it** is the Pi 4 bootloader recovery image, not an OS. It's fine for updating a new Pi 4's firmware (boot it once: the green LED blinks fast when done), then flash the card properly.
- **The brain never appears on the network.** It only knows the networks you gave `make_cloudinit.py`, and it reads them on the first boot only: changing the file on the card afterwards does nothing. Either reflash, or plug the Pi into your router with a network cable (Ethernet uses DHCP until `setup_brain.sh` runs) and add the network: `ssh -t pi@sektor5-2.local '~/tools/add_wifi.sh "Home Wi-Fi"'`.
- **Nothing on USB when the Pi is plugged into the Mac.** Normal: the Pi 4's USB-C port only takes power. A Mac port may not supply enough for a Pi 4; check `vcgencmd get_throttled` is `0x0`.
- **`ssh` warns the host key changed** after reflashing a card with the same name: `ssh-keygen -R sektor5-2.local`.

## What the setup does, step by step

The scripts above do all of this. It's here for reference, and for building a brain by hand.

### 1. Flash the eMMC (from a Mac)

1. Set the carrier's USB boot jumper and connect its USB port to the Mac. It shows up as `BCM2711 Boot`.
2. Build and run `rpiboot` (from [raspberrypi/usbboot](https://github.com/raspberrypi/usbboot), needs `brew install libusb pkgconf`). The eMMC appears as a disk.
3. Put the Wi-Fi SSID and password in the repo's `.env` ([`.env.example`](../.env.example)), then write the cloud-init files:
   ```bash
   python3 brain/provision/make_cloudinit.py      # writes ~/tools/rpi/cloudinit/ (outside the repo)
   ```
   It asks for as many Wi-Fi networks as you like (workshop, home…); the brain joins whichever is in range. `--add-wifi` adds one more to files you've already written, keeping the rest. In `.env` they're `S5_WIFI_SSID`/`S5_WIFI_PASSWORD`, `S5_WIFI2_…`, `S5_WIFI3_…`.
   This sets hostname `sektor5` (`S5_HOSTNAME` in `.env` to change it), user `pi` with your `~/.ssh/id_ed25519.pub`, no password login, Australia/Sydney, Wi-Fi, and `avahi-daemon`.
4. Flash with Raspberry Pi Imager's command-line mode:
   ```bash
   "/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager" --cli \
     --cloudinit-userdata ~/tools/rpi/cloudinit/user-data \
     --cloudinit-networkconfig ~/tools/rpi/cloudinit/network-config \
     raspios-trixie-arm64-lite.img.xz /dev/diskN
   ```
5. Remove the boot jumper and power-cycle. First boot takes 2–3 minutes. Then `ssh pi@sektor5.local`.


### 2. Network: Ethernet to the decks

The deck switch has no router or DHCP. The decks give themselves 169.254.x.x addresses, so the brain does the same on `eth0` and never routes through it:

```bash
sudo nmcli con mod netplan-eth0 ipv4.method link-local ipv4.never-default yes \
  ipv6.method link-local ipv6.never-default yes
```

On Raspberry Pi OS the NetworkManager profile is generated by netplan. Also put `dhcp4: false`, `dhcp6: false` and `link-local: [ipv4, ipv6]` under `eth0` in `/etc/netplan/90-NM-*.yaml` so it survives regeneration. IP forwarding stays off, so the brain never bridges the deck network and Wi-Fi.

Plug `eth0` into a free port on the deck switch. Every device connects to the switch; don't also cable the decks to each other, or you create a loop.

### 3. Packages and system config

**One command does this step, the `/srv/rave` folders and accounts, the eth0 link-local setup (step 2) and the beat-link download (step 4)**, from the Mac:

```bash
brain/provision/setup_brain.sh sektor5-2.local     # or no argument for S5_BRAIN_HOST / sektor5.local
S5_BRAIN_HOST=sektor5-2.local brain/deploy.sh      # then the code
ssh pi@sektor5-2.local 'sudo reboot'               # eth0 switches to link-local at boot
```

It's safe to run again. What it does, by hand:

```bash
sudo apt-get update && sudo apt-get -y full-upgrade
sudo apt-get -y install openjdk-21-jdk-headless python3-numpy python3-usb tcpdump alsa-utils flac avahi-utils
```

Accounts and folders: group `rave`, system user `ravesvc` (group `rave`, no login), `pi` in `rave`, and `/srv/rave/{deckdash-web,deckdash-preview,projector,visuals,recordings}` owned `pi:rave`, mode `2775`. eth0: `/etc/netplan/60-sektor5-eth0.yaml` with `dhcp4: false`, `dhcp6: false`, `link-local: [ipv4, ipv6]`.

From [`brain/system/`](../brain/system/):

| File | Install to | Purpose |
|---|---|---|
| `deckdash.service`, `showbrain.service`, `mixer.service`, `projector.service`, `visuals.service` | `/etc/systemd/system/` | The services (then `sudo systemctl enable deckdash showbrain mixer projector visuals`) |
| `50-udmx.rules` | `/etc/udev/rules.d/` | Lets the `pi` user drive the uDMX (par can) without root |
| `journald-rave.conf` | `/etc/systemd/journald.conf.d/rave.conf` | Persistent logs, capped at 100 MB |
| `avahi-alias-ravecave.service` | `/etc/systemd/system/` | Transition only: also answers the old name `ravecave.local` (needs `avahi-utils`). Only on the brain renamed from `ravecave`; remove it once nothing uses the old name. |

### 4. Code

From the Mac, in the repo:

```bash
ssh pi@sektor5.local 'mkdir -p ~/deckdash/web ~/showbrain'
scp brain/deckdash/fetch_libs.sh pi@sektor5.local:deckdash/ && ssh pi@sektor5.local 'bash ~/deckdash/fetch_libs.sh'
brain/deploy.sh          # copies every brain service, compiles, restarts them
```

It refuses unless your checkout is a clean `main` matching `origin/main`. To test a pull request use `brain/deploy.sh --pr N <target>`, and `brain/deploy.sh live` to go back to `main`. See [CONTRIBUTING.md](../CONTRIBUTING.md#deploying-to-the-rig). Each deploy records its commit in `~/.deployed/<target>` on the Pi.

`deploy.sh` also copies the repo's `.env` to the Pi (as `~/showbrain/.env`) if present. It's never committed.

## How the two services fit together

- **deckdash** ([`brain/deckdash/`](../brain/deckdash/)) is the only process on the DJ Link network. It joins as virtual player 7, which stays clear of the decks' numbers. Metadata comes from the rekordbox export over NFS (CrateDigger), because the players' database server only answers to players 1–4.
  - Web: `/` dashboard, `/api/state`, `/api/events` (SSE), `/api/art/N`, `/api/waveform/N`, `/api/wavedetail/N`, `/api/timeline/N`.
  - Pushes beat events and 20 Hz status to `showbrain` over UDP on localhost:9100.
- **showbrain** ([`brain/showbrain/`](../brain/showbrain/)) runs the scenes. See [show-engine.md](show-engine.md). Fixtures are listed in `config.json`, where hosts can use `${VAR:-default}` from `.env`.
- **tools/prodj_listen.py** is a receive-only Pro DJ Link decoder, useful for checking a new deck setup without joining the network.

## Access for collaborators

Each collaborator gets their own account on the brain, never the `pi` user (which has passwordless root and runs the show).

| Account | Can | Can't |
|---|---|---|
| `pi` | Everything (owner) | |
| `richard` | Edit the dashboard page in `/srv/rave/deckdash-web` (live) and `/srv/rave/deckdash-preview`; `sudo systemctl restart deckdash` / `status deckdash`; read logs (`systemd-journal` group) | Touch `showbrain`, the fixtures, system config, or anything else as root |
| `chris` | Edit the projection mapping and generative visuals in `/srv/rave/projector` and `/srv/rave/visuals` (code, sketches, saved layouts and presets); `sudo systemctl restart` / `status` for `projector` and `visuals`; read logs | Touch `showbrain`, `deckdash`, the fixtures, system config, or anything else as root |
| `ravesvc` | Runs the `projector` and `visuals` services (no login, no sudo, group `rave`), so editing their code never gives anyone root | |

Shared folders are owned by `pi:rave`, group-writable and setgid, so files stay editable by the group. The narrow sudo rule lives in `/etc/sudoers.d/<user>`.

**Adding someone:**
```bash
sudo adduser --disabled-password --gecos "Name" name
sudo usermod -aG rave,systemd-journal name
sudo install -d -m 700 -o name -g name /home/name/.ssh
echo "<their ssh-ed25519 public key>" | sudo tee /home/name/.ssh/authorized_keys
sudo chown name:name /home/name/.ssh/authorized_keys && sudo chmod 600 /home/name/.ssh/authorized_keys
```
Removing them: `sudo deluser --remove-home name` (and delete any `/etc/sudoers.d/name`).

**Working on projection mapping and visuals (Chris):**
- Code lives in `/srv/rave/projector` and `/srv/rave/visuals`, and runs as `ravesvc`. Edit in place over SSH (`ssh chris@sektor5.local`), then `sudo systemctl restart visuals` (or `projector`). A new sketch in `/srv/rave/visuals/sketches/` shows up in the control page's menu after a restart.
- Page-only changes (`web/`) just need a browser reload.
- Anything worth keeping goes into a PR. `brain/deploy.sh projector` / `visuals` overwrites the code with what's in git (saved layouts, presets and live values are kept).

**Working on the dashboard page:**
- `http://sektor5.local:8080/` serves `/srv/rave/deckdash-web/index.html`, re-read on every request (no restart).
- `http://sektor5.local:8080/preview/` serves `/srv/rave/deckdash-preview/`, a work-in-progress copy with the same live data. Break it freely.
- API reference: [api.md](api.md). The API allows cross-origin requests, so the page can also be developed on a laptop against `http://sektor5.local:8080/api/...`.
- From the repo: `brain/deploy.sh preview` (test) and `brain/deploy.sh web` (live). Live changes go through a PR to `main` first.

## Admin PIN (viewers and admins)

Anyone can open the pages and watch. **Changing anything needs admin**: loading or playing tracks, tempo, the Commander, projection layouts, visuals. Each service enforces this itself: a change without the admin cookie gets `401`. So hiding a button isn't what protects the rig.

- **Unlocking:** enter the PIN once (any page: the VIEW ONLY badge bottom-right, or the prompt that appears when you try to change something). The browser gets a signed `s5_admin` cookie for 5 years. Cookies are per host, not per port, so one unlock covers every page on that address (`sektor5.local`, the Tailscale name and the public link each need one unlock).
- **Locking a browser:** click the ADMIN badge.
- **Set or change the PIN** (hidden input, stored only as a salted PBKDF2 hash in `/srv/rave/auth.json`, group `rave`, mode 640):
  ```bash
  brain/deploy.sh tools                                # once, copies set_pin.py to the brain
  ssh -t pi@sektor5.local 'python3 ~/tools/set_pin.py'
  ```
  Changing the PIN signs every browser out. `--sign-out` keeps the PIN and signs everyone out (lost phone); `--off` removes it. Services pick changes up immediately.
- **Brute force:** each check takes about 0.5 s, and 8 wrong PINs in 10 minutes lock PIN entry for 10 minutes (per service). Use 6+ digits if the rig is on a public link.
- **Until a PIN is set, auth is off** and everyone is admin, as before.
- Code: `brain/common/s5auth.py` (Python services) and `brain/deckdash/Auth.java` (same token format, so the cookie works on every port). `brain/common/web/s5auth.js` is the shared page script. `deploy.sh` copies these into each service.

## Remote access (Tailscale)

The brain is on the owner's tailnet as `sektor5` (MagicDNS `sektor5.<tailnet>.ts.net`; the real name is in the Tailscale admin console, not in git).

- **Public link (Tailscale Funnel):** only the dashboard is published, at `https://sektor5.<tailnet>.ts.net/`. Anyone with the link can watch; changes need the admin PIN (above).
- **Everything else stays private:** the Commander, projector and visuals are reachable only on the rig's Wi-Fi (`http://sektor5.local:8090/` etc.) or over the tailnet at `https://sektor5.<tailnet>.ts.net:18090/`, `:18100`, `:18110`. They must be **https** (browsers always use HTTPS for `ts.net` names), and on **port + 10000**: `tailscale serve --bg --https=18090 http://127.0.0.1:8090` (same for 18100 → 8100, 18110 → 8110). Serving HTTPS on the service's own port stops that service from restarting (`Address already in use`). The dashboard is on 443. The page links handle this for you.
- **Top-bar page links** (`a[data-port]`, wired by `s5auth.js`) are greyed out for viewers. For admins they're greyed out only if that page can't be reached from where you are (e.g. on the public link without Tailscale).
- **Controls:** the System panel (click the logo) has a Tailscale card: status, devices online, the public link, and buttons to turn the public link or Tailscale itself off and on (admin). Turning Tailscale off while you're using it cuts you off; turn it back on from the rig's Wi-Fi.
- **Setup (done once):** `sudo tailscale up --hostname=sektor5`, `sudo tailscale set --operator=pi` (so deckdash can run the CLI without sudo), `tailscale funnel --bg --https=443 http://127.0.0.1:8080`, and the three `tailscale serve` lines above (`18090`, `18100`, `18110`). All of it survives reboots. Check with `tailscale serve status`.
- **Sharing with a collaborator:** share the `sektor5` machine from the admin console (Machines → sektor5 → Share) or invite them to the tailnet.
- Funnel needs HTTPS certificates and the `funnel` node attribute enabled in the tailnet policy (both already on).

## Renaming the brain

The brain was renamed from `ravecave` to `sektor5` on 27 Sep 2026. What that took, for next time:
- `sudo hostnamectl set-hostname sektor5`, and the `127.0.1.1` line in `/etc/hosts`.
- cloud-init resets the hostname on every boot from `/boot/firmware/user-data` (`hostname:`), so change it there too. `/etc/cloud/cloud.cfg.d/99-sektor5-hostname.cfg` (`preserve_hostname: true`) stops it resetting.
- `sudo systemctl restart avahi-daemon` for the new `.local` name. `avahi-alias-ravecave.service` keeps the old name answering (it publishes the Wi-Fi address at start; restart it if that address changes).
- Tailscale: `tailscale set --hostname=sektor5`, then rebuild the serve config for the new name: `tailscale serve reset`, the funnel line and the three serve lines from above. The old `ts.net` link stops working.

## Operations

- Logs: `journalctl -u deckdash -f`, `journalctl -u showbrain -f`.
- Health: `vcgencmd get_throttled` (should be `0x0`), `vcgencmd measure_temp`.
- **No RTC:** the clock is wrong until time syncs after boot. deckdash builds its show feed from per-device status lookups because of this (a timestamp-based lookup came back empty after the clock jumped).
- **The fan's control wire** is unused. If you use it, check its voltage first (a GPIO pin can't take 5 V) and use GPIO18 (pin 12) with the `gpio-fan` overlay.
