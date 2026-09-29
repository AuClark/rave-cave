# Generative visuals

Code-driven visuals you can reshape live, in the spirit of Zach Lieberman's sketches. A **sketch** is a small GPU shader with named parameters. The `visuals` service on the brain holds their live values, and any projector surface set to **generative** shows the sketch, warped to fit that surface. Code: [`brain/visuals/`](../brain/visuals/). Service: `visuals` on the brain, port **8110**.

## Using it

1. Open **`http://sektor5.local:8110/`** on a phone or laptop (on Android, use the IP: `http://<brain IP>:8110/`).
2. Move the sliders. The preview and every generative surface update as you drag.
3. **Q**, **W** and **E** are the same dice at three energies — calm, groove, full on for the drop. **Randomise** throws everything, **Nudge** moves each value a little, **Reset** returns to the defaults. Each group has its own **random** button.
4. **Save** a look as a preset and **Load** it later. Presets are per sketch, and carry the ranges and automation as well as the values.
5. In the mapping editor (`:8100/edit`), set a surface's content to **generative** to put the sketch on it.

Everything is beat-locked: speeds are in cycles per beat, and **Beat punch** sets how hard each beat kicks the visual.

**Two pages.** The **Launchpad** (`:8110/pad.html`) is the phone one: pads for energy, effects,
presets and a desk section, with a launch-on-the-beat quantise. The **full controls** (`:8110/`) are
for rigging a look up. They share the same state over the same event stream, so one device can set
up while another plays. Both are described in **[visuals-live.md](visuals-live.md)**.

**Playing it live — [visuals-live.md](visuals-live.md).** Every parameter has a **range** (the orange
band on its track, with two ▲ arrows) that everything else respects, and an **automation** toggle that
moves it between the ends of that range on its own, in note values, locked to the beat. There are
keyboard shortcuts for the lot. That guide is the one to hand someone who is about to VJ; what
follows here is the reference.

### What the page stores

| | |
|---|---|
| Values | `GET`/`POST` `/api/params`, as before: `{id: value}` |
| Ranges and automation | `GET`/`POST` `/api/auto`: `{id: {on, lo, hi, rate, shape, phase, retrig, hz}}`, plus `_freeze` on POST to hold every automation where it stands |
| Presets | `{"_v": 2, "values": {...}, "auto": {...}}`. A preset written before automation existed is a flat `{id: value}` and still loads, with automation off and ranges wide open. |

The automation itself is worked out in [`render.js`](../brain/projector/web/render.js) (`autoEval`),
once per frame, from `u_beat` — so it is frame-exact on the projector, identical on every surface,
costs nothing on the network, and needs no shader recompile. The control page reads the same numbers
back out of the renderer to draw its moving markers.

### Marking a parameter in the JSON

Three optional fields, so the page does not have to guess from names:

