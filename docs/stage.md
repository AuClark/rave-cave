# Stage: 3D visualiser and designer

`http://ravecave.local:8100/stage.html` (the **Stage** link at the top of every control page). It's served by the projector service. The 3D engine is three.js r160, included in `brain/projector/web/vendor/` with its MIT licence, so it works offline.

## What it shows

The stage in 3D: a 4.8 × 3 m platform, a back wall, a lighting truss, and the DJ booth with two XDJs, the mixer and a DJ for scale. Your rig sits on it, lit from the running show.

| Fixture | Default position | Driven by |
|---|---|---|
| Tube L / Tube R | Either side of the DJ | **Live:** each tube's real 60 LEDs (`tube1`, `tube2`) |
| Projector L | Outside the tubes, on a stand | **Live:** the projector's output as mapped (its own `render.js` and layout), onto Screen L |
| Projector R | Outside the tubes, on a stand | **Live:** the Visuals page's generative sketch (`:8110`), full frame, onto Screen R |
| Screen L / R | Back wall | Projection surfaces |
| Laser L / R | Top left and right of the truss | **Simulated** from the show: sweeps on the beat, wide in DROP, converging through BUILD, off in the pre-drop blackout |
| Strobe | Top middle | **Simulated:** Commander strobe, blinder, and the drop hits |
| Wash | Top middle | **Live:** the par can's DMX colour (`parcan`) |

- **Live fixtures** use what the show engine actually sends each light: `preview` in its state (every LED of a strip, with the fixture's brightness applied; the par can's emitters mixed into one colour), 25 times a second via the projector's `/api/events` feed.
  - Drive levels are linear light, so they're read as linear RGB and scaled as a whole (never clipped per channel), which keeps hues exact.
  - Strobe, blinder and the drop's white hit are drawn by the page on the same beat clock, frame-exact, so they can't fall between updates.
  - **Match real lights** (saved with the layout): an LED display gain, a wash gain, and gamma (1.0 = as sent, WLED's realtime default; 2.8 if the fixture applies its own gamma). Set these by eye against the real rig.
- **Projectors** each show the projector output (as mapped), the Visuals page (generative), or nothing. To make the *real* projector show the visuals, set its surface content to "generative" on the Projection page.
- **Simulated fixtures** follow the scene, beat, colour, strobe and blackout.
- **Linking:** any fixture can be linked to a real fixture from the panel.

## Designing

- **Add** a tube, wash, strobe, laser, moving head, projector, LED bar or screen.
- **Select** a fixture by clicking it in the view or the list.
- **Move and aim:** **MOVE** (or M) drags the fixture; **AIM** (or A) drags the orange dot it points at. You can also type positions in metres. X is left/right, Y is height, Z is towards the audience, and (0, 0, 0) is the front edge of the stage floor, centre.
- **Per-fixture settings:** beam angle or projector throw, LED or beam count, colour for simulated fixtures, and screen size.
- **Views:** AUDIENCE, DJ, TOP and SIDE. **HAZE** controls how visible the beams are. **GLOW** is a bloom effect; turn it off on slow machines. **DESIGN** hides the panel for a full-screen show view.
- **Saving:** the layout saves to the brain (`/api/stage`, stored in `brain/projector/layouts/stage.json`, not in git) and updates on every open copy. **EXPORT** and **IMPORT** move a layout as a JSON file. **RESET TO MY RIG** restores the table above.
