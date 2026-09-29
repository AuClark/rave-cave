# Leg pyramids

Two small pyramids, one either side of the stage. Each is four aluminium legs slotted into a 3D-printed top junction. A WS2815 strip runs up the outside of each leg, an ESP32 at the top drives each leg from its own pin, and a red laser points straight up out of the apex. A white fabric cover over the frame is optional.

**Status (30 Sep 2026):** designed; not built yet. They're modelled in the Stage view (the outdoor venue, and **Add fixture → Leg pyramid**) with simulated looks, so the show can be worked out before the hardware exists. They aren't fixtures in showbrain yet.

These are a different fixture from the big [LED pyramid](pyramid.md) (600 LEDs on the Pi `rave-box`).

## Frame

From the Fusion model **Pyramid v3** (project *Random*, folder *Rave Cave*):

| Part | Size |
|---|---|
| Legs | 4 × aluminium U-channel, 20 × 11.5 mm, 2 mm walls, 1000 mm long |
| Leg angle | 45° to the floor, one leg to each corner |
| Footprint | feet about 1.02 m apart (square), about 1.44 m corner to corner |
| Height | apex about 0.74 m |
| Top junction | 3D printed, about 83 mm across and 43 mm tall, four leg sockets |
| Laser boss | on top of the junction, 14.6 mm across with a 14.2 mm bore |

The legs just slot in, so a pyramid packs flat: four legs and a junction.

## Electronics (per pyramid)

| Part | Notes |
|---|---|
| 4 × 1 m WS2815, 12 V, IP65/67 | One per leg, in the channel on the outside face. Density to decide: 60 LED/m is the Stage default (set **LEDs / leg**). Four wires each: +12V, GND, DI, BI. |
| ESP32 (e.g. ESP-32S NodeMCU, as in the tubes) | In or on the junction. Runs WLED. |
| Level shifter, 4 channels (74AHCT125) | 3.3 V data to 5 V, one channel per leg. Short leads, as the strips start right at the junction. |
| Red laser module, TTL input | In the boss, pointing up. Switched from a GPIO (direct TTL input, or a logic-level MOSFET such as an AO3400 on its supply). |
| 12 V supply | 4 × 60 LEDs is about 3.6 A at full white at 15 mA per LED (the figure in [pyramid.md](pyramid.md)); check the strip's W/m, and size the supply with headroom (5 A or more). Set WLED's current limit to match. |
| 12 V → 5 V buck (≥ 1 A) | Powers the ESP32 (5V pin). |

### Wiring

| From | To |
|---|---|
| ESP32 GPIO 13 → 74AHCT125 ch 1 | front-left leg DI |
| ESP32 GPIO 14 → ch 2 | front-right leg DI |
| ESP32 GPIO 25 → ch 3 | back-right leg DI |
| ESP32 GPIO 26 → ch 4 | back-left leg DI |
| ESP32 GPIO 27 | laser TTL (or the MOSFET gate, with a 100 kΩ pull-down) |
| each strip's BI (first LED) | GND |
| 12 V | each strip's +12V and GND at the top, the buck converter, the laser (if 12 V) |

- The pins avoid the ESP32's boot pins (0, 2, 5, 12, 15), its flash (6–11) and the input-only ones (34–39); see [tubes.md](tubes.md#2-wiring-the-esp32).
- One common ground for everything. Tie the 74AHCT125's OE pins to GND.
- The strips are fed **from the top**, where the ESP32 is, so each strip's first LED is at the apex. WLED reverses each output (below) so that pixel 0 is at the foot, which is what the show and the Stage view expect.

## WLED setup

Flash and join Wi-Fi as for the tubes ([tubes.md](tubes.md#3-flashing-wled-from-a-mac)), then in **Config → LED Preferences** add five outputs:

| Output | Type | GPIO | Length | Start | Reversed |
|---|---|---|---|---|---|
| 1 | WS281x (GRB; check the strip) | 13 | 60 | 0 | yes |
| 2 | WS281x | 14 | 60 | 60 | yes |
| 3 | WS281x | 25 | 60 | 120 | yes |
| 4 | WS281x | 26 | 60 | 180 | yes |
| 5 | On/Off | 27 | 1 | 240 | – |

- LED current: WS2815, and the supply's rating as the limit.
- Names: `rave-pyramid-l` / `rave-pyramid-r` (mDNS), as for the tubes.

The brain then drives it like a tube, as one 241-pixel strip over DDP.

## Pixel map

The same for the Stage view (`source` set to the fixture's name) and for showbrain:

| Pixels | What |
|---|---|
| 0–59 | front-left leg, foot to apex |
| 60–119 | front-right leg |
| 120–179 | back-right leg |
| 180–239 | back-left leg |
| 240 | the laser: on when its brightest channel is above half, off otherwise |

"Front" faces the audience. With another density, each leg is *n* pixels and the laser is pixel 4*n*.

## Looks

What the Stage view simulates now, and the plan for showbrain. **View → Section** previews each one on a 128 BPM clock. The two pyramids mirror each other.

| Section | Legs | Laser |
|---|---|---|
| Groove | A white comet runs up one leg per beat, round the pyramid; the feet pulse with the kick in the show colour | off |
| Build / hold | The legs fill from the feet to the apex with the build's progress, with a bright line at the fill; they flicker on 8ths, then 16ths, then 32nds as it nears the drop | flickers in the last 10% |
| Predrop | Dark, except the top few LEDs breathing white | **on, steady**: the only light before the drop |
| Drop | On the downbeat a white burst runs from the apex down all four legs, then full colour (alternate legs in the complementary colour) with a white ring falling from the apex each beat | on the kick for 4 bars, then on the one |
| Breakdown, intro, outro | Slow breathing in a soft complementary colour, brighter towards the top | off |
| Strobe, blinder, blackout | follow the rest of the rig | off in a blackout |

Other ideas for later:
- Pass a comet from one pyramid to the other across the stage (left pyramid's legs, then the tubes, then the right's).
- The legs as a VU meter: the level of each deck's channel from the mixer, on its own pyramid.
- With the cover on, fills read as the whole pyramid glowing; without it, the edges draw a wireframe in the air. Looks may want to know which.

## Laser safety

Keep it to a low-power module (**Class 2, under 1 mW**, or at most Class 3R) and pointing only at the sky, never across the crowd. In Australia a laser shone into the sky can dazzle pilots: outdoor laser use near aerodromes needs CASA's assessment, and handheld lasers over 1 mW are prohibited in most states. Check the site before running it outdoors.

## To do

- Build and wire one; pick the LED density.
- Add both as fixtures in [`brain/showbrain/config.json`](../../brain/showbrain/config.json) (`kind: "strip"`, 241 LEDs), with pyramid looks in showbrain that use the map above, then link them in the Stage view.
- In the Blender file (`stage.blend`): replace `Side_Pyramid_L` / `_R` with these, so the venue export no longer needs `venue.hide` (see [stage.md](../stage.md#venues)).
