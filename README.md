# Rave Cave

**Weekend-build DJ-synced stage lighting for Sydney shows.**

This is Jonathan Clark's beat-synced lighting rig: Engine DJ decks driving cheap AliExpress DMX fixtures (ALIEN wall washers, optional laser) plus an ESP32 WLED LED backdrop, all locked to the beat via Engine Lighting (SoundSwitch). Designed to be built in one weekend with mates before a show.

## What's Inside

- **[PLAN.md](PLAN.md)**: Full project plan—architecture, buy list (AU-sourced), power/cabling, weekend build order (Fri/Sat/Sun), software stack, risks, and open questions.
- Signal path: Engine DJ → SoundSwitch Micro DMX → DMX512 fixtures + DMX-to-Art-Net node → WLED ESP32 backdrop.
- Budget: ~AU$300–500 depending on how many fixtures and whether you already own the Micro DMX.

## Quick Start

1. **Read [PLAN.md](PLAN.md)** top to bottom.
2. **Check stock NOW**: SoundSwitch Micro DMX is often on backorder ([Bashs Music](https://www.bashsmusic.com.au/product/soundswitch-usb-to-dmx-lighting-interface/), [DJ City](https://djcity.com.au/product/soundswitch-2-micro-dmx-interface-micro-usb-to-dmx-xlr-lighting-interface/)).
3. **Order AliExpress ALIEN fixtures** (wall washers, 2–6 week shipping).
4. **Local LED strip**: [K&A Electronics SK6813HV 5m IP68](https://kandaelectronics.com.au/products/rgb-addressible-led-strip-sk6815-ws2815-60-leds-per-meter-dc-12v-ip68) ~AU$112 (in stock).
5. **Friday night**: Flash WLED, test breadboard, install SoundSwitch DLW.
6. **Saturday**: Build DMX chain, create Fixture Profiles, run Autoscript.
7. **Sunday**: Mount backdrop, wire Art-Net node, full rig run-through.

## Stack

- **Decks**: Engine DJ hardware (SC5000/SC6000 + X1800/X1850 mixer or Prime 4/SC Live all-in-one)
- **Lighting brain**: Engine Lighting firmware (inside Engine OS) + SoundSwitch DLW (PC authoring)
- **DMX interface**: SoundSwitch Micro DMX (USB, 1 universe, AU$64, **VID/PID locked—generic dongles don't work**)
- **Fixtures**: ALIEN DMX512 wall washers (AliExpress, ~AU$56 each)
- **Backdrop**: ESP32 + WLED + 12V WS2815 addressable LEDs (300 LEDs = 5m roll)
- **Protocols**: DMX512 (fixtures), DMX→Art-Net via Enttec ODE Mk2 or ESP-DMX node (WLED)

## Not Included / Later

- **Floor lamps (Bluetooth/IR RGB)**: Wrong protocol. Engine Lighting can't talk to them. Skip.
- **ALIEN 500mW laser**: Needs Attribute Cues (not autoscript), and if genuine 500mW = Class 4 = requires laser safety officer in AU. Park it unless you're qualified.
- **Per-pixel LED mapping**: WLED is treated as 1 DRGB fixture (whole strip same colour). Per-pixel = 510 DMX channels (170 RGB LEDs) = future upgrade.

## Risks

- **Micro DMX stock**: Often backorder. Order NOW.
- **AliExpress shipping**: 2–6 weeks. If show is soon, order yesterday or buy local (more expensive).
- **Art-Net from deck is flaky**: Don't rely on direct Engine Lighting → WLED Art-Net. Use DMX → Art-Net node (Enttec ODE Mk2) as reliable path.
- **Cheap AliExpress optos**: Buy isolated DMX splitter or separate PSUs per fixture.

## References

- [Engine Lighting official](https://enginedj.com/enginelighting)
- [SoundSwitch DLW download](https://www.soundswitch.com/download/)
- [WLED install](https://install.wled.me/)
- [Why only SoundSwitch USB works](https://support.enginedj.com/support/solutions/articles/69000793758)

---

**Done when:** Washers + backdrop strobe on beat by Sunday night. Ship it.
