# Generative visuals

Code-driven visuals you can reshape live, in the spirit of Zach Lieberman's sketches. A **sketch** is a small GPU shader with named parameters. The `visuals` service on the brain holds their live values, and any projector surface set to **generative** shows the sketch, warped to fit that surface. Code: [`brain/visuals/`](../brain/visuals/). Service: `visuals` on the brain, port **8110**.

## Using it

1. Open **`http://ravecave.local:8110/`** on a phone or laptop (on Android, use the IP: `http://<brain IP>:8110/`).
2. Move the sliders. The preview and every generative surface update as you drag.
3. **Randomise** throws everything, **Nudge** moves each value a little, **Reset** returns to the defaults. Each group has its own **random** button.
4. **Save** a look as a preset and **Load** it later. Presets are per sketch.
5. In the mapping editor (`:8100/edit`), set a surface's content to **generative** to put the sketch on it.

Everything is beat-locked: speeds are in cycles per beat, and **Beat punch** sets how hard each beat kicks the visual.

## Sketches

| Sketch | Controls |
|---|---|
| `rings` | Structure: ring count, spacing, inner radius, zoom. Shape: sides (3–12) and roundness (polygon to circle). Wave: frequency, amplitude, phase per ring, speed. Motion: twist per ring, spin, beat punch. Line: width, glow. Colour: hue, hue spread across the rings, saturation, follow the show's colour. |

