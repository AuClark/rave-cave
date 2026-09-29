// Wormhole: your own words running round the inside of a pipe you are falling down.
//
// Two ideas stacked. Take the log of the radius and you have a distance that never runs out, so
// stepping it by whole numbers gives ring after identical ring with no end and no seam, and the
// angle is somewhere to run text along. Reading is then one lookup: the ring picks the word, the
// angle picks the letter, the height across the ring picks the line of it. Travelling inward and
// spinning are one term each, both in cycles per beat, and every ring down to the vanishing
// point costs the same as the first.
//
// On its own that gives a tunnel seen straight down its axis, with the vanishing point dead
// centre and every ring concentric -- which is not what looking down a pipe is like. So before
// any of it, the plane goes through a Mobius transform. It maps circles to circles but moves
// the centre, so the rings come out nested and not concentric and the vanishing point sits off
// to one side. That one complex divide is the whole of the perspective, and because the map is
// conformal the letterforms stay letterforms: they are sheared and scaled, never skewed.
//
// The log radius is also a depth. -log(r) is how far down the pipe a point is, the same for a
// whole ring, so fog is one exp() of it, and the light at the end of the pipe is a glow round
// r = 0. The picture is lit, not printed: a dark ribbed wall, type that glows, darkness gathering
// with depth and a light at the end that the kick flares. Two tone turns all of that back into
// black type on card, where the depth becomes haze instead.
//
// The music does three different things. The kick (A Hit) lurches you down the pipe and fires a
// ring of light out of the vanishing point at you, and on the drop brings in the smears (the
// streaks, the chromatic split, the bloom) by Hectic. The hats glint the seams between the rings.
// The chords (B Move, C Change) wander the vanishing point round and turn the palette and the
// words. The lurch is not the hit's amount: it is a step of travel on every beat, eased, so the
// position only ever goes forward. A hit that shoves forward and relaxes back reads as the tunnel
// wobbling, not as falling.
//
// Being readable is a property of the ranges, not of the defaults, so the ranges in the json are
// set where the words survive rather than where the maths stops. Two tone and Mirror are marked
// fixed: one decides card against light and the other decides whether half the words read
// backwards; neither is an energy. Two guards live here rather than in the json because they are
// about how parameters combine: the word count is capped against Mirror, and the type is taken
// out by the pixel as it goes too fine to read (the atlas has no mipmaps, so the far rings would
// otherwise shimmer).
//
// The other thing worth knowing before changing anything here is that atan() has a branch cut at
// +/-pi, and every straight-line artefact this sketch has ever had came out of it. Anything added
// to the ring coordinate that is not periodic over a full turn leaves a visible slice there. That
// is why Twist counts whole rings per turn and why the word, its offset and its colour are taken
// mod the thread count: see the notes in ring().
//
// Drivers (docs/reactive.md): A Hit -> the light pulse, the core flare, and everything hectic;
// B Move -> the spin and the vanishing point wandering; C Change -> the next word and the palette.
// Params are p_* uniforms; ranges and defaults are in wormhole.json.
uniform float p_rings, p_reps, p_height, p_zoom, p_lurch, p_spin, p_twist, p_counter, p_mirror,
              p_off, p_offspin,
              p_seam, p_weight, p_edge, p_glow, p_trail, p_chroma, p_hectic,
              p_mono, p_bg, p_fog, p_core, p_pulse, p_hats, p_rib, p_vign,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_palette, p_spread, p_sat, p_follow;

#define TAU 6.2831853

// The Mobius transform (z - a) / (1 - conj(a) z), which is what tips the tunnel off its axis.
// It sends the point a to the origin, so a is literally where the vanishing point lands. jac is
// how much one screen pixel is worth in the mapped plane, which the hairlines and the type's
// level of detail need to stay right however much the map has stretched things there.
vec2 mobius(vec2 z, vec2 a, out float jac) {
  vec2 num = z - a;
  vec2 den = vec2(1.0 - (a.x * z.x + a.y * z.y), a.y * z.x - a.x * z.y);
  float dd = max(dot(den, den), 1e-6);
  jac = (1.0 - dot(a, a)) / dd;
  return vec2(num.x * den.x + num.y * den.y, num.y * den.x - num.x * den.y) / dd;
}

