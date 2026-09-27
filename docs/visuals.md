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

Low sides with no roundness, zero wave frequency and some twist gives the stacked, rotating-polygon spirograph look. High frequency with small amplitude gives rippling contour lines. In `field`, turning up Links with some Wander gives a drifting net; Wave with no Wander gives a clean grid of dots swelling in bands.

## Writing a sketch

Add two files to `brain/visuals/sketches/`:

- **`NAME.glsl`**: declares `uniform float p_<id>;` for each parameter and defines `vec3 content(vec2 uv)`. `uv` is 0..1 across the surface. It can use everything the projector's shaders get: `u_beat`, `u_frac`, `kick()` (1 on the beat, decaying), `u_hue`, `u_energy`, `u_scene`, `u_aspect`, `hsv()`, `hash()`. See [`render.js`](../brain/projector/web/render.js) (`COMMON`).
- **`NAME.json`**: title, description and parameter groups, each parameter with `id`, `label`, `min`, `max`, `step` and `default`. The control page builds its sliders from this.

Deploy with `brain/deploy.sh visuals` and pick it from the menu at the top of the control page. If the shader doesn't compile, the control page shows the error and the projector keeps the last working sketch.

## Reaction-diffusion lab

**`http://ravecave.local:8110/rd.html`** (on Android, use the IP) is a standalone test page running a real Gray-Scott reaction-diffusion simulation on the GPU, after [Karl Sims](https://www.karlsims.com/rd.html). It is not a sketch: it's there to find looks and to check what the projector's GPU can handle before simulations go into the shared renderer.

- Pattern buttons set feed and kill (Coral, Mitosis, Mazes, Fingerprint, Worms, U-skate and more) and reseed. Draw with a finger or the mouse to add chemical.
- **Pattern map**: Uniform, Karl's f/k map (every behaviour at once), or Radial (your pattern in the middle, spots at the rim).
- Speed is in simulation steps per beat, so growth follows the tempo. **Seeds on beat** drops new growth on each beat (a burst on DROP); **Feed pulse** makes the pattern breathe with the kick. Beat comes from showbrain via `/api/events`, with a 120 BPM idle clock without it.
- The stats show fps, simulation size, and the storage the GPU supports (float32, float16, or an 8-bit packed fallback that works everywhere). If the fps drops, lower the resolution.
- URL options for bookmarking a look: `?preset=mazes&look=1&res=4&mode=2&speed=200&seeds=0.3&pulse=0&hud=0` (also `f=` and `k=`). **H** hides the panel.

## How it works

- `visuals.py` serves the control page, the sketch (`/api/sketch`) and its values (`/api/params`). It pushes `sketch` and `params` messages to every open page over Server-Sent Events (`/api/events`), plus showbrain's state for the preview's beat clock.
- The projector page and the mapping editor also connect to `:8110/api/events`. The renderer compiles the sketch as content `gen` and sets its `p_*` uniforms every frame, so slider moves need no recompile.
- The control page's preview is the projector's own renderer (`/render.js`, served from `../projector/web/`), so it shows exactly what the projector draws.
- The beat clock runs smoothly at the track's tempo and eases towards the show engine's reported position (at most 10% faster or slower), so network jitter on the ~20 updates a second doesn't show as stutter. It only jumps on a seek or track change.
- Shaders get `u_px` (one output pixel in surface units), so lines never go thinner than a pixel and don't shimmer as they move.
- Live values and presets are kept on the brain in `~/visuals/state/`, not in git.

## API (on :8110)

`GET /api/events` (SSE: `sketch`, `params`, `state`), `GET /api/sketch`, `GET /api/sketches`, `GET/POST /api/params` (POST any subset, values are clamped to their ranges), `POST /api/select {"sketch": NAME}`, `GET /api/presets`, `GET/POST /api/presets/NAME`, `POST /api/presets/NAME/load`.