| `field` | Elements: density (dots across the surface height, up to 60), size, size variation, round to square, filled to outline. Movement: wander, wander speed, drift speed and direction (the whole field travels across the surface). Wave: a travelling wave that swells the dots (amount, frequency, speed, direction). Links: lines to neighbouring dots (a moving net), link width, glow. Colour: hue, spread, colour by random or by the wave, saturation, follow the show's colour. |
| `eye` | The all-seeing eye for the capstone. Eye: size, open, opens through the build, wide open on the drop, blink, white of the eye. Iris: size, rings, fibres, pupil, dilate with energy, look around and its speed. Around: rays, ray length and spin, the dollar-bill triangle, glow, line width. Colour, a paper background and thin lines shooting from the pupil. |
| `sacred` | Gold line geometry. Mode 0 Sierpinski triangle zooming forever into its apex, 1 Flower of Life, 2 Metatron's Cube (Fill 0 = circles only, cheaper), 3 golden spiral (Fill adds the counter-spiral), 4 pyramid tunnel (Fill twists it). Scale, detail, zoom in cycles per beat, spin, a pulse that runs through the levels, width, glow, colour. |
| `ascend` | Energy climbing a pyramid face. With Triangle on, it clips itself to the face (apex top middle), so a plain surface over a face needs no masks. Edge light, capstone glow, charge level (climbs through a BUILD, full on the DROP), rising bands, glyph rows and their scroll, colour. |
| `subliminal` | They Live-style words. Mode 0 flash each bar, 1 strobe each beat, 2 steady, 3 hidden behind a bland broadcast until the DROP. First word and how many (0-8 the obey set: OBEY, CONSUME ...; 9-15 the wake-up set: WAKE UP, THEY LIVE ...), random order, hold, size, black on white, background flash, RGB glitch, jitter, grain. |
| `cctv` | A surveillance camera: night vision, thermal or grey; figures walking; a targeting box that jumps to a new one every few beats with a label; REC, camera number, timestamp and beat counter; grain, scanlines, rolling bar, vignette, glitch and zoom punch on the kick. |
| `redacted` | A classified document: black bars slide off on the beat to show glowing hidden words (MAJESTIC 12, MK ULTRA, AREA 51 ...). All revealed on the DROP, blacked out in the OUTRO. Lines, margin, scroll, dark paper, how much is redacted and revealed, how often, a stamp that thumps down each bar. |
| `cipher` | A wall of scrambling code, style 0 pigpen (the Freemasons' cipher), 1 binary rain, 2 numbers station, with a message in the middle row that decodes letter by letter every few bars, follows a BUILD, and completes on the DROP. |
| `area51` | Mode 0 radar with a beat-locked sweep and blips (one moves wrong), 1 a saucer whose tractor beam grows through the build and blazes on the drop, 2 a glowing crop circle. |
| `reptile` | Iridescent hex scales rippling on the beat, with a slit-pupil eye that blinks and opens wide on the drop. |
| `seething` | A lumpy ball of living cells (after Andy Lomas's Seething video). Size, grows through the section, lumps; cells across, jitter, seethe speed; Folds carves brain-like creases; shading, background (black to white), colour. |
| `seed` | Neon branching trees over glowing flower dots (after Vincent Houze's Seed video). Trees, levels, branch angle and shrink, sway, grows a level at a time through the section; width, glow, blossoms, ground flowers, colour from trunk to tips. |
| `orb` | A black glass orb with a pearl circling inside on vintage paper (after Whiskas fx's Harmonisch Serie video). Size, wobble, pearl size, orbit, gloss; paper, mirror into four or tile, RGB split on the kick, pearl tint. |
| `pipes` | White square pipes in a grey tiled room (after Graphset's Echoes Reality video). Cells, pipe width, density, round to square corners, one or two drifting layers, re-roll every few bars, shadows, room tiles, tint. |
| `wavelength` | Lines made of waves. Mode 0 ridgeline (stacked waveforms, each hiding the ones behind, like Unknown Pleasures), 1 flowing sine lines, 2 an oscilloscope trace with harmonics. Lines, amplitude, frequency, detail, ridge width, speed in cycles per beat, phase per line, width, glow, colour or a rainbow in the colours of visible light. Presets: unknown-pleasures, ridge-spectrum, ridge-gold, spectrum, moire, scope, scope-rgb. |

Low sides with no roundness, zero wave frequency and some twist gives the stacked, rotating-polygon spirograph look. High frequency with small amplitude gives rippling contour lines. In `field`, turning up Links with some Wander gives a drifting net; Wave with no Wander gives a clean grid of dots swelling in bands.

## Writing a sketch

Add two files to `brain/visuals/sketches/`:

- **`NAME.glsl`**: declares `uniform float p_<id>;` for each parameter and defines `vec3 content(vec2 uv)`. `uv` is 0..1 across the surface. It can use everything the projector's shaders get: `u_beat`, `u_frac`, `kick()` (1 on the beat, decaying), `u_hue`, `u_energy`, `u_scene`, `u_aspect`, `hsv()`, `hash()`. See [`render.js`](../brain/projector/web/render.js) (`COMMON`).
- **`NAME.json`**: title, description and parameter groups, each parameter with `id`, `label`, `min`, `max`, `step` and `default`. The control page builds its sliders from this.

Deploy with `brain/deploy.sh visuals` and pick it from the menu at the top of the control page. If the shader doesn't compile, the control page shows the error and the projector keeps the last working sketch.

## Conspiracy set

Sketches and presets for the conspiracy-themed night (a pyramid with an eye on the capstone). Each theme is a sketch with several presets to try:

| Theme | Sketch | Presets |
|---|---|---|
| The all-seeing eye | `eye` | watcher, dollar, reveal (opens on the drop), hypnotic, void |
| Sacred geometry | `sacred` | sierpinski, sierpinski-prism, flower-of-life, metatron, golden-spiral, sunflower, pyramid-tunnel, twisted-tunnel |
| Energy rising up the pyramid | `ascend` | charge, hieroglyph-wall, power-lines, full-power, cold |
| Red-string board | `field` | string-board, string-web, evidence-wall |
| Ciphers | `cipher` | pigpen, matrix-rain, numbers-station, novus-ordo |
| CCTV | `cctv` | night-vision, thermal-hunt, grey-cam, motion-alarm |
| Subliminal messages | `subliminal` | obey-flash, they-live, wake-up-strobe, drop-reveal, watching |
| Hypnosis | `rings` | hypno-spiral, mkultra, op-art, crop-rings |
| Aliens | `area51` | radar, radar-red, tractor-beam, abduction, crop-circle, crop-gold |
| Redacted files | `redacted` | top-secret, dark-files, heavy-redaction, declassified |
| Reptilians | `reptile` | lizard, snake-eye, iridescent, dragon |

Several of these react to the song's sections: the eye opens and the pyramid charges through a BUILD, and the DROP gives the reveal (eye wide open, words shown, message decoded, files declassified). Without showbrain the idle clock never reaches a BUILD or DROP, so those presets look quiet when testing at home.

### Shipped presets

Presets in `sketches/presets/NAME/*.json` ship with the sketch in git and show in the preset list alongside the ones saved on the brain. A preset file only needs the values it changes; everything else takes the sketch's defaults. Saving a preset with the same name on the brain overrides the shipped one.

### Text in sketches

Shaders can't draw text by themselves, so `tools/glsltext.py` writes a 5x7 pixel font and a list of messages into a sketch. The sketch lists its messages on a `// @messages: OBEY|CONSUME|WAKE UP` line and has an empty `// <text>` ... `// </text>` block; running `python3 brain/visuals/tools/glsltext.py brain/visuals/sketches/subliminal.glsl` fills the block. To change the words, edit the `@messages` line and run it again. The block gives the shader `textCov()` (a message), `charCov()` (one character), `msgLen()`, `msgChar()` and `CH_A` ... `CH_9` for drawing live numbers. Letters, digits, space and `: - . ! ? / # '` only.

## Max Cooper set

Simplified takes on five Max Cooper videos, each a sketch with presets:

| Video (artist) | Sketch | Presets |
|---|---|---|
| Seething (Andy Lomas) | `seething` | seething-red, brain, grey-mass, pink-coral |
| Seed (Vincent Houze) | `seed` | neon-grove, coral-bloom, blue-sprout, golden |
| Third (Vicetto) | `eye` | third-blue, third-green, third-teal |
| Harmonisch Serie (Whiskas fx) | `orb` | harmonisch, black-pearl, mirror, rgb-tiles |
| Echoes Reality (Graphset) | `pipes` | echoes, maze, round, blue-steel |

`emergence` (Order From Chaos, Maxime Causeret) is the sixth.

## How it works

- `visuals.py` serves the control page, the sketch (`/api/sketch`) and its values (`/api/params`). It pushes `sketch` and `params` messages to every open page over Server-Sent Events (`/api/events`), plus showbrain's state for the preview's beat clock.
- The projector page and the mapping editor also connect to `:8110/api/events`. The renderer compiles the sketch as content `gen` and sets its `p_*` uniforms every frame, so slider moves need no recompile.
- The control page's preview is the projector's own renderer (`/render.js`, served from `../projector/web/`), so it shows exactly what the projector draws.
- The beat clock runs smoothly at the track's tempo and eases towards the show engine's reported position (at most 10% faster or slower), so network jitter on the ~20 updates a second doesn't show as stutter. It only jumps on a seek or track change.
- Shaders get `u_px` (one output pixel in surface units), so lines never go thinner than a pixel and don't shimmer as they move.
- Live values and presets are kept on the brain in `~/visuals/state/`, not in git.

## API (on :8110)

`GET /api/events` (SSE: `sketch`, `params`, `state`), `GET /api/sketch`, `GET /api/sketches`, `GET/POST /api/params` (POST any subset, values are clamped to their ranges), `POST /api/select {"sketch": NAME}`, `GET /api/presets`, `GET/POST /api/presets/NAME`, `POST /api/presets/NAME/load`.
