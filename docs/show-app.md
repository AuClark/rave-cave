# The Show app

One page for running a night: decks, lights, visuals, projection mapping and the stage, each on its own screen, with the controls laid out round the picture rather than in tabs. It's served by the `visuals` service: **`http://sektor5.local:8110/show.html`** (on a phone, use the brain's IP). Code: [`brain/visuals/web/show.html`](../brain/visuals/web/show.html).

It drives the rig through the existing APIs, so nothing on the servers changes and every other page keeps working alongside it:

| Screen | Talks to |
|---|---|
| Decks | deckdash `:8080` (`/api/state`, `/api/deck`, `/api/library/…`, `/api/timeline/N`, `/api/waveform/N`, `/api/wavedetail/N`) |
| Lights | showbrain `:8090` (`/api/state`, `/api/cmd`) |
| Visuals | visuals `:8110` (this service) |
| Mapping | projector `:8100` (`/api/layout`, `/api/layouts/…`, `/api/events`) |
| Stage | projector `:8100/stage.html?embed=1` in a frame |

Addresses go through `S5AUTH.url`, so the page works on the rig's network and over HTTPS alike. POSTs go through the shared PIN check; a refused one says why in a toast instead of failing silently.

## The screens

- **Decks.** Both decks with Play/Stop, Sync and Master, the time left and the drops marked. **Automix** (below) sits under them, then the music: search, playlists, and **Fits the mix** (near the master's BPM, in a compatible key). Tap a track to load it on the deck that isn't playing; a playing deck's load button is greyed out. **Setup → Track waveforms** adds a scrolling waveform and a whole-track overview to each deck.
- **Lights.** Scene, the hits (Strobe, Blinder, Flash, Blackout), a colour ring with **Follow the music** in the middle, and the master level.
- **Visuals.** The preview (with a Live / Frozen / Reconnecting badge) with Freeze, Next look and **Focus**, and the projectors' output level. On the left, the **look**: the themes, the looks in the one you pick (tap one to mix to it), and **Shuffle** (on/off, every 1–32 bars, Skip, and when the next change lands). The theme you pick is the one Shuffle plays from. On the right, energy (Calm / Groove / Drop), the presets, **Randomise** (a random preset for this look, **R**), and **Words** for looks that draw type. On a phone, energy comes straight after the picture. **Focus** is the view to leave open while playing: the scene, the drop countdown and the beat; the moments (Drop now, Build up, Flash, Blackout); energy, **colour palettes** and presets; no tab bar. A palette locks the lights to its first colour and sets each sketch's own colour settings (`follow` off, `hue`, `sat`, `spread`, `tint`, where it has them), and stays on over new looks, presets and energy rolls until **Auto**.
- **Mapping.** The projector's picture in the middle: drag corners to pin a surface, drag inside to move it, arrow keys nudge. Surfaces (quads and triangles), hidden areas (masks) and saved layouts on the left; the selected surface's settings on the right, with Undo on removals.
- **Stage.** The 3D stage in the middle: camera, haze, daylight and glow on the left; laser looks, a section preview and the rig on the right. Adding and aiming fixtures is on the full Stage page (**Edit the rig**). The page is embedded with `?embed=1`, which hides its own panels and takes `{s5stage: "set", cam, haze, day, laser, sec, glow, select, pause}` messages; it answers with `{s5stage: "state", …}`. Every change goes through its own controls, so Daylight and the laser look save exactly as they do there. The frame only loads when Stage is first opened, and pauses on the other screens.

The **Autopilot** pill at the top says what the room is doing that the music didn't ask for (a latched scene, a locked colour, frozen visuals…); tap it to hand everything back. **Setup** (the gear) holds Appearance (dark, light or match the device), Track waveforms, and links to the full pages for everything done before the night.

## Automix

A port of the Decks page's automix, without its kick-align and tempo-ramp extras (those stay on the full page). It runs in the browser tab that has it switched on, so keep that tab open, and don't switch it on here and on the Decks page at once. With both channel faders up, the next track loads on the idle deck and syncs; **Land the drop** starts it so its first drop lands as the playing track's outro ends (falling back to an overlap when the drop is too far in), **Overlap** plays both for 16, 32 or 64 beats from the outro's first bar. Then the old deck stops on a bar line and the new one takes master. **Skip** picks another track; **Mix now** starts on the next bar.

## Keys

Space flash · S / W strobe, blinder (hold) · B blackout · 0–4 scenes · D drop now · Z / X / C visuals calm, groove, drop · N next look · R randomise · L Shuffle on/off · F freeze · / search the music · ? Setup and the key list · arrow keys nudge a corner on Mapping · Esc closes Setup or leaves Focus. Esc no longer hands everything back to autopilot: it's the key you reach for to get out of something, and it shouldn't also drop a blackout mid-set. Use the pill, which says **Reset** while anything is overridden.

## Look

The page has its own design system, not the charcoal-and-hairline one in [design.md](design.md): near-black and flat, zinc neutrals with 1 px borders, sentence case, a light mode. The tokens are at the top of the stylesheet. One accent, Sektor orange, and it only means live or on: the look, energy or preset that's playing, Shuffle running, a held hit. A selected choice (a segment, a chip, a theme) is white; blackout is red. Radius 8 / 12 / 16; controls 32–40 px on desktop and at least 44 px on phones. It uses system fonts, so nothing is fetched from the web (the brain is often offline at a gig). The screen stays awake while the page is open (Wake Lock), and hover styles are off on touch screens so a tapped tile doesn't stay lit. The pictures (preview, mapping, stage) stay dark in both themes. On a laptop or desktop every screen fits the window; on a phone the picture comes first and the controls stack under it, at 40 px or more to tap.

## Not here yet

Still only on the full pages: every sketch setting, saving presets, transition settings, Shuffle's per-look tick-outs and queueing a look for next, the Launchpad's effects and quantised launch; build lengths other than 4 bars, hold / cancel build, skip or mark a drop, strobe rate, motion speed, tap tempo, Mixer React, per-fixture levels; kick align and tempo ramps; renaming or removing a projector, output latency and resolution, the backdrop; fixture editing and venues; the simulation and System controls.
