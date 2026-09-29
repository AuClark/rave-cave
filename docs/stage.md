# Stage: 3D visualiser and designer

`http://sektor5.local:8100/stage.html` (the **Stage** link at the top of every control page). It's served by the projector service. The 3D engine is three.js r160, included in `brain/projector/web/vendor/` with its MIT licence, so it works offline.

## What it shows

The stage in 3D: a 4.8 × 3 m platform, a back wall, a lighting truss, and the DJ booth with two XDJs, and the mixer. Your rig sits on it, lit from the running show.

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
  - Tubes and LED bars are drawn as one continuous strip blended between LEDs, like the real diffuser. A tube is the real one: a 26 mm OD, 1.03 m tube standing in the collar of a four-leg fold-out base.
  - Leg pyramids ([leg-pyramids.md](fixtures/leg-pyramids.md)) draw their four legs' strips from one 241-pixel fixture (60 per leg, foot to apex, then the laser), and their laser straight up from the apex.
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

## Venues

A layout can stand in a **venue** instead of the built-in room: a set modelled elsewhere, with its own cameras, ground and light. Pick one under **Layout → Venue**. That loads the venue with its starting rig and replaces the current layout, so EXPORT the current one first to keep it. **RESET TO MY RIG** goes back to the room.

- Venues live in `brain/projector/web/venues/`. `index.json` lists them. Each `<id>.json` holds the venue (`model`, `floor`, `cams`, `light`) and its fixtures; `<id>.glb` is the set as glTF (three.js's GLTFLoader, in `vendor/`).
- The set is only scenery. The fixtures are ordinary Stage fixtures, so they're linked, simulated and edited as usual. Projectors' images land on the set, and the set casts shadows from them. In a venue, fixtures don't get the room's stands or truss clamps, because the model has its own mounts.
- **Lights inside the set:** a wash with `inside` set to the name of a part of the venue model (for example `"inside": "Side_Pyramid_L"`) lights that part from within. The part glows in the light's colour and level, and spills a little light around it; there's no beam.
- **Parts the rig replaces:** `venue.hide` lists parts of the model that aren't drawn (they're hidden, not deleted), for when a fixture now models the thing itself. The outdoor venue hides `Side_Pyramid_L` / `_R`, which the leg pyramids replace.
- **LED strips on the set:** an LED bar with `onto` set to a strip in the venue model (`"onto": "Arch_LED_Strip"`) lays its LEDs along that strip, from one foot of the arc to the other, with a soft halo like the tubes. It's driven like any strip: simulated, or linked to a real one.
- **Daylight** (View tab, saved with the layout) runs from night (0, the room as it always was) to a day sky (1): the sky, haze colour, ambient light and a low sun with shadows come up together. A venue sets its own default (`light.day`) and can override the colours (`light.sky`, `hemiSky`, `hemiGround`, `sun` position). The outdoor venue starts at dusk (0.55), so you can see the set and still see the lights.
- Venue coordinates are the same as the room's (metres, x right, y up, z towards the audience). The venue says where (0, 0, 0) is.

**Outdoor tarp stage** (`outdoor-tarp`) is Chris's Blender design: a 3 × 3 m tarp on four poles, the DJ table with a half-pyramid facade, a side pyramid and PA stack each side, a moon-gate arch 18 m out and the star chill tent beyond it. (0, 0, 0) is the tarp's front edge, on the ground.

| Fixture | Where | Driven by |
|---|---|---|
| Mapping projector | Crossbar between the front poles, aimed at the centre pyramid's front faces (72° short throw, 35% so a 2 m throw doesn't blow out) | Projector output (as mapped) |
| Laser (tripod) | Behind the DJ, on the laser/smoke tripod at 3 m, aimed at the tent roof | Simulated |
| Table par (uplight) | On the DJ table, straight up at the tarp | Live: `parcan` |
| Tube L / R | Floor tubes just outside the gazebo, beside the speakers | Live: `tube1`, `tube2` |
| Leg pyramid L / R | The two side pyramids, built to the real frame ([leg-pyramids.md](fixtures/leg-pyramids.md)): LED strips up the legs, a red laser up from the apex, cover optional (Selected → Cover) | Simulated; View → Section previews their looks |
| Arch LED strip | Round the inside of the arch, foot to foot (240 LEDs) | Simulated (link to a real fixture from the panel) |
| Tent par | Base of the tent pole, up into the roof | Simulated |

It's exported from the Blender file with `export_sektor5.py` (next to `stage.blend`): `Blender -b stage.blend -P export_sektor5.py -- brain/projector/web/venues`. That script reads positions, aims, beam angles and colours from the model, so re-run it after changing the design. The leg pyramids, the tubes' new positions and `venue.hide` were edited into `outdoor-tarp.json` by hand (30 Sep 2026): carry them into the Blender file before the next export, or it will put the old side pyramids and tube positions back.

## Designing

- **Add** a tube, wash, strobe, laser, moving head, projector, LED bar, leg pyramid or screen.
- **Select** a fixture by clicking it in the view or the list.
- **Move and aim:** **MOVE** (or M) drags the fixture; **AIM** (or A) drags the orange dot it points at. You can also type positions in metres. X is left/right, Y is height, Z is towards the audience, and (0, 0, 0) is the front edge of the stage floor, centre.
- **Per-fixture settings:** projector **brightness** (0–150%), beam angle or projector throw, LED or beam count, colour for simulated fixtures, and screen size.
- **Views:** AUDIENCE, DJ, TOP and SIDE. **HAZE** controls how visible the beams are. **GLOW** is a bloom effect; turn it off on slow machines. **DESIGN** hides the panel for a full-screen show view.
- **Saving:** the layout saves to the brain (`/api/stage`, stored in `brain/projector/layouts/stage.json`, not in git) and updates on every open copy. **EXPORT** and **IMPORT** move a layout as a JSON file. **RESET TO MY RIG** restores the table above.