| Field | Meaning |
|---|---|
| `"kind": "rate"` | This is a speed. The page snaps it to note values (1/32 … 8/1, dotted and triplet) and shows it as one. Stored in cycles per beat as everywhere else; negative is backwards and 0 is stopped. |
| `"kind": "quality"` | This buys frame rate, not looks. Randomise and Q/W/E leave it alone. `cathedral`'s Steps and Detail are marked this way. |
| `"kind": "fixed"` | This is identity, not a setting, so the dice leave it alone too. Rolling it does not give you a different look — it gives you something that is no longer the thing it is meant to be. `hypnotoad`'s collar, keyline and tint are marked this way (a Hypnotoad with a randomised collar is just a frog), and so are `wormhole`'s Two tone and Mirror. Two tone is a choice between black-on-white and colour, and a value half way between the two collapses the contrast between the card and the ink; Mirror decides whether half the words come out mirror-image, and rolling it means three rolls in four give you backwards type. Both are look decisions rather than energies, and both are the thing that sketch exists to protect. |
| `"energy": 1 / -1 / 0` | Which way this parameter pushes for Q/W/E: 1 = more of it is busier, -1 = calmer, 0 = neither, so just randomise it. Without the field the page uses a list of the usual movers and settlers. |

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
| `track` | The waveform of the song actually playing, from the decks. Mode 0 terrain (Unknown Pleasures made of the song: each ridge is a bar, the front one playing now, the bars to come rolling in, so drops are visible before they land), 1 scrolling colour waveform past a playhead, 2 ring (the current stretch round a circle with a sweeping hand), 3 bass/mids/highs meters. Bars shown, beats shown, playhead, brightness of what has played, height, contrast, width, glow, the track's own colours or a tint. Presets: terrain, terrain-gold, terrain-white, scroll, scroll-show, ring, meters. |
| `sisyphus` | A dung beetle pushing the sun up a hill that never ends, drawn as clean flat cartoon by default. **Hand** redraws the whole thing in another style: crayon scribble (colour outside the lines, paper tooth, boiling), 1930s rubber-hose cartoon (duotone, ben-day dots, grain and scratches), acid, or cycling all four every few bars. The sky runs day to night on its own loop; at night there's an aurora, a ringed planet, saucers, and a tractor beam that lifts the sun away while the beetle carries on pushing nothing. The sun has a face that squints and grimaces the higher it gets, and goes wide when it's taken or when it rolls back down. Hill: slope, bars per climb, size, leg swing. Sky: bars per day, night visitors. Hand: which style, bars per style, boil, ink. Then the three reactive slots ([reactive.md](reactive.md)): **A Hit** drives the legs and the sun's heat, **B Move** the twinkle and the acid drift, **C Change** the abduction. Presets: crayon, cuphead, acid, cycle, flipbook, night-shift, long-haul. |
| `emergence` | A Turing-pattern labyrinth after Maxime Causeret's video for Max Cooper's *Order From Chaos*. Pattern: complexity, stripe density, spots to worms to fill, solid blobs. Motion: slither (cycles per beat), rewire, spin, beat punch (fattens the worms). Organism: size, hole, ragged edge, grow through the song section. Colour: zone mixing, hue shift, saturation, follow the show's colour. |
| `flow` | Particles streaming through a noise flow field, leaving fading trails, after [Radiant](https://github.com/pbakaus/radiant)'s Flow Field with Particle Trails by Paul Bakaus (MIT). Field: detail, curl, evolve per beat. Particles: density, speed in heights per beat, trail length, line width, width and alpha variation, quality (trace steps: fewer is cheaper on the projector's GPU). Beat: punch (brighter, thicker on the kick) and push (the streams bend away from the centre on the kick). Colour: hue, spread, saturation, brightness, background, follow the show's colour. Presets: amber, mono, blue, rose, emerald, arctic (the original's colour schemes), illuminati-gold, storm. |
| `topo` | A topographic contour map of slowly evolving terrain, after [Radiant](https://github.com/pbakaus/radiant)'s Topographic Contour Map by Paul Bakaus (MIT). Every 5th contour is major, with elevation labels on a dark knockout. Terrain: hill size, relief, evolve per beat. Contours: levels, line width, glow, scroll (levels per beat, so the rings march up or down the hills). Beat: punch, a peak in the middle (negative for a crater), its radius, swell on the kick. Labels: chance, size, spacing. Colour: the original coral → amber → gold ramp or a tint (hue, spread low to high, saturation), brightness, background, vignette, follow the show's colour. Presets: amber, mono, blue, rose, emerald, arctic, pyramid-peak, rave-rings. |
| `pendulum` | Pendulum Wave, after [Radiant](https://github.com/pbakaus/radiant)'s Pendulum Wave by Paul Bakaus (MIT). Pendulum i swings (base + i) times per cycle, so they drift from a line through snakes and braids and fall back into line at the end of every cycle; the cycle is in beats, so the line comes back on the phrase (128 beats = 32 bars). Pendulums: count, cycle, swings per cycle for the longest, swing angle, trail in beats. Look: size, the curve through the bobs, pivot bar and guides. Beat: bobs flash on the kick, a ripple from the centre on each beat. Colour: the original amber → gold → coral or a tint (hue, spread left to right, saturation), brightness, background, follow the show's colour. Presets: amber, mono, blue, rose, emerald, arctic, phrase-gold (16-bar cycle), neon-swing. |
| `phyllotaxis` | Phyllotaxis Spiral, after [Radiant](https://github.com/pbakaus/radiant)'s Phyllotaxis Spiral by Paul Bakaus (MIT): a sunflower of glowing points, each a golden angle round from the last, with a faint Fibonacci lattice between neighbours. A pixel finds the few points that can touch it by solving for its place in the local Fibonacci lattice, so thousands of points cost only nine lookups. Spiral: points, spacing, grow from the centre over a cycle of beats (oldest points fade from the middle, everything fades before it restarts). Motion: spin, breathing (point sizes, along the spiral), tilt sway, a ripple outward on each beat. Look: point size and glow, lattice lines, centre glow, vignette. Beat: flash on the kick. Colour: the original amber → gold → coral along the spiral or a tint, brightness, background, follow the show's colour. Presets: amber, mono, blue, rose, emerald, arctic, golden-sunflower, vortex. |
| `sequin` | Sequin Wave, after [Radiant](https://github.com/pbakaus/radiant)'s Sequin Wave by Paul Bakaus (MIT): tiny mirror sequins on a hex grid, tilted by five interfering waves, flashing copper → gold → white as they catch the light. Ported nearly line for line (its reversed smoothsteps rewritten, since they're undefined in GLSL). Sequins: how many across, wave speed per beat, tilt, sparkle, individual shimmer. Beat: sparkle on the kick, a ring of flashes running out from the centre on each beat. Light: a roaming light (the original's mouse light) circling the surface, laps per 16 beats. Colour: the original gold or a tint, brightness, vignette, follow the show's colour. Presets: gold, silver, rose-gold, sapphire, emerald, disco-gold, dancefloor. |
| `gilt` | Gilt Mosaic, after [Radiant](https://github.com/pbakaus/radiant)'s Gilt Mosaic by Paul Bakaus (MIT): a Byzantine gold mosaic wall lit by three drifting candle lights, its tesserae turning over in a wave. Ported nearly line for line (reversed smoothsteps rewritten; its hash() is the renderer's). Mosaic: tiles per height, candlelight drift per beat, tile shimmer. Flip: wave on or off (off gives the still, shimmering wall), sweep and rest in beats (6 + 2 = one sweep every 2 bars), direction, a radial flip from the centre every N beats (the original's click). Beat: the gold flares on the kick. Colour: the original gold or a tint, brightness, vignette, follow the show's colour. Presets: byzantine, candlelit, silver-leaf, rose-gold, lapis, temple-drop, neon-temple. |
| `throne` | Golden Throne, after [Radiant](https://github.com/pbakaus/radiant)'s Golden Throne by Paul Bakaus (MIT): a golden sacred-geometry mandala of rings, petals, spokes, hexagons and triangles in counter-rotating layers, with golden-ratio spiral arms and fractal hex lace. Ported nearly line for line (reversed smoothsteps rewritten, and the original's spokes fixed: they drew dark rays through the mandala). Mandala: size, layers, spiral arms, lace. Motion: time per beat, layer rotation, whole spin. Beat: the lines glow and the centre flares on the kick. Colour: line glow, the original gold or a tint, brightness, follow the show's colour. Presets: golden-throne, cathedral, platinum, rose-window, lapis, ascension, portal. |
| `geometry` | Radiant Geometry, after [Radiant](https://github.com/pbakaus/radiant)'s Radiant Geometry by Paul Bakaus (MIT): golden sacred geometry that morphs from a tiled hex lattice of star rosettes to a single central mandala with petals, spiral arms and an ornate edge. Ported nearly line for line (reversed smoothsteps rewritten). Pattern: the morph (lattice → mandala), a swing toward the mandala over a cycle of beats, build through the song section (lattice early in a section, mandala by its end, so it forms through a BUILD), complexity (2 to 6 layers), size. Motion: time per beat, layer rotation, whole spin. Beat: the lines glow and the centre flares on the kick. Colour: line glow, the original gold or a tint, brightness, follow the show's colour. Presets: lattice, girih, mandala, breathing-temple (swings every 8 bars), build-to-mandala, platinum, neon-girih. |
| `tropical` | Tropical Heat, after [Radiant](https://github.com/pbakaus/radiant)'s Tropical Heat by Paul Bakaus (MIT): heat haze and chromatic aberration over flowing domain-warped noise in hot magenta, orange, amber and teal, with blooms of vivid colour. Ported nearly line for line (reversed smoothsteps rewritten). Heat: distortion, colour vibrancy, time per beat, zoom. Beat: the blooms flare on the kick; heat can follow the track's energy. Colour: hue shift, shift by the show's colour, brightness, vignette. Quality: octaves (the original's 6 is the heaviest sketch here) and chromatic mode: full samples the noise three times, once per colour channel, which is the original's fine, busy look; off (the default) samples once and shifts red and blue, a smoother liquid flow at about a third of the cost. Presets: tropical-heat (exactly the original), lite (cheapest), heatwave, lagoon, ultraviolet, carnival. |
| `eclipse` | A solar eclipse, played out: the moon crosses a limb-darkened sun over a cycle of beats, from a bite and a crescent through Baily's beads (sunlight through the valleys on the moon's limb) and the diamond ring into totality with the corona, chromosphere and pink prominences, then back out. The corona, solar wind, bloom and stars are from [Radiant](https://github.com/pbakaus/radiant)'s Eclipse Glow by Paul Bakaus (MIT; reversed smoothsteps rewritten, its hash renamed, stars and grain sized in output pixels). Eclipse: crossing in beats (0 = set the phase by hand; 0.5 is totality), how much of the cycle totality holds, totality as each song section ends (so a BUILD lands on totality), the moon's path angle, a miss (a partial eclipse), moon size (under 1 gives an annular ring of fire, with no corona), size. Sun: brightness, corona size, rays, prominences, lens streak, stars, corona time per beat. Beat: the corona and diamond ring flare on the kick; diamond strength. Colour: hue shift, shift by the show's colour, brightness. Presets: crossing, totality, diamond-ring, build-to-totality, ring-of-fire, partial, great-corona, blood-moon, black-sun. |
| `diamond` | Diamond Caustics, after [Radiant](https://github.com/pbakaus/radiant)'s Diamond Caustics by Paul Bakaus (MIT): prismatic fire through a brilliant-cut diamond, with caustic folds from faceted refraction, chromatic dispersion into rainbow fire, scintillating sparkles and star bursts. Ported nearly line for line (17 reversed smoothsteps rewritten, its hash and a local named refract renamed, float loops made int, and a seam in the original's dispersion fixed). Diamond: brilliance, fire (dispersion), sparkles, star bursts, zoom. Motion: time per beat, turning. Beat: sparkles and star bursts flash on the kick. Colour: hue shift, shift by the show's colour, brightness (default 0.55: the original's exposure washes out; the original-exposure preset has it). Heavy: about ten caustic lookups per pixel. Presets: brilliant, fire, ice, disco-diamond, sapphire, ruby, rave-rock, original-exposure. |
| `umbrella` | Rain on Umbrella, after [Radiant](https://github.com/pbakaus/radiant)'s Rain on Umbrella by Paul Bakaus (MIT): looking up through a rain-soaked umbrella at a blurred night city. The original simulates drops on a canvas every frame and hands them to a refraction shader; this is a stateless rebuild of the look: drops land (on the beat if you like), sit, then slide down the dome leaving trails of droplets, each one a lens onto a sharper, displaced piece of the city bokeh, with micro-droplets beading and drying between. The ribs, panels and hub are the original's shader code. Rain: amount, drop size, drop life in beats, slide, trails, micro-droplets, impacts on the beat. Look: refraction, city blur, city lights, walk (the city drifts past), umbrella ribs. Beat: the lights pulse on the kick. Colour: hue shift, shift by the show's colour, brightness. Presets: night-walk, downpour, drizzle, standing-still, neon-blue, rave-rain. |
| `artpop` | Artpop Iridescence, after [Radiant](https://github.com/pbakaus/radiant)'s Artpop Iridescence by Paul Bakaus (MIT): iridescent soap-film bubbles, thin-film rainbow bands over a domain-warped surface with fresnel edge glow and chrome highlights. Ported nearly line for line (reversed smoothsteps rewritten; the bubble edges' atan noise, which seamed at ±π, sampled round a circle instead; the small bubbles only computed where they are). Film: thickness (how many bands), flow per beat, warp (1 = the original, which folds the film into fine grain), size, small bubbles on or off, chrome highlights. Beat: the bands shimmer and the bubbles swell on the kick. Colour: band shift, shift by the show's colour, brightness. Quality: octaves (the original's 4 with full warp is about 190 noise lookups per pixel; the default 2 octaves at 0.4 warp is clean and about half that). Presets: holographic, original, lite, oil-slick, chrome-bubble, single-bubble, holo-pop. |
| `horizon` | Event Horizon, after [Radiant](https://github.com/pbakaus/radiant)'s Event Horizon by Paul Bakaus (MIT): a ray-traced Schwarzschild black hole. Each pixel follows its light ray's bent path (velocity-Verlet geodesics), crossing a Novikov-Thorne accretion disk with Doppler beaming and gravitational redshift, so the far side of the disk arcs over the shadow, with a photon ring and a lensed star field. Ported nearly line for line (its hash renamed). Black hole: zoom, disk brightness, chromatic (spectral rings), photon ring fringe, stars. Camera: orbit in turns per 64 beats, tilt (-0.2 gives the edge-on Interstellar view), roll, disk spin per beat. Beat: the disk flares and the photon ring pulses on the kick. Quality: step (1 = the original's up to 200 steps per pixel, the heaviest sketch here; the default 1.5 looks the same at two-thirds the cost). Presets: event-horizon, gargantua (original steps), lite, spectral, edge-on, from-above, singularity. |
| `burn` | Burning Film, after [Radiant](https://github.com/pbakaus/radiant)'s Burning Film by Paul Bakaus (MIT): celluloid catching fire in a projector. Burn holes open in dark film stock with a white-hot frontier and spread until it's all fire, embers glowing through, sparks drifting up, sprocket holes and grain; then it fades to black and a fresh strip starts. Ported nearly line for line (its many reversed smoothsteps rewritten, noise renamed, loop made int, grain sized in output pixels, and its sprocket holes, which came out as flat dashes, redrawn as real rounded holes). Burn: direction (spread, the default, or die down: the original's fire actually shrinks over its cycle, the opposite of what it describes), cycle in beats, burn through the song section (the film burns away over a BUILD, all fire by the drop), pattern drift, burn size. Fire: burning edge, ember glow, sparks. Film: sprocket holes, film run (the holes scroll through the gate, in holes per beat), grain. Beat: the frontier flares on the kick. Colour: hue shift, shift by the show's colour, brightness. Quality: octaves (6 = the original). Presets: burning-film, original, burn-the-build, fast-burn, slow-burn, blue-flame, toxic. |
| `vertigo` | Vertigo, after [Radiant](https://github.com/pbakaus/radiant)'s Vertigo by Paul Bakaus (MIT): an endless crimson tunnel of neon rings and segments, lit by waves of light running along it, with sparse ring flashes. Ported nearly line for line (reversed smoothsteps rewritten; its hash is the renderer's; its unused Spiral Intensity now twists the tunnel). Tunnel: speed in rings per beat, spiral, spin in turns per 64 beats, ring density, segments round. Light: wave speed, ring flashes, neon edges. Beat: the rings flash on the kick. Colour: hue shift, shift by the show's colour, brightness. Presets: vertigo, hyperdrive, spiral-down, ice-tunnel, acid, rave-tunnel. |
| `silk` | Silk Cascade, after [Radiant](https://github.com/pbakaus/radiant)'s Silk Cascade by Paul Bakaus (MIT): three layers of translucent silk in gold, rose and lavender, with domain-warped folds, Kajiya-Kay anisotropic sheen, backlit peaks and rare sparkles, drifting at different depths. Ported nearly line for line; the sheen's pinch points (where a fold flattens and its tangent is undefined) are faded out, and since the original's sheen is near full almost everywhere and washes the image out, sheen defaults to 0.7 with a contrast control (the original preset has both at 1). Silk: flow per beat, sheen, contrast, fold size, layers (1 to 3), sparkles. Light: the key light's orbit in turns per 64 beats. Beat: the sheen flashes on the kick. Colour: hue shift, shift by the show's colour, brightness. Presets: silk-cascade, original, emerald-silk, crimson-silk, single-sheet, disco-silk, show-silk. |
| `milking` | Alien Dairy: two greys milking a dancing cow under their saucer in a moonlit field, a cartoon drawn from 2D distance fields with ink outlines. The cow bobs, sways, stamps its legs in pairs, head-bops, swishes its tail and jingles its bell on the beat; the greys take turns, one squirt per beat, into a bucket that fills over a cycle of beats; the saucer's rim lights chase and its tractor beam flickers on the kick. Scene: dance, size, bucket fill in beats, ink line. Saucer: tractor beam, rim lights, beam hue, beam follows the show's colour. Night: stars, moon, brightness. Beat: the beam flares on the kick. Presets: moonlight-dairy, disco-dairy, slow-moo, red-alert. |
| `atlantis` | Atlantis Rising: Moses parts the sea and finds Atlantis, overrun by dolphins with thumbs. A cartoon drawn from 2D distance fields with ink outlines. The walls of water (foam, currents, spray) part over a cycle of beats, hold, then crash shut, or part through the song section so they're fully open by the drop; Moses raises his staff on every beat, its tip glowing; the temple, towers and crystal spire of Atlantis sit on the seabed, the crystal pulsing on the kick and throwing rays up between the walls; dolphins leap across the gap in their own lanes, each giving a thumbs up that pumps on the kick. The sea: part-and-close cycle in beats (0 = by hand), parted by hand, part through the section. Dolphins: how many, thumb size. Atlantis: crystal glow, light rays, glow hue, glow follows the show's colour. Look: size, ink line, brightness. Beat: the crystal and thumbs on the kick. Presets: parting, part-the-build, dolphin-party, red-sea-rave, exodus. |
| `wormhole` | **Your own words**, running round the inside of a pipe you are looking down at an angle. Type them on the Visuals page (or the pad's drawer) and separate them with `|` — up to eight, one per ring, cycling as the bars go by. Two changes of coordinates stacked. Take the log of the radius and you get a distance that never runs out, so stepping it by whole numbers gives ring after identical ring with no end and no seam, and the angle is somewhere to run text along; travelling inward and spinning are then one term each, both in cycles per beat, and every ring down to the vanishing point costs the same as the first. On its own that is a tunnel seen straight down its axis — vanishing point dead centre, every ring concentric, which is not what looking down a pipe is like — so before any of it the plane goes through a **Möbius transform**, `(z − a)/(1 − conj(a)·z)`. It maps circles to circles but moves the centre, so the rings come out nested and not concentric and the vanishing point sits off to one side; `a` is literally where it lands. Because the map is conformal the letterforms stay letterforms: sheared and scaled, never skewed. Its Jacobian is what keeps the hairline at each ring one pixel wide however far the map has stretched things there. **It is meant to be read**: black type on a near-white card with those hairlines, no colour and no effects, is the default, and **Hectic** is how much of the chromatic split, the trails and the bloom the A Hit driver brings in — so it goes wild on the drop and behaves itself the rest of the time. The three effects also have their own always-on sliders if you want them sitting there. **The sliders are scaled for reading, not for range.** Every min and max is set where the words are still legible, so the ends of the travel are a ring a bar and a turn every two bars rather than the several-per-beat they started at, the type cannot be subdivided smaller than about four words to a ring, and the three effects that smear letterforms cannot be pushed past a smear. The point is that a randomise — including **Drop** — gives you a different tunnel rather than an unreadable one, so there is no setting you have to avoid mid-set. Pipe: how far off centre the vanishing point is and how it wanders, rings per turn of scale, times the word goes round, how much of a ring it fills, travel, spin, **Twist** into a helix, alternate rings creeping back, and **Mirror** to fold the angle into wedges — the fold stretches the word lookup back over a full turn so a wedge holds whole words, and the count is capped so the wedges can never squeeze past four words to a ring. Half of them still come out mirror-image, which is what a kaleidoscope does to type, so Mirror is yours to turn on and the dice leave it alone. **Twist counts whole rings gained per turn**, and it has to be whole: `atan` has a branch cut at ±π, so a fractional twist makes the ring coordinate jump by a fraction of a ring where the angle wraps, and that shows up as a hard straight line out of the vanishing point with the bands stepped and the letters cut in half. A whole number closes the helix. It doubles as how many words are in the cycle, because crossing that wrap moves you exactly that many rings along the thread, so the word, its offset and its colour are taken mod the thread count — one thread is a single endless ring, three threads cycle three. Type: the ring hairline, weight, outline, Hectic. Scene: two tone, background when it isn't, fog into the vanishing point (which is also what takes the rings out down there before they go finer than a pixel and turn into noise — note it runs the other way, low is a *wider* fog), vignette. Then the three reactive slots ([reactive.md](reactive.md)): **A Hit** shoves the tunnel inward and brings in everything hectic, **B Move** the spin and the vanishing point wandering, **C Change** which word comes up next and the palette. Presets: panter, read-me, night-print, hyperspace, kaleido, strobe-words. |
| `hypnotoad` | ALL GLORY TO THE HYPNOTOAD. Built to the Futurama still: olive khaki, the cartoon's near-black brown line round everything, and the **red-rimmed black splat** of a pupil — drawn squashed and lobed rather than round, because that splat is the single most recognisable thing about him. Blotches over his back with the little "c" wart ticks on them, the two brow curls on his crown, nostrils, a pale khaki throat whose top edge runs right across him as the mouth, and the **mauve collar** with its stitch holes, mint buckle and hanging tag. Front-on and symmetrical: the still is a three-quarter view, but symmetry is what makes a centre-piece hypnotic, so the pose is squared up and every feature taken from the still. The hypno rings inside the eyes are faint at rest — the still has none — and come up with the hit, so he looks like himself until the kick lands. Everything behind him takes the hue: wavy concentric hypno rings on a small quantised palette, with **sacred geometry** over them in gold (0 Flower of Life, 1 Metatron's Cube, 2 a ring-and-spoke mandala), plus a soft shadow so he holds off a busy background. Toad: size, bob, blink, blotches, tint, collar, line weight. Eyes: size, pupil splat, hypno rings, how fast they run. Then the three reactive slots ([reactive.md](reactive.md)): **A Hit** the bob, the squash and the eyes flaring, **B Move** the geometry turning and the rings running, **C Change** the palette and how much line-work is on top. Presets: glory, obey, temple, stare, swamp, strobe-toad. |
| `inkwell` | Rubber hose cartoons, after Fleischer's *Out of the Inkwell*, arranged down a tunnel. One pen draws the lot, and it is thin and hard: bold comes from contrast — near-black ink against fills at full saturation on a dark card — not from thickness, and the line is floored at a pixel so it never strobes as it moves. Arms, stems, spouts and handles are hoses: one thickness, round ends, bending in a curve instead of hinging at a joint. The shapes are **masks** — each is filled with a log-polar tunnel of its own drawn in the subject's local coordinates, so the pattern travels and squashes with the shape, and with the faces off it is the interiors that carry the picture. Sixteen subjects (face, bird, tree, lamp, trolley, teapot, flower, fish, umbrella, toadstool, cactus, snail, ice cream, alarm clock, rocket, balloon), and they dance: a hop, a squash on the landing, a rock from the feet, a shimmy across and a turn to face left and right, each a step behind the last. **Faces and props are decided per cell, not globally** — sliders set how strong they are and how many of the cast have one, so a row of five can be two with eyes, one of those with a mouth, and a couple carrying something. Every subject has its own prop: steam off the teapot, a leaf off the tree, a bee round the flower, a hat that will not stay on, a drip down the ice cream. **Layout** 1 is the tunnel — log(*r*) against the angle, repeated on both, so the cast recedes forever and Spin and Zoom are one term each; layout 0 is a chorus line along a floor, which suits a wide surface and suits faces (in the tunnel everything is rotated radially, so faces read as tilted heads). Cast: layout, how many across or around, bars per subject, size, bounce, dance. Movement: spin and zoom, in cycles per beat. Pen: line weight, boil, noodle. Fill: pattern amount, **which pattern** (0 guilloché — two engine-turned line fields crossing, as on a banknote; 1 halftone dot screen; 2 op rings after Riley; 3 the log-polar spiral), rings across the shape, pattern travel in cycles per beat. Faces and props: how strong, how many of them, and how much C Change brings the faces in. Scene: kaleidoscope (a quantised hue turn rather than a wash, so it tints without desaturating — 8% by default), rosette (a backdrop built from mirrored wedges and hard concentric bands, structured by value in one hue rather than by hue, which at this brightness would only make mud), background brightness, film. Colour is a **small quantised palette** — `palette` sets how many hues are in it and every fill, and the backdrop, is a step of it. A continuous rainbow is the single thing that makes work like this read as a screensaver. Then the three reactive slots ([reactive.md](reactive.md)): **A Hit** the bounce, the squash and the eye pop, **B Move** the noodle and the kaleidoscope turning, **C Change** the palette, who the cast reaches for next, and the faces. Presets: tunnel, chorus, warp, deep, silent, sunday-comic, they-blink. |
| `cathedral` | A kaleidoscopic fractal you fly through and never reach the end of. Space is mirrored into wedges around the axis of travel, tiled so there is stonework in every direction, then folded back into itself, which gives arches inside arches inside arches at every scale; a nave is cut down the middle to fly along. **Raymarched**, so the depth is real: near stone hides what is behind it and the far end goes to fog, and the colour comes off the geometry (an orbit trap) rather than a gradient laid over it. Structure: wedges, fold passes, fold scale, form (floating chunks to solid crystal), fold angle (plain to intricate), nave width. Flight: beats per bay, twist, roll, sway. Render: steps, depth, fog, glow, shading. Then the three reactive slots ([reactive.md](reactive.md)): **A Hit** releases a ring of light down the nave and breathes the walls out, **B Move** bends the fold angle, which reshapes the whole building, **C Change** moves the fold's offset and the palette. Presets: nave, gold-vault, hyperdrive, crystal, rose-window, strobe-hall, cavern, lean. |

Low sides with no roundness, zero wave frequency and some twist gives the stacked, rotating-polygon spirograph look. High frequency with small amplitude gives rippling contour lines. In `field`, turning up Links with some Wander gives a drifting net; Wave with no Wander gives a clean grid of dots swelling in bands. In `emergence`, a large Size with no Hole fills the surface with maze (good for walls), and low Spots → worms gives cells instead of worms.

`emergence` is not a real reaction-diffusion simulation (that needs a feedback buffer the renderer doesn't have yet). It adds up plane waves of one wavelength in scattered directions and colours where the sum is above a level, which gives the same labyrinth with no memory between frames, so every surface stays in sync.

### Parameters that can empty the picture

The rule is that nothing may ever blank the screen, and the ranges are always clamped to each
parameter's own min and max, so automation cannot take a value somewhere the sketch does not allow.
Within that, these are the ones to be careful of when setting a range by hand:

| Sketch | Parameter | At its extreme |
|---|---|---|
| any reactive | `aamt` `bamt` `camt` at 0 | Not blank, but nothing reacts — the picture goes static |
| `cathedral` | `far` at its lowest | The ray stops before it reaches anything; almost everything goes to fog |
| `cathedral` | `glow` 0 with `shade` 0 | Flat silhouettes, no depth |
| `inkwell` | `bg` at 0 | The card goes black; the cast still draws, so it reads rather than disappears |
| `inkwell` | `size` at its lowest | The cast shrinks towards specks |
| `inkwell` | `pat` 0 **and** `face` 0 | Legal and fine — flat colour shapes — but the least interesting thing the sketch does |
| `wormhole` | `fog` at its lowest | **Was** a blank card, and is why its floor is 0.3 rather than 0.05. The fog radius is `0.07 / fog`, so it grows as the slider falls; the Möbius map keeps the whole frame inside the unit disc, so anything past a radius of 1 fogs the entire picture to paper. An inverse relationship is easy to range-check the wrong way round |
| `subliminal` `redacted` | `bg` / paper values | Can go to solid black between flashes, which is the intent |

`cathedral`'s fold angle was the one real offender and is no longer reachable: the slider is mapped
onto the window that always builds something (see [reactive.md](reactive.md#gotcha-a-driver-must-not-be-able-to-empty-the-picture)).

### What `cathedral` and `inkwell` cost

`inkwell` grew expensive when it gained the tunnel, the masked interiors and sixteen subjects:
on the same CPU rasteriser it went from about 124 ms a frame to **289**, against 149 for
`sisyphus`, 146 for `hypnotoad`, 114 for `wormhole` and 298 for `cathedral`. (`hypnotoad` is in the safe class and
wants no special care; its Metatron geometry is the dearest of its three modes at about 218,
because that one walks the lines between thirteen circle centres, against 143 for the mandala.) Adding the props and the four pattern modes on top of that
cost nothing measurable, because only one subject's branch and one pattern run per pixel. Only one subject's branch runs per pixel, and
on a real GPU the cells are large enough that neighbouring pixels almost always take the same
one, so it should land nearer `sisyphus` there than this suggests — but it is no longer in the
safe class it was, so **give it the same treatment as `cathedral` and watch the fps on the rig.**
Turning Pattern to 0 and using the row layout are the two cheapest things to try.


`cathedral` is the only sketch that raymarches: it walks a ray through the scene for every
pixel, where every other sketch answers each pixel with a formula. On a CPU rasteriser here, at
1280×720 and its defaults, it measured about **270 ms a frame against 18 for `seething`, 22 for
`emergence` and 40 for `rings`** — roughly seven times the most expensive sketch we already run,
and thirteen times a typical one. That was not measured on the projector's own GPU, which
parallelises marching far better than a CPU does, so treat it as an order of magnitude and not a
prediction: **put it on the rig and watch the fps on the projector's stats before it goes in a set.**

If it struggles, in this order:

- **Detail** (fold passes) is the lever that pays: 5 → 3 took about a fifth off, and 7 put a fifth back on.
- **Depth** shortens the rays that hit nothing.
- **Steps** is nearly free either way — 64 → 32 saved under a tenth, and 96 cost nothing over 64, because at these settings most rays already stop on a hit or run out of Depth long before the cap. Turn it down for the frame rate and you mostly lose thin stonework for nothing.
- The **lean** preset is those three already set low.

Each generative surface is drawn separately, so putting `cathedral` on two surfaces costs twice,
and the Stage page draws it again on top of the projector's own copy.

## Transitions

Changing the sketch, or loading a preset, hands over on the projector through a transition in time with the music, set in the **Transitions** section of the control page. The old sketch stays up until the sync point (now, or the next beat, bar or 4-bar phrase), then the two play together for the transition's length in beats.

| Type | What it does |
|---|---|
| Auto (smart) | Picks one that suits the song section showbrain is in, never the same twice running: a flash cut, a stutter or a zoom into a PREDROP or DROP; a zoom, swirl, pixelate or tiles through a BUILD (1 bar); a dissolve, luma, crossfade or iris in a BREAKDOWN, INTRO or OUTRO (4 bars); a wipe, iris, tiles, slices, dissolve, pixelate or swirl in the groove. |
| Cut | An instant change on the sync point. |
| Crossfade | A straight fade. |
| Wipe | A soft line sweeps across at one of 8 angles, lit in the show's colour. |
| Iris | A glowing circle opens from the centre. |
| Dissolve | The new sketch burns through the old in noise-shaped holes with a hot edge. |
| Luma | The new sketch's bright parts appear first, then its darks. |
| Tiles | Squares pop in at random, each growing from its centre. |
| Glitch slices | Horizontal bands of the new sketch slide in from the sides. |
| Zoom through | The old sketch zooms in and away while the new one flies in from the centre as a framed picture. |
| Swirl | The old one twists away as the new one untwists in. |
| Stutter | The two flicker on 16th notes, the new one more and more, until it holds. |
| Flash cut | A white flash, with the cut on its peak. |
| Pixelate | The old one breaks into big pixels and the new one resolves out of them. |
| None | Instant, as before. |

Length is automatic (each type's own) or 1 beat to 8 bars. **Presets morph too** makes loading a preset transition from the old values to the new ones in the same sketch. **Mix to a random sketch** switches to another sketch with one of its shipped presets through the current transition, for quick mixing. The API is `GET/POST /api/transition` (`type`, `beats`, `sync`, `presets`), `POST /api/next`, and `POST /api/select` takes an optional `"transition": {...}` to override the settings once (e.g. `{"type": "cut"}`).

How it's drawn: while a transition runs, each generative surface draws the outgoing sketch with its old values and then the incoming one on top, whose alpha is the transition's mask (in `render.js`, `COMMON`: `u_trole`, `u_tp`, `u_tmode`, and the `s5t_` functions). Either side can warp its own coordinates (zoom, swirl, pixelate, slices). There's no render-to-texture, so it runs on the projector's WebGL1 GPU, but for the transition's length the surface costs both sketches together: going between two heavy sketches (tropical, diamond, artpop, horizon) may stutter on the X3. Sketches need no changes.

## Writing a sketch

Add two files to `brain/visuals/sketches/`:

- **`NAME.glsl`**: declares `uniform float p_<id>;` for each parameter and defines `vec3 content(vec2 uv)`. `uv` is 0..1 across the surface. It can use everything the projector's shaders get: `u_beat`, `u_frac`, `kick()` (1 on the beat, decaying), `u_hue`, `u_energy`, `u_scene`, `u_aspect`, `hsv()`, `hash()`, `wave(beat)` (the live track's waveform, see below), and `drive()` with `band()`, `loopBeats()` and `barBeat()` (see [reactive.md](reactive.md)). See [`render.js`](../brain/projector/web/render.js) (`COMMON`).
- **`NAME.json`**: title, description and parameter groups, each parameter with `id`, `label`, `min`, `max`, `step` and `default`. The control page builds its sliders from this.

Deploy with `brain/deploy.sh visuals` and pick it in the Sketch card on the control page. If the shader doesn't compile, the control page shows the error and the projector keeps the last working sketch.

For sketches driven by the track's frequency bands on their own loop lengths — the kick punching on the beat, the hats in 8ths, the chords swelling over 8 bars — see [reactive.md](reactive.md). Every sketch already has `drive()`; `sisyphus` is the one built on it.

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
## The live track's waveform

Sketches can draw the song that's playing. rekordbox analyses every track when the USB is prepared, the decks share that colour waveform over Pro DJ Link, and deckdash already fetches it with the beat grid (`/api/wavedetail/N`, `/api/timeline/N`). Nothing has to be uploaded per song; it works for any track loaded from rekordbox media.

- `trackwave.py` in the visuals service follows showbrain's live deck. When its track changes (deckdash's `waveformKey`), it fetches the waveform and beat grid and resamples the waveform onto the grid, 8 samples per beat, keeping the loudest frame in each slice. It pushes the result to every page once per track as a `wave` event: RGBA bytes (height, bass, mids, highs) in a 256-wide texture.
- `render.js` uploads it as a texture and gives every sketch `vec4 wave(float beat)`: height, bass, mids and highs (0..1) at any beat of the track, where 1 is the first beat. Sketches look it up with `u_beat`, so it stays on the beat through tempo changes and can read ahead (`wave(u_beat + 16.0)` is four bars from now). Outside the track it returns 0.
- The `track` sketch uses it (terrain, scroll, ring, meters).
- **At home** (no decks) it plays a demo track, looped. To test with a real track, capture one on the rig with a track loaded: `python3 brain/visuals/tools/capture_wave.py http://<brain IP>:8080`. That saves `brain/visuals/state/wave-sample.*` (not in git), which is then used, looped, whenever no deck is live.
- `GET /api/wave` returns the current waveform message (`source`: `live`, `sample` or `demo`; `title`, `beats`, `spb`, `w`, `h`, `data`).
## The words you type

Sketches can't draw type by themselves, so the page draws it for them. There is a **Words** field
on the Visuals page and in the pad's drawer: type a few words separated by `|` and every sketch
can read them immediately.

- The service holds one string (`GET`/`POST` `/api/text`, up to 240 characters, control characters
  stripped) and pushes a `text` event to every page and projector.
- [`render.js`](../brain/projector/web/render.js) `setText()` splits it on `|` or a newline, takes
  the first eight words, and draws each into one row of a 2048×2048 eight-row atlas — each word
  scaled down to fit its row so the letterforms keep their proportions however long the word is.
  Drawn once per change on the CPU, uploaded as one texture. 2048 gives each row 256 pixels of
  height, which sounds generous until a sketch magnifies one row over half the screen: `wormhole`'s
  nearest ring does exactly that, and at 128 the diagonals of the letterforms stair-stepped.
- Every sketch gets `uniform sampler2D u_text`, `uniform float u_textn` (how many rows are in
  use) and the helper **`float word(vec2 uv, float row)`** in `COMMON`: coverage of word `row`
  at `uv`, where `uv` is 0..1 across that word's own row and `uv.y = 0` is the top of it. Off the
  edge of the word it returns 0, so a sketch can lay type anywhere without clipping it.
- The words are saved with the live values and go into presets, so a preset can carry its own
  message. `wormhole` is built on this; `subliminal`, `redacted` and `cipher` still use the older
  baked 5×7 font (`tools/glsltext.py`), which is compiled in and not editable live.

## Reaction-diffusion lab

**`http://sektor5.local:8110/rd.html`** (on Android, use the IP) is a standalone test page running a real Gray-Scott reaction-diffusion simulation on the GPU, after [Karl Sims](https://www.karlsims.com/rd.html). It is not a sketch: it's there to find looks and to check what the projector's GPU can handle before simulations go into the shared renderer.

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

`GET /api/events` (SSE: `sketch`, `params`, `state`, and `wave` once per track), `GET /api/wave`, `GET /api/sketch`, `GET /api/sketches`, `GET/POST /api/params` (POST any subset, values are clamped to their ranges), `POST /api/select {"sketch": NAME}`, `GET /api/presets`, `GET/POST /api/presets/NAME`, `POST /api/presets/NAME/load`.
