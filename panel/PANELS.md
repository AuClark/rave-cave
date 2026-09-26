# HUB75 panels: setup, tests and fault log

## Setup

- **Panels:** 4x 32x16 RGB HUB75 (1/8 scan), labelled **1-4** by hand. Normal chain order is 1 → 2 → 3 → 4 (panel 1 nearest the controller).
- **Controller:** `rave-box`, a Raspberry Pi 3 A+ (`ssh rave-box`, user `raver`, 192.168.20.36 on FT Hangar) with an Adafruit RGB Matrix Bonnet (`--led-gpio-mapping=adafruit-hat`). The Pi only drives the data lines.
- **Power:** a dedicated high-current 5 V supply for the panels.
- **Driver:** `~/rpi-rgb-led-matrix/examples-api-use/ledcat` (hzeller/rpi-rgb-led-matrix), run with `--led-rows=16 --led-cols=32 --led-slowdown-gpio=2 --led-no-hardware-pulse`. It runs as the unprivileged user, so colour timing is loose. `sudo setcap 'cap_sys_nice=eip' .../ledcat` would fix that (not done yet; needs the rave-box password).
- **Show input:** `panel/ddp_panel.py` receives DDP on UDP 4048 (128x16 for the full chain) and feeds ledcat. The rave brain streams to it.

## HUB75 cheat sheet

| Pin | Signal | Pin | Signal |
|---|---|---|---|
| 1 | R1 (top-half red) | 2 | G1 (top-half green) |
| 3 | B1 (top-half blue) | 4 | GND |
| 5 | R2 (bottom-half red) | 6 | G2 (bottom-half green) |
| 7 | B2 (bottom-half blue) | 8 | E (unused on 1/8 scan) or GND |
| 9 | A (row address) | 10 | B (row address) |
| 11 | C (row address) | 12 | D (unused on 1/8 scan) |
| 13 | CLK | 14 | LAT |
| 15 | OE | 16 | GND |

What a symptom points to:
- **One colour missing in one half:** that half's colour data line (R1/G1/B1 or R2/G2/B2), a ribbon, connector pin or the input buffer.
- **Everything after a given panel missing the same thing:** that panel's OUT connector, or the ribbon to the next panel.
- **Single column missing one colour (all 8 rows of a half):** one driver chip output, or its trace or solder joint. Reflowing that chip can fix it.
- **Rows skipped, doubled or out of order:** row address lines A/B/C, or the row driver chip.
- **Garbage or random pixels everywhere:** CLK / LAT / OE, the ribbon, or ground.
- **Dimming at full white:** panel power leads or supply.

## Test procedure

Test one panel at a time on the **same ribbon cable** from the Bonnet, so the cable stays constant:

```bash
ssh rave-box 'cd ~/panel-controller && python3 -u panel_test.py --hold 5'
# single step, slower:  python3 -u panel_test.py --step 9 --hold 8
```

| Step | Pattern | Checks |
|---|---|---|
| 1-3 | Full red / green / blue | Whole-panel colour faults, driver-chip patches |
| 4 | Full white | Power |
| 5-7 | Each colour, top half then bottom half | The six colour data lines |
| 8 | White row walk, rows 0-15 | Row addressing (A/B/C) |
| 9 | Column walk, red then green then blue | Every driver chip channel |
| 10 | Checkerboard, then inverted | Shorts or bridges between neighbours |

Stop the show receiver first (`pkill -f "[d]dp_panel.py"`) and restart it afterwards (`pi/deploy.sh panel`).

## Results log

### 2026-09-26: full chain 1-2-3-4 (photos, before individual tests)

| Test | Observation | Suspected cause |
|---|---|---|
| Blue | Panel 1 full blue; panels 2-4 blue **top half only** | B2 (pin 7) not passing from panel 1 OUT to panel 2 IN: ribbon 1→2, panel 1 OUT connector, or panel 2 IN connector |
| Green | Gaps in a few bottom-half columns on panel 2 | Driver chip channels on panel 2 |
| White | Single columns tinted cyan / magenta / orange in bottom halves (panels 1-2); dimmer band of rows on panel 4 | Driver channels (bottom half); panel 4 row address or power |

### 2026-09-26 19:55: panel 2 alone

- Full test run on the Bonnet ribbon.
- **Result: "seems cooked".** Detailed symptoms still to be recorded (nothing lit / garbage / missing colours / shifted rows?).
- Status: **set aside.**

### 2026-09-26 ~20:00: panel 1 alone

- Full test run on the Bonnet ribbon. rave-box's clock jumped about 2.5 min during step 5 (time sync after boot), so the log timestamps around it aren't meaningful.
- **Result:** some pixels show **blue in the white test** and **don't light in the red test**. Blue on white means red and green are both missing on those pixels (green test result to confirm).
- Suspected cause: if scattered single pixels, the red/green dies or joints of those LEDs (press test: comes back = cold joint, reflow; doesn't = replace LED). If whole columns, a driver chip channel.
- To record: single pixels or columns, and roughly where.
- Status: **usable with defects**; it passed full blue in the chain earlier.

### 2026-09-26 20:04: panel 3 alone

- Full test run with 7 s holds (clock stable).
- **Result: good.** All colours, halves, row walk and column walk OK. Slight general flicker.
- Suspected cause of the flicker: software timing, not the panel. ledcat has no real-time priority (it warns at start-up). Fixes to try: `setcap cap_sys_nice`, `isolcpus=3`, `--led-pwm-bits` / `--led-limit-refresh`.
- Status: **good**, the best candidate for the first panel in the chain.

### 2026-09-26 20:06: panel 4 alone

- Full test run with 7 s holds. Steps 1-2 on time. **Step 3 (full blue) stalled for about 100 s**; steps 4-7 then ran. **Died during step 8 (row walk).** The panel went dark and rave-box dropped off the network (no ping).
- Earlier in the chain photos: a dimmer band of rows on this panel.
- Suspected cause: a power fault on panel 4 (short or excess draw) pulling the shared 5 V down and resetting the Pi, if the Pi is powered through the Bonnet. Alternatively a rave-box Wi-Fi drop, though that wouldn't explain the panel going dark.
- To check: rave-box uptime when it's back (short = it rebooted), how the Pi is powered, and panel 4's power leads for shorts or heat damage.
- Status: **suspect, don't chain it** until the power question is answered.

## Next steps

- Test panels 1, 3 and 4 alone and record results here.
- Then test the ribbons: the known-good panel with each ribbon in turn.
- Rebuild the chain with good panels first and any faulty panel last (a bad OUT connector only affects panels after it).