// Everything about a pixel that does not change between the extra lookups (the chromatic split,
// the outline, the streaks) is worked out once in content(); a lookup is then this, which is a
// floor, a fract and a texture fetch. lr is the ring coordinate, au the angle already unfolded
// for Mirror, uo a shift round the ring. Gives back (coverage, thread) -- the thread is the ring
// number taken mod the thread count, so it is safe to colour by.
float g_tw, g_reps, g_h, g_counter, g_shift, g_sharp, g_lod;
vec2 ring(float lr, float au, float uo) {
  float rg = floor(lr);
  float v = lr - rg;
  // Crossing the atan cut moves you exactly |tw| rings along the thread, so anything that varies
  // from ring to ring -- the word, its offset, its colour -- jumps there unless it repeats with
  // that period. Taking it mod the thread count is what makes it repeat, and it is also just
  // what a helix is: one thread is a single endless ring, three threads cycle three.
  float key = g_tw != 0.0 ? mod(rg, abs(g_tw)) : rg;
  // Each ring sits round from the last so the words never line up into columns; alternate rings
  // creep the other way. Into the offset, not the coordinate: negating the coordinate turns a
  // ring round but mirrors every letter on it.
  float dir = mod(key, 2.0) < 0.5 ? 1.0 : -1.0;
  float u = fract(au / TAU * g_reps + key * 0.37 + uo + dir * g_counter);
  float c = word(vec2(u, (v - 0.5) / g_h + 0.5), key + g_shift);
  // The atlas is sampled bilinear with no mipmaps. Close up that is a soft edge a few pixels
  // wide, which the remap below brings back to one pixel; far off it is a letter smaller than
  // its texels, which shimmers, so it is eased to its average and the ring reads as a band.
  c = smoothstep(0.5 - g_sharp, 0.5 + g_sharp, c);
  return vec2(mix(c, 0.15 * step(0.0, (v - 0.5) / g_h + 0.5) * step((v - 0.5) / g_h + 0.5, 1.0), g_lod), key);
}

vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> pulse, core flare, hectic
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> spin, and the axis wandering
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> the next word, the palette
  float hats = drive(3.0, 0.0, 0.0, p_hats);             // the hats, as they are: the seams glint

  float t = u_beat;
  float H = p_hue + (p_follow > 0.5 ? u_hue : 0.0) + 0.13 * C;
  float PAL = max(2.0, floor(p_palette + 0.5));
  float mono = step(0.5, p_mono);

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;

  // Where the vanishing point sits, and the slow wander of it. Kept inside the unit disc, which
  // is where the Mobius map is well behaved.
  float oa = t * p_offspin * TAU + B * 0.8;
  vec2 axis = vec2(cos(oa), sin(oa)) * clamp(p_off, 0.0, 0.85);

  // Travel. The steady part is the rate; the lurch is a step of travel on every beat, eased out
  // from the beat so it is fastest on the kick. Both only go one way, in the direction of travel,
  // and the step is whole at the end of each beat, so the sum is continuous and beat-locked.
  float fb = fract(t);
  float ease = (1.0 - exp(-6.0 * fb)) / (1.0 - exp(-6.0));
  float dirT = p_zoom < 0.0 ? -1.0 : 1.0;
  float travel = t * p_zoom + dirT * clamp(p_lurch, 0.0, 0.5) * (floor(t) + ease);

  float jac;
  vec2 z = mobius(p, axis, jac);
  float r = max(length(z), 1e-5);
  // A pixel exactly on the axis's horizontal (an odd-sized surface with the vanishing point dead
  // centre has a whole row of them) gets atan(0, x), which some GPUs -- SwiftShader among them --
  // do not return cleanly, and it drew a dashed line across the picture. Nudged off zero.
  float ang = atan(abs(z.y) < 1e-6 ? 1e-6 : z.y, z.x) + t * p_spin * TAU + B * 0.6;

  // Mirroring folds the angle into a wedge, and a wedge is only TAU/(2m) wide. The word lookup
  // has to be stretched back over a whole turn or it would only ever sample the first 1/(2m) of
  // the word. The twist keeps the folded angle, so the rings kink at the wedge edges.
  float au = ang, mm = 1.0;
  float m = floor(p_mirror + 0.5);
  if (m > 1.5) {
    float seg = TAU / m;
    ang = abs(mod(ang + seg * 0.5, seg) - seg * 0.5);
    au = ang * 2.0 * m;
    mm = 2.0 * m;
  }

  // Twist is a whole number of rings gained per turn, and it has to be whole: going once round,
  // ang jumps by TAU at the atan cut and lr by TAU * twist, and any fraction of a ring in that
  // jump is a straight line out of the vanishing point with the letters cut in half along it.
  g_tw = floor(p_twist + 0.5);
  // At most four words round the whole circle, however the wedges divide it. Floored because a
  // fractional count leaves a part-word at the seam.
  g_reps = max(1.0, floor(min(p_reps, 4.0 / m)));
  g_h = clamp(p_height, 0.05, 1.0);
  g_counter = t * p_counter;
  g_shift = floor(C * 4.0);
  float lr = log(r) * p_rings - travel + g_tw * (ang / TAU);

  // One screen pixel is u_px; through the map that is u_px * jac, and in ring units it is |grad
  // lr| of that. The same number sizes the hairline, sharpens the type close up, and takes the
  // type and the seams out where they go finer than the pixels.
  float grad = sqrt(p_rings * p_rings + (g_tw / TAU) * (g_tw / TAU));
  float lrPx = max(grad * u_px * jac / r, 1e-6);
  float texV = 256.0 / g_h * lrPx;                              // atlas texels per pixel, across
  float texU = 2048.0 * g_reps * mm / TAU * u_px * jac / r;     // and along the ring
  float tpx = max(texU, texV);
  g_sharp = 0.5 * clamp(tpx, 0.12, 1.0);
  // How tall a capital is on screen, in pixels (the atlas draws them about 0.8 of a row).
  // Under a couple of pixels there is nothing left to read, only shimmer.
  g_lod = 1.0 - smoothstep(1.5, 4.0, 205.0 / texV);
  float resolve = 1.0 - smoothstep(0.08, 0.35, lrPx);           // 0 once a ring is under ~3px

  // Depth: -log(r) is how far down the pipe this ring is, 0 about where the screen edge is.
  float depth = max(-log(r), 0.0);
  float light = exp(-depth * p_fog * 1.8);

  // Hectic is how much of the smearing the hit brings in, and the drop brings in a little more.
  float drop = abs(u_scene - 7.0) < 0.5 ? 1.0 : 0.0;
  float hx = p_hectic * (A + 0.35 * drop);
  float chroma = min(1.0, p_chroma + hx * 0.85);
  float trail = min(1.5, p_trail + hx * 1.1);
  float glow = min(1.2, p_glow + hx * 0.6);

  vec2 s0 = ring(lr, au, 0.0);
  float cov = s0.x * resolve, thread = s0.y;
  float v = fract(lr);
  float seam = min(v, 1.0 - v) / lrPx;

  // The colours. Lit: a dark wall in the show hue, type in a spread of hues either side of it,
  // one per thread, and a light at the end that is nearly white. Two tone: card and ink.
  float wh = mod(thread, PAL) / (PAL - 1.0) - 0.5;
  vec3 wall = hsv(fract(H - 0.04), 0.85 * p_sat, p_bg);
  vec3 ink = hsv(fract(H + p_spread * wh), 0.9 * p_sat, 1.0);
  vec3 coreC = mix(vec3(1.0), hsv(fract(H + 0.06), 0.9 * p_sat, 1.0), 0.45);
  vec3 card = vec3(0.94, 0.93, 0.91), black = vec3(0.05, 0.05, 0.06);

  // The kick's ring of light: fired from the vanishing point on the hit and out past the camera
  // inside a beat (half one on the 8ths), fading as it comes. It rides the untwisted depth, so it
  // is a nested circle of the pipe even when the words are a helix.
  // Its own envelope rather than A's shape, so a punch that is over in a tenth of a beat still
  // gets its ring all the way out: how hard the loop fired is the ramp shape over its phase.
  float L = loopBeats(p_aloop);
  float ph = fract(barBeat() / L);
  float hit = p_aamt * clamp(drive(p_aband, p_aloop, 2.0, 1.0) / max(ph, 0.02), 0.0, 1.0);
  float since = ph * L / min(L, 1.0);
  float lg = log(r);
  float pos = mix(-3.0, 0.6, sqrt(clamp(since, 0.0, 1.0)));
  float pd = (lg - pos) / (0.05 + 0.12 * since);
  float pulse = p_pulse * sqrt(hit) * 1.6 * max(1.0 - since, 0.0) * exp(-pd * pd);

  // The light at the end: a hot core, a wider halo round it, both flared by the hit.
  float coreR = 0.035 + 0.05 * p_core;
  float core = p_core * (exp(-r / coreR) + 0.35 * exp(-r / (coreR * 4.0))) * (1.0 + 1.6 * A);

  // The hairlines swell as the pulse goes by.
  float sw = p_seam * (1.0 + 2.5 * pulse);
  vec3 col;
  if (mono < 0.5) {
    // The wall is ribbed: each ring is a rounded rib, darker into the seam, so the pipe has a
    // surface to it. The seam itself is a line of light, glinting on the hats.
    float rib = mix(1.0, 0.35 + 0.65 * sqrt(sin(3.14159 * v)), p_rib * resolve);
    col = wall * rib * (0.6 + 0.4 * light);
    if (p_seam > 0.004) {
      float ln = (1.0 - smoothstep(sw, sw + 1.2, seam)) * resolve;
      col += mix(ink, vec3(1.0), 0.5 * hats) * ln * (0.18 + 1.2 * hats) * (0.2 + 0.8 * light);
    }
    // The letters, with a chromatic split when it is called for: two more lookups a little
    // round the ring either way.
    vec3 lit = ink * (0.3 + 0.9 * light) + vec3(0.22) * light * light;
    if (chroma > 0.004) {
      float o = chroma * 0.018;
      float cr = ring(lr, au, -o).x * resolve, cb = ring(lr, au, o).x * resolve;
      // Bright fringes, outside the letter only, so the split reads as light and not a shadow.
      float lf = (0.45 + 0.55 * light) * (1.0 - cov);
      col += vec3(1.0, 0.15, 0.45) * cr * 0.8 * lf;
      col += vec3(0.1, 0.6, 1.0) * cb * 0.8 * lf;
    }
    col = mix(col, lit, cov);
    // The pulse lights whatever it passes, the wall a little and the type a lot.
    col += mix(ink * 0.6 + coreC * 0.4, vec3(1.0), 0.5 * cov) * pulse * (0.4 + 1.1 * cov);
  } else {
    // Two tone: black type on card. The depth is haze: ink goes back into the card with distance.
    col = card;
    if (p_seam > 0.004) {
      float ln = (1.0 - smoothstep(sw, sw + 1.2, seam)) * resolve;
      col = mix(col, black, ln * 0.85 * (0.25 + 0.75 * light) * (1.0 + 0.4 * hats));
    }
    if (chroma > 0.004) {
      float o = chroma * 0.018;
      float cr = ring(lr, au, -o).x * resolve, cb = ring(lr, au, o).x * resolve;
      col = mix(col, vec3(0.95, 0.15, 0.20), cr * 0.6 * light);
      col = mix(col, vec3(0.15, 0.35, 0.95), cb * 0.6 * light);
    }
    col = mix(col, black, cov * (0.15 + 0.85 * light));
  }

  // An outline just outside the letters, and a bloom outside that, both off the coverage sampled
  // a little way off round the ring and across it (a letter is taller than it is wide here, so
  // the offset across is in ring units, sized to match). The bloom takes two radii, nearer
  // weighted more, which is soft enough without the grain a jittered radius gave it.
  float w = 0.006 * (1.0 + p_weight), wv = 0.035 * (1.0 + p_weight) * g_h;
  if (p_edge > 0.004) {
    float near = max(max(ring(lr, au, w).x, ring(lr, au, -w).x),
                     max(ring(lr + wv, au, 0.0).x, ring(lr - wv, au, 0.0).x)) * resolve;
    float halo = clamp(near - cov, 0.0, 1.0);
    col = mix(col, mono > 0.5 ? black : ink * 0.1, halo * p_edge * 0.85);
  }
  if (glow > 0.004) {
    float soft = 0.0;
    for (int i = 1; i <= 2; i++) {
      float k = 1.3 * float(i);
      soft += (0.7 - 0.2 * float(i)) * (ring(lr, au, w * k).x + ring(lr, au, -w * k).x +
                                         ring(lr + wv * k, au, 0.0).x + ring(lr - wv * k, au, 0.0).x);
    }
    float bloom = soft * 0.4 * resolve * (1.0 - cov);
    if (mono < 0.5) col += mix(ink, vec3(1.0), 0.3) * bloom * glow * 1.4 * (0.3 + 0.7 * light);
    else col = mix(col, black, bloom * glow * 0.45 * light);   // on card, a bloom is ink bleed
  }

  // Streaks: the same rings a little further down the pipe, which is where they were a moment
  // ago, so the type smears out towards you -- motion blur without a frame of history. The length
  // is in rings and grows with the travel, so standing still gives no smear.
  if (trail > 0.004) {
    float sp = clamp(abs(p_zoom) + clamp(p_lurch, 0.0, 0.5) * 2.0 * exp(-4.0 * fb), 0.03, 0.6);
    // Four steps with a per-pixel jitter, so the copies melt into one smear instead of stepping.
    float jit = hash(uv * u_res);
    float len = (0.025 + 0.09 * sp) * dirT;
    for (int i = 1; i <= 4; i++) {
      float fi = float(i);
      vec2 b = ring(lr + (fi - jit) * len, au, 0.0);
      float k = b.x * resolve * trail * (0.5 - 0.1 * fi);
      vec3 tc = mono > 0.5 ? black : hsv(fract(H + p_spread * (mod(b.y, PAL) / (PAL - 1.0) - 0.5) + 0.03 * fi), 0.9 * p_sat, 1.0) * light;
      col = mono > 0.5 ? mix(col, tc, k * 0.6) : col + tc * k * 0.7;
    }
  }

  // Down at the vanishing point the rings go finer than a pixel; the fog and the light take over.
  if (mono < 0.5) {
    col = mix(wall * 0.3, col, max(resolve, 0.0));
    col += coreC * core;
  } else {
    col = mix(card, col, resolve);
    col = mix(col, vec3(1.0), clamp(core * 0.6, 0.0, 1.0));
  }
  col *= 1.0 - p_vign * pow(clamp(length(p * vec2(0.85, 1.25)), 0.0, 1.0), 2.5);
  return col;
}
