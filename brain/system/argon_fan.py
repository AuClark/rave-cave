#!/usr/bin/env python3
"""Argon ONE case fan: sets the fan speed from the CPU temperature.

The case's microcontroller sits on I2C bus 1 at 0x1a (needs dtparam=i2c_arm=on). The fan speed is a
single byte, 0-100 (the original Argon ONE protocol). Only ever send 0-100: other values are
commands to the case (0xFF, for one, tells it to cut the power), and sending a register address
first (0x80, as newer Argon scripts do) wasn't understood by our case's firmware. Installed by brain/provision/setup_brain.sh as the argon-fan service. Writes its
state to /run/argon-fan/status.json for the System view. Exits quietly if there's no Argon case.

Curve: off below 50 °C, then 25 / 50 / 75 / 100 % from 50 / 55 / 60 / 65 °C. It only steps down
once the temperature is 3 °C under a step, so the fan doesn't flick on and off at a boundary.
"""
import json
import os
import sys
import time

ADDR = 0x1A
CURVE = [(65, 100), (60, 75), (55, 50), (50, 25)]   # (°C, %), hottest first
HYSTERESIS = 3.0
STATUS = "/run/argon-fan/status.json"


def temp_c():
    with open("/sys/class/thermal/thermal_zone0/temp") as f:
        return int(f.read()) / 1000.0


def target(t, current):
    want = next((pct for c, pct in CURVE if t >= c), 0)
    if want < current:                                  # stepping down: wait until clearly cooler
        keep = next((pct for c, pct in CURVE if t >= c - HYSTERESIS), 0)
        return max(want, min(current, keep))
    return want


def main():
    try:
        import smbus
        bus = smbus.SMBus(1)
        bus.read_byte(ADDR)
    except Exception as e:                              # no I2C, or no Argon case on it
        print(f"no Argon ONE case found ({e}); nothing to do")
        return 0

    def set_fan(pct):
        bus.write_byte(ADDR, max(0, min(100, int(pct))))

    speed = -1
    while True:
        t = temp_c()
        new = target(t, max(speed, 0))
        if new != speed:
            set_fan(new)
            print(f"{t:.1f} °C: fan {new}%", flush=True)
            speed = new
        try:
            tmp = STATUS + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"case": "Argon ONE", "fan_pct": speed, "temp_c": round(t, 1), "ts": int(time.time())}, f)
            os.replace(tmp, STATUS)
        except OSError:
            pass
        time.sleep(5)


if __name__ == "__main__":
    sys.exit(main())
