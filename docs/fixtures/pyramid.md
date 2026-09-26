# LED pyramid

A pyramid frame lined with 600 addressable LEDs, driven by `rave-box` over SPI. Code: [`fixtures/pyramid/`](../../fixtures/pyramid/).

**Status (27 Sep 2026):** wired and running test patterns. The pixel map and pyramid looks aren't done, so it isn't a fixture in the show yet.

## Hardware

| Part | Notes |
|---|---|
| 2 × 5 m WS2815, 12 V, 60 LED/m, IP67 | 600 LEDs. Four wires: +12V, GND, DI (data), BI (backup data). |
| Raspberry Pi 3 A+ (`rave-box`) | Drives the data from GPIO10 (SPI MOSI). The HUB75 Bonnet is removed. |
| SP901E signal amplifier | Turns the Pi's 3.3 V data into a strong 5 V signal (measured: 3.3 V in gives 5 V out). Four outputs carry identical copies. |
| 12 V supply | Powers the strips and the SP901E. At full white 600 LEDs draw about 9 A; the receiver limits current in software (5 A default). |
| 12 V → 5 V BEC | Powers the Pi (at least 2.5 A). |

## Wiring

| From | To |
|---|---|
| Pi **pin 19** (GPIO10, SPI MOSI) | SP901E Signal In **DAT 1** |
| Pi **pin 20** (GND) | SP901E Signal In **GND** |
| SP901E **Output 1 DAT 1** | strip **DI** (at the input end: the arrows point away from it) |
| strip **BI** (first LED only) | **GND** |
| 12 V supply | SP901E VCC/GND, and the strips' +12V/GND directly, fed at both ends of each 5 m run |
| BEC 5 V / GND | Pi pin 2 or 4 (5V) / pin 6 (GND) |
| — | **Nothing** on SP901E DAT 2 or Pi GPIO11 (pin 23) |

- **One common ground** for the supply, BEC, Pi, SP901E and strips.
- Don't run strip current through the SP901E's output terminals.
- **Pin mistakes we made:** pins 24 and 26 are SPI chip selects (held high), and pin 28 is ID_SC (pulled up). Neither carries data. GPIO11 (pin 23) is the SPI clock; feeding it to DI sends a square wave instead of data.
- **Mirrored or independent edges:** the SP901E's four outputs are copies. Four mirrored edges can each take one output. Independent edges need one chained run (one pixel map) or separate data lines.

## Software setup (on rave-box)

```bash
scp fixtures/pyramid/* rave-box:pyramid/      # or: brain/deploy.sh pyramid
ssh rave-box 'bash ~/pyramid/setup_rave_box.sh && sudo reboot'
```

[`setup_rave_box.sh`](../../fixtures/pyramid/setup_rave_box.sh) does the one-time setup:
- stops the old panel software
- enables SPI and fixes the Pi 3 core clock at 250 MHz (SPI LED timing depends on it)
- sets `spidev.bufsiz=32768` (600 LEDs don't fit the 4 KB default)
- adds the user to `spi` and `gpio` (no root needed at runtime)
- installs `rpi_ws281x` into `~/pyramid-venv`
- installs the `pyramid` service

[`ddp_ws281x.py`](../../fixtures/pyramid/ddp_ws281x.py) receives DDP on UDP 4048, scales frames to the current budget (`--max-amps`, about 15 mA per LED at full white), and shows a dim rainbow when no frames arrive for 3 s.

## Checking the chain

With the receiver stopped, `pinctrl set 10 op dh` / `dl` holds pin 19 high or low. Measure with a multimeter:

| Point | High | Low |
|---|---|---|
| Pi pin 19 | 3.3 V | 0 V |
| SP901E In DAT 1 | 3.3 V | 0 V |
| SP901E Out 1 DAT 1 | 5 V | 0 V |

Afterwards, restore SPI with `pinctrl set 10 a0`, then `sudo systemctl start pyramid`.

## To do

- Pixel map: shape, edge lengths, and the strip's route around the frame.
- Pyramid looks: fill from base to apex on builds, burst from the apex on drops, comets up the edges in groove.
- Add as a fixture in [`brain/showbrain/config.json`](../../brain/showbrain/config.json).
- Tie BI to GND for the show. Set `--max-amps` to the supply's rating.
