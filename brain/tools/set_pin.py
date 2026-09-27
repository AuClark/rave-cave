#!/usr/bin/env python3
"""Set, change or remove the rig's admin PIN. Run ON the brain as pi:

    ssh -t pi@sektor5.local 'python3 ~/tools/set_pin.py'            # set or change the PIN
    ssh -t pi@sektor5.local 'python3 ~/tools/set_pin.py --sign-out'   # keep the PIN, sign every browser out
    ssh -t pi@sektor5.local 'python3 ~/tools/set_pin.py --off'        # remove the PIN (everyone is admin again)

The PIN is asked for twice with hidden input and stored only as a salted PBKDF2 hash in
/srv/rave/auth.json (owner pi, group rave, mode 640), with a fresh random signing key. Changing the
PIN also signs every browser out. Services pick the change up immediately (no restart).
"""
import getpass
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path.home() / "showbrain"))
import s5auth  # noqa: E402

FILE = s5auth.AUTH_FILE


def write(data):
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    os.chmod(tmp, 0o640)
    try:
        import grp
        os.chown(tmp, -1, grp.getgrnam("rave").gr_gid)
    except (KeyError, PermissionError):
        pass
    tmp.replace(FILE)


def main():
    if "--off" in sys.argv:
        if FILE.exists() and input("Remove the admin PIN? Everyone will be able to control the rig. [y/N] ").lower() == "y":
            FILE.unlink()
            print("PIN removed.")
        return
    if "--sign-out" in sys.argv:
        d = json.loads(FILE.read_text())
        d["not_before"] = int(time.time()) + 1
        write(d)
        print("Every browser is signed out. Re-enter the PIN to unlock.")
        return
    pin = getpass.getpass("New admin PIN (6+ digits recommended): ").strip()
    if len(pin) < 4:
        sys.exit("Too short: use at least 4 characters (6+ digits if the rig is on a public link).")
    if getpass.getpass("Repeat it: ").strip() != pin:
        sys.exit("They don't match. Nothing changed.")
    if len(pin) < 6:
        print("Note: a PIN under 6 digits is weak if the rig is reachable from the internet.")
    write(s5auth.new_auth_file(pin))
    print(f"PIN set. It's stored hashed in {FILE}. Every browser needs to enter it once.")


if __name__ == "__main__":
    main()
