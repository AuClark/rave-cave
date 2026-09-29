// Wormhole: your own words running round the inside of a pipe you are looking down at an angle.
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
// It is meant to be read. Black type on white with a hairline at each ring, no colour and no
// effects, is the default; Hectic is how much of the chromatic split, the trails and the bloom
// the A Hit driver brings in, so it goes wild on the drop and behaves itself the rest of the
// time. The words come from the Visuals page -- type them in, separate them with | -- and arrive
// as an eight-row texture read through word() (see COMMON).
//
// Being readable is a property of the ranges, not of the defaults, so the ranges in the json are
// set where the words survive rather than where the maths stops: travel tops out at a ring a bar
// and spin at a turn every two bars, the smearing effects stop at a smear, and Two tone and
// Mirror are marked fixed because one decides card against ink and the other decides whether half
// the words read backwards -- neither is an energy, and rolling them is how a randomise produced
// an unreadable picture. Two guards live here rather than in the json because they are about how
// parameters combine: the word count is capped against Mirror (below), and the hit's shove is
// normalised against the magnitude of the travel rate (in content()).
//
// The other thing worth knowing before changing anything here is that atan() has a branch cut at
// +/-pi, and every straight-line artefact this sketch has ever had came out of it. Anything added
// to the ring coordinate that is not periodic over a full turn leaves a visible slice there. That
// is why Twist counts whole rings per turn and why the word, its offset and its colour are taken
// mod the thread count: see the notes in pipe().
//
// Drivers (docs/reactive.md): A Hit -> a shove down the pipe and everything hectic; B Move ->
// the spin and the vanishing point wandering; C Change -> the next word and the palette.
// Params are p_* uniforms; ranges and defaults are in wormhole.json.
uniform float p_rings, p_reps, p_height, p_zoom, p_spin, p_twist, p_counter, p_mirror,
              p_off, p_offspin,
              p_seam, p_weight, p_edge, p_glow, p_trail, p_chroma, p_hectic,
              p_mono, p_bg, p_fog, p_vign,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_palette, p_spread, p_sat, p_follow;

#define TAU 6.2831853

// The Mobius transform (z - a) / (1 - conj(a) z), which is what tips the tunnel off its axis.
// It sends the point a to the origin, so a is literally where the vanishing point lands. jac is
// how much one screen pixel is worth in the mapped plane, which the hairlines need to stay one
// pixel wide however much the map has stretched things there.
vec2 mobius(vec2 z, vec2 a, out float jac) {
  vec2 num = z - a;
  vec2 den = vec2(1.0 - (a.x * z.x + a.y * z.y), a.y * z.x - a.x * z.y);
  float dd = max(dot(den, den), 1e-6);
  jac = (1.0 - dot(a, a)) / dd;
  return vec2(num.x * den.x + num.y * den.y, num.y * den.x - num.x * den.y) / dd;
}

