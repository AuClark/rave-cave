# Stage: 3D visualiser and designer

`http://sektor5.local:8100/stage.html` (the **Stage** link at the top of every control page). It's served by the projector service. The 3D engine is three.js r160, included in `brain/projector/web/vendor/` with its MIT licence, so it works offline.

## What it shows

The stage in 3D: a 4.8 × 3 m platform, a back wall, a lighting truss, and the DJ booth with two XDJs, the mixer and a DJ for scale. Your rig sits on it, lit from the running show.

| Fixture | Default position | Driven by |
|---|---|---|
| Tube L / Tube R | Either side of the DJ | **Live:** each tube's real 60 LEDs (`tube1`, `tube2`) |
| Projector L | Outside the tubes, on a stand | **Live:** the projector's output as mapped (its own `render.js` and layout), onto Screen L |
| Projector R | Outside the tubes, on a stand | **Live:** the Visuals page's generative sketch (`:8110`), full frame, onto Screen R |
| Screen L / R | Back wall | Projection surfaces |
| Laser L / R | Top left and right of the truss | **Simulated** laser shows from the show's beat clock and scene (see [Laser shows](#laser-shows)) |
| Strobe | Top middle | **Simulated:** Commander strobe, blinder, and the drop hits |
| Wash | Top middle | **Live:** the par can's DMX colour (`parcan`) |

- **Live fixtures** use what the show engine actually sends each light: `preview` in its state (every LED of a strip, with the fixture's brightness applied; the par can's emitters mixed into one colour), via the projector's `/api/events` feed. Showbrain keeps its last four output frames (50 fps, time-stamped, each fixture as one hex string). The projector sends each frame once, only to pages that ask for them (`/api/events?frames=1`, the Stage page), and leaves the per-LED preview out of the normal state stream. The page plays the frames back at their real spacing, behind by the measured delivery spread plus 50 ms (it adapts if Wi-Fi delivery gets bursty), so rain, sparkles and fills move as smoothly as on the real tubes.
  - Tubes and LED bars are drawn as one continuous strip blended between LEDs, like the real diffuser, inside a frosted shell with a faint halo.
  - Drive levels are linear light, so they're read as linear RGB and scaled as a whole (never clipped per channel), which keeps hues exact.
  - Strobe, blinder and the drop's white hit are drawn by the page on the same beat clock, frame-exact, so they can't fall between updates.
  - **Match real lights** (saved with the layout): an LED display gain, a wash gain, a **Projectors** trim, and gamma (1.0 = as sent, WLED's realtime default; 2.8 if the fixture applies its own gamma). Set these by eye against the real rig.
- **Projectors** each show the projector output (as mapped), the Visuals page (generative), or nothing. To make the *real* projector show the visuals, set its surface content to "generative" on the Projection page.
- **Simulated fixtures** follow the scene, beat, colour, strobe and blackout.
- **Linking:** any fixture can be linked to a real fixture from the panel.

## Laser shows

The simulated lasers play full laser shows, locked to the show's beat clock and following its scene. The engine is in `brain/projector/web/lasershow.js`.

- **Looks (LASERS in the top bar, saved with the layout).** They're modelled on the big touring shows, but none of them uses an artist's actual show data.
  - **Epic:** Prydz-style. Cool white plus the track's colour; liquid skies, tunnels, rippling fans.
  - **Red & white:** SHM-style. Crossfire, knives, chases and lattices, chopped in drops.
  - **Trance green:** ASOT-style. Cones, liquid skies, fan waves.
  - **Dark & cinematic:** Afterlife-style. Sparse white and violet blades, slow sheets.
  - **Mainstage rainbow:** Garrix-style. Rainbow bursts, scans, zigzags.
  - **Warehouse techno:** strobing white with amber.
  - **Classic:** the old simple fan, using the fixture's own colour, beam count and spread.
  - **Auto** (the default) picks a new look for each track.
- **Cues:**
  - **Fan:** a wide fan swinging on the beat.
  - **Wave:** a dense fan with a ripple travelling across it.
  - **Tunnel:** a turning cone, drawn as a scanned surface.
  - **Liquid sky:** a rippling sheet over the crowd's heads.
  - **Crossfire:** beams from each side shooting across the centre.
  - **Knives:** a vertical fan slicing sideways.
  - **Chase:** beams jumping to new spots on every step.
  - **Audience scan:** a fan tilting from the floor up over the crowd.
  - **Sunburst:** spokes bursting out once a bar.
  - **Zigzag lattice:** beams crossing into a diamond mesh.
  - **Converge:** a fan closing to a point, used in builds.
- **When cues change:** every 8 bars, or every 4 in a drop, so the show follows the track's phrasing.
- **Mirroring:** every laser in the rig takes part. Left and right mirror each other.
- **Sections:**
  - **Builds** narrow, spin faster and stutter at ¼, then ⅛, then 1/16 as they rise.
  - **Drops** open after the white hit. The 4th bar of each drop phrase stutters.
  - The **pre-drop blackout** cuts them.
- **Physical behaviour:** beams stop at the floor, and **HAZE** sets how visible they are.
- **Section preview:** the second LASERS menu makes the lasers play one section (GROOVE, BUILD, DROP, BREAKDOWN or INTRO) on the show's clock, or at 128 BPM when no deck is playing. It's for designing and only affects your view. **FOLLOW SHOW** returns to normal.
- **Laser fixtures:** add more with **Add fixture → Laser** and place them on the truss or the stage front for a fuller field. Each fixture draws up to 72 beams plus a sheet.

## Designing

- **Add** a tube, wash, strobe, laser, moving head, projector, LED bar or screen.
- **Select** a fixture by clicking it in the view or the list.
- **Move and aim:** **MOVE** (or M) drags the fixture; **AIM** (or A) drags the orange dot it points at. You can also type positions in metres. X is left/right, Y is height, Z is towards the audience, and (0, 0, 0) is the front edge of the stage floor, centre.
- **Per-fixture settings:** projector **brightness** (0–150%), beam angle or projector throw, LED or beam count, colour for simulated fixtures, and screen size.
- **Views:** AUDIENCE, DJ, TOP and SIDE. **HAZE** controls how visible the beams are. **GLOW** is a bloom effect; turn it off on slow machines. **DESIGN** hides the panel for a full-screen show view.
- **Saving:** the layout saves to the brain (`/api/stage`, stored in `brain/projector/layouts/stage.json`, not in git) and updates on every open copy. **EXPORT** and **IMPORT** move a layout as a JSON file. **RESET TO MY RIG** restores the table above.
