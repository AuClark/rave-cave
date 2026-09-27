# Projector (projection mapping)

A projector running Chrome, showing the brain's projection-mapping page full-screen. Content is warped onto real-world surfaces and beat-locked to the show engine. Code: [`brain/projector/`](../../brain/projector/). Service: `projector` on the brain, port **8100**.

**Status (27 Sep 2026):** phase 1 running: surfaces with corner-pin warping, masks, seven content types, a live editor and presets. Phase 2 (camera auto-calibration) not started.

## Pages

| URL | For | What it does |
|---|---|---|
| `http://ravecave.local:8100/` | The projector | Full-screen output. Tap/click or press F / Enter for fullscreen. T toggles the test pattern, I shows an info HUD. `?test=1` and `?hud=1` do the same from the URL. |
| `http://ravecave.local:8100/edit` | A phone or laptop | The mapping editor, with a live preview of the output at the projector's aspect ratio |

## Setting up a room (about 5 minutes)

1. Open `/` on the projector and make it full-screen.
2. Open `/edit` on your phone. Turn on **Handles on wall** so the corner dots show on the wall too.
3. For each wall, panel or object: **+ Surface**, then drag its four corner dots onto the real corners. Each corner has its own colour: red top-left, green top-right, blue bottom-right, yellow bottom-left. Drag inside a surface to move it. On a laptop, arrow keys nudge the selected corner by 1 px (Shift = 10 px); **Next corner** picks which one.
4. **Test pattern** on: every surface shows a grid, border and circle. Adjust until the lines look straight and the circle round on the real surface.
5. Pick each surface's **content**, and draw **masks** over anything that shouldn't be lit (doorways, the DJ, speakers): **+ Draw mask**, tap points around it, then **Finish mask**.
6. Turn off Handles and Test pattern, set **Latency compensation** so drops land with the lights, and **Save** a preset (e.g. `workshop-back-wall`).

Layouts are saved on the brain in `~/projector/layouts/`: `current.json` plus presets. They aren't in git.

## Content

| Content | Look |
|---|---|
| `show` | Follows the scene engine. Groove: a pulse and ring on every beat, whiter on beat 1. Breakdown: dim two-colour plasma with sparse sparkles on the eighth notes. Build: strobe that speeds up, fill rising, washing to white. Pre-drop: blackout. Drop: white hit, then rings that alternate colour. |
| `pulse` | Whole surface flashes in the track's key colour on each beat |
| `tunnel` | Rings flowing inward on the beat |
| `bars` | Beat-driven bars scaled by the bar's energy |
| `title` | Current track title, glowing on the beat |
| `solid` | Key colour |
| `test` | Alignment grid for that surface |

Every surface has its own opacity and hue shift, so neighbouring surfaces can use complementary colours.

## How it works

- `projector.py` serves the pages and pushes showbrain's state to every open page about 20 times a second (Server-Sent Events, `/api/events`). Layout changes from the editor are saved and pushed to all pages immediately.
- `web/render.js` is the shared WebGL renderer. For each surface it computes the homography from the unit square to the surface's corners, and the fragment shader maps every pixel back through the inverse. The content is therefore perspective-correct on angled surfaces, with no mesh or texture resampling. Masks and edit handles go on a 2D overlay.
- Beat position is extrapolated locally between updates, and shifted by the layout's latency compensation (`lead_ms`).
- The output page reports its real resolution (`/api/screen`) so the editor matches its aspect ratio. Opening `/` on another device will overwrite that, so only open `/` on the projector.

## API (on :8100)

`GET /api/events` (SSE: `state`, `layout`, `screen`), `GET/POST /api/layout`, `GET /api/layouts`, `GET/POST /api/layouts/NAME`, `POST /api/layouts/NAME/load`, `POST /api/screen`.

## Next (phase 2)

- **Camera auto-calibration:** project Gray-code patterns, film them on a phone at `/calibrate`, decode the projector-to-camera mapping, and snap surfaces to detected edges.
- **Mesh warp** for curved surfaces (a grid of control points per surface).
- More content, and a per-surface "follow deck" option.