// One sample of the pipe. `off` shifts the lookup round the ring, which is all the chromatic
// split and the outline need. Gives back the letter coverage, the thread index (the ring number
// taken mod the thread count, so it is safe to colour by), and how near this point is to a ring's
// seam, in pixels, so the hairline can be drawn at one width anywhere.
vec4 pipe(vec2 p, vec2 a, float t, float off, float turn, float wordShift, float counter) {
  float jac;
  vec2 z = mobius(p, a, jac);
  float r = max(length(z), 1e-5);
  float ang = atan(z.y, z.x) + turn;

  // Mirroring folds the angle into a wedge, and a wedge is only TAU/(2m) wide. The word lookup
  // has to be stretched back over a whole turn or it would only ever sample the first 1/(2m) of
  // the word -- a quarter of it at Mirror 2 -- which reads as the letterforms falling apart
  // rather than as a kaleidoscope. The twist keeps the folded angle, so the rings kink at the
  // wedge edges, which is the part you do want.
  float au = ang;
  float m = floor(p_mirror + 0.5);
  if (m > 1.5) {
    float seg = TAU / m;
    ang = abs(mod(ang + seg * 0.5, seg) - seg * 0.5);
    au = ang * 2.0 * m;
  }

  // Twist is a whole number of rings gained per turn, and it has to be whole. atan() has a branch
  // cut at +/-pi, so going once round, ang jumps by TAU and lr jumps by TAU * twist. Any fraction
  // of a ring in that jump shows up as a straight line out of the vanishing point where the bands
  // step radially and the letters are cut in half. A whole number closes the helix up: lr jumps by
  // an integer, so the fractional part -- which is what the band and the type are drawn from -- is
  // continuous straight through it.
  float tw = floor(p_twist + 0.5);
  float lr = log(r) * p_rings - t * p_zoom + tw * (ang / TAU);
  float ring = floor(lr);
  float v = fract(lr);

  // Closing the band up is only half of it. Crossing the cut moves you exactly |tw| rings along
  // the thread, so anything that varies from ring to ring -- the word, its offset, its colour --
  // jumps there unless it repeats with that period. Taking it mod the thread count is what makes
  // it repeat, and it is also just what a helix is: one thread is a single endless ring, three
  // threads cycle three. With no twist there is no angular term and no cut, so the ring stands.
  float key = tw != 0.0 ? mod(ring, abs(tw)) : ring;

  // Each ring sits round from the last so the words never line up into columns; alternate rings
  // creep the other way. The creep goes into the offset, not the coordinate: negating the
  // coordinate turns a ring round but mirrors every letter on it, which reads as a mistake.
  float dir = mod(key, 2.0) < 0.5 ? 1.0 : -1.0;
  // At most four words round the whole circle, however the wedges happen to divide it. Mirroring
  // multiplies the count by m, so reps 4 at Mirror 4 put sixteen words on a ring and the type
  // rendered as tick marks. Floored because a fractional count leaves a part-word at the seam.
  float repsEff = max(1.0, floor(min(p_reps, 4.0 / m)));
  float u = fract(au / TAU * repsEff + key * 0.37 + off + dir * counter);

  float h = clamp(p_height, 0.05, 1.0);
  float cov = word(vec2(u, (v - 0.5) / h + 0.5), key + wordShift);

  // One screen pixel is u_px; through the map that is u_px * jac, and in log-radius units that is
  // |grad lr| of it again. Twisting adds an angular term to lr, so the gradient is no longer just
  // the radial rings/r -- without the extra term the hairline thickens as the helix steepens.
  float grad = sqrt(p_rings * p_rings + (tw / TAU) * (tw / TAU));
  float lrPx = max(grad * u_px * jac / r, 1e-6);
  float seam = min(v, 1.0 - v) / lrPx;
  // key, not ring: content() colours by this, and ring jumps where the helix closes.
  return vec4(cov, key, seam, 0.0);
}

vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> a shove, and everything hectic
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> spin, and the axis wandering
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> the next word, the palette

  float bb = barBeat(), t = u_beat;
  float H = p_hue + (p_follow > 0.5 ? u_hue : 0.0) + 0.13 * C;
  float PAL = max(2.0, floor(p_palette + 0.5));

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;

  // Where the vanishing point sits, and the slow wander of it. Kept inside the unit disc, which
  // is where the Mobius map is well behaved.
  float oa = t * p_offspin * TAU + B * 0.8;
  vec2 axis = vec2(cos(oa), sin(oa)) * clamp(p_off, 0.0, 0.85);

  float turn = t * p_spin * TAU;
  // The hit shoves it down the pipe. Dividing by the travel rate and then multiplying by it
  // again in lr() normalises the shove to a fixed fraction of a ring however fast we are going,
  // which is the point -- but it has to be the magnitude. Clamping the signed rate floors at
  // 0.02 while lr still multiplies by the real negative rate, so running the tunnel backwards
  // turned a kick into a five-ring jump.
  float tt = t + A * 0.42 / max(abs(p_zoom), 0.02);
  float wordShift = floor(bb / 4.0) + floor(C * 4.0);
  float counter = t * p_counter;

  // Everything hectic arrives on the hit rather than sitting there all night.
  float hx = p_hectic * A;
  float chroma = min(1.0, p_chroma + hx * 0.85);
  float trail = min(1.5, p_trail + hx * 1.1);
  float glow = min(1.5, p_glow + hx * 1.0);

  vec4 s0 = pipe(p, axis, tt, 0.0, turn, wordShift, counter);
  // .y is the thread index, already taken mod the thread count so it does not jump at the wrap.
  float cov = s0.x, thread = s0.y, seam = s0.z;

  // Two tone by default: black type on white, with a hairline at every ring. Colour is the thing
  // you turn on, not the thing you turn off.
  vec3 paper = mix(hsv(fract(H + 0.5), 0.75 * p_sat, p_bg), vec3(0.94, 0.93, 0.91), p_mono);
  vec3 ink = mix(hsv(fract(H + p_spread * (mod(thread, PAL) / PAL - 0.5) * 2.0), 0.92 * p_sat, 1.0),
                 vec3(0.05, 0.05, 0.06), p_mono);
  vec3 col = paper;

  // The hairline between rings, one pixel wide wherever it lands.
  if (p_seam > 0.004) {
    float w = p_seam;
    col = mix(col, ink, (1.0 - smoothstep(w, w + 1.2, seam)) * 0.85);
  }

  // The letters, with a chromatic split when it is called for. A split is two more lookups at a
  // slightly different angle, which is cheap here because a lookup is a fetch and not a march.
  if (chroma > 0.004) {
    float o = chroma * 0.018;
    float cr = pipe(p, axis, tt, -o, turn, wordShift, counter).x;
    float cb = pipe(p, axis, tt, o, turn, wordShift, counter).x;
    col = mix(col, mix(ink, vec3(0.95, 0.15, 0.20), p_mono * 0.8 + 0.2), cr * 0.6);
    col = mix(col, mix(ink, vec3(0.15, 0.35, 0.95), p_mono * 0.8 + 0.2), cb * 0.6);
    col = mix(col, ink, cov);
    cov = max(cov, max(cr, cb) * 0.7);
  } else {
    col = mix(col, ink, cov);
  }

  // An outline just outside the letters, and a bloom outside that. Both off the same coverage
  // sampled a hair wider, so they follow the type without a second pass over it.
  if (p_edge > 0.004 || glow > 0.004) {
    float w = 0.010 * (1.0 + p_weight);
    float near = max(pipe(p, axis, tt, w, turn, wordShift, counter).x,
                     pipe(p, axis, tt, -w, turn, wordShift, counter).x);
    float halo = clamp(near - cov, 0.0, 1.0);
    col = mix(col, ink, halo * p_edge * 0.6);
    col += hsv(fract(H + 0.08), 0.8 * p_sat, 1.0) * halo * glow * (1.0 - p_mono * 0.6);
  }

  // Trails: the same pipe a little further back, faint, which reads as motion down the hole
  // without keeping a single frame of history.
  if (trail > 0.004) {
    for (int i = 1; i <= 3; i++) {
      float fi = float(i);
      float back = pipe(p, axis, tt - fi * 0.10, 0.0, turn - fi * 0.015, wordShift, counter).x;
      vec3 tc = mix(hsv(fract(H + 0.05 * fi), 0.85 * p_sat, 1.0), ink, p_mono);
      col = mix(col, tc, back * trail * (0.20 / fi));
    }
  }

  // Down at the vanishing point the rings go finer than a pixel, so they have to be taken out
  // before they turn into noise. Then a vignette.
  float jac;
  float rr = length(mobius(p, axis, jac));
  col = mix(col, paper, 1.0 - smoothstep(0.0, 0.07 / max(p_fog, 0.05), rr));
  col *= 1.0 - p_vign * pow(clamp(length(p * vec2(0.85, 1.25)), 0.0, 1.0), 2.5);
  return col;
}
