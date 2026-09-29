// Hypnotoad: ALL GLORY TO THE HYPNOTOAD. Drawn front-on and symmetrical, which is both how the
// thing is usually seen and the most hypnotic way to put anything on a wall.
//
// The toad keeps its own colours whatever the show's hue is doing, because a Hypnotoad that is
// not olive-and-cream with yellow eyes is not Hypnotoad. Tint lets you overrule that. Everything
// behind it -- the wavy hypno rings and the sacred geometry over them -- takes the hue instead,
// on a small quantised palette like the rest of the house.
//
// The eyes are the whole point: an olive dome, concentric rings running outward from the middle,
// and a red-rimmed black splat of a pupil that wobbles. The rings run on their own speed in
// cycles per beat, so the stare is on the music.
//
// Drivers (docs/reactive.md): A Hit -> the bob, the squash on the landing and the eyes flaring;
// B Move -> the geometry turning and the rings running; C Change -> the palette and how much
// sacred line-work is on top.
// Params are p_* uniforms; ranges and defaults are in hypnotoad.json.
uniform float p_size, p_bob, p_blink, p_patches, p_tint, p_collar, p_ink, p_halo,
              p_eyesize, p_pupil, p_rings, p_ringspin,
              p_mode, p_scale, p_detail, p_width, p_spin,
              p_bands, p_wave, p_bandspin, p_glow,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_palette, p_sat, p_follow;

#define TAU 6.2831853
#define PI  3.14159265

// Painted shape over shape, same as sisyphus and inkwell: a fill and the ink laid over it.
// gS carries a distance in the toad's own units out to surface units, so the line stays one
// width whatever size he is drawn at.
vec3 gCol;
float gInk, gPx, gLw, gS;

const vec3 INK   = vec3(0.16, 0.11, 0.03);   // the cartoon's near-black brown line
const vec3 HIDE  = vec3(0.52, 0.41, 0.13);   // his olive khaki
const vec3 HIDE2 = vec3(0.60, 0.48, 0.17);   // the lighter olive across the top of him
const vec3 DARK  = vec3(0.34, 0.26, 0.08);   // the blotches over his back
const vec3 DARK2 = vec3(0.25, 0.19, 0.05);   // deepest: the far haunch
const vec3 CREAM = vec3(0.79, 0.77, 0.60);   // throat and belly
const vec3 CREAM2 = vec3(0.70, 0.67, 0.50);  // under the belly
const vec3 SCLER = vec3(0.91, 0.83, 0.23);   // the eye yellow
const vec3 RIM   = vec3(0.85, 0.12, 0.06);   // the red round the pupil
const vec3 PUP   = vec3(0.05, 0.04, 0.03);
const vec3 COLL  = vec3(0.42, 0.29, 0.35);   // the mauve collar
const vec3 MINT  = vec3(0.66, 0.87, 0.82);   // its buckle and the tag

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
float sdEll(vec2 p, vec2 r) { return (length(p / r) - 1.0) * min(r.x, r.y); }

// A circle pulled out of shape by a couple of lobes: the pupils and the patches on his back are
// both this, because nothing about him is drawn with a compass.
float blob(vec2 p, float r, float wob, float ph) {
  float a = atan(p.y, p.x);
  return length(p) - r * (1.0 + wob * (0.34 * sin(a * 3.0 + ph) + 0.22 * sin(a * 2.0 - ph * 0.7)));
}

// Flat vector by default: the form comes from where one colour stops and the next starts, and
// there is no outline at all. Ink above zero puts a pen back on him for a cartoon look.
// The little "c" ticks the cartoon scatters over his back and haunches. A thin arc, cut in
// half, rotated: fiddly to describe and the single thing that most says "drawn by hand".
float wart(vec2 p, vec2 at, float r, float a) {
  vec2 d = rot(a) * (p - at);
  return max(abs(length(d) - r) - 0.005, -d.x);
}

void draw(float d, vec3 c) {
  float f = 1.0 - smoothstep(-gPx, gPx, d);
  gCol = mix(gCol, c, f);
  if (gLw > 0.0) {
    float e = 1.0 - smoothstep(gLw - gPx, gLw + gPx, abs(d));
    gInk = max(gInk * (1.0 - f), e);
  } else {
    gInk *= 1.0 - f;
  }
}
// Rounded union, so the head, body and haunches read as one animal rather than as three shapes
// stacked up. Without an outline to hide the joins this is what does the work.
float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}
void D(float d, vec3 c) { draw(d * gS, c); }
// A fill with no outline, for shading inside a shape that is already outlined.
void shade(float d, vec3 c, float amt) {
  gCol = mix(gCol, c, (1.0 - smoothstep(-gPx, gPx, d * gS)) * amt);
}

// ---------------------------------------------------------------- the eyes
// Yellow dome, and a wide flat black splat of a pupil with a thin red rim round it. That splat
// is the single most recognisable thing about him, so it is drawn squashed and lobed rather
// than round. The hypnotic rings live inside the yellow and are kept faint at rest -- the still
// has none -- and come up with the hit, so he looks like himself until the kick lands.
void eye(vec2 q, vec2 at, float R, float t, float A, float flare) {
  const float SQ = 0.84;                                  // how much flatter than round he is
  vec2 e = (q - at) / vec2(1.0, SQ);
  float r = length(e);
  D((r - R) * SQ, SCLER);
  if (r < R) {
    float n = max(1.0, floor(p_rings + 0.5));
    float ph = r / R * n - t * p_ringspin;
    float aa = min(0.9, 3.0 * n / max(R, 0.02) * u_px / max(gS, 1e-5));
    float band = smoothstep(-aa, aa, cos(TAU * ph));
    float inside = 1.0 - smoothstep(-gPx, gPx, (r - R) * SQ * gS);
    gCol = mix(gCol, SCLER * 0.78, band * (0.07 + 0.34 * flare) * inside);
    gCol = mix(gCol, vec3(1.0, 0.97, 0.62), (1.0 - band) * 0.16 * flare * inside);
  }
  // The splat: much wider than it is tall, with a couple of lobes so it never reads as an oval.
  vec2 pe = e * vec2(1.0, 1.55);
  float pr = R * p_pupil * (1.0 + 0.12 * A);
  float wob = 0.30 + 0.10 * sin(t * 0.7);
  float lw0 = gLw; gLw *= 0.5;
  D(blob(pe, pr * 1.16, wob, t * 0.35) * SQ, RIM);         // the red is a rim, not a ring
  D(blob(pe, pr, wob, t * 0.35) * SQ, PUP);
  gLw = lw0;
  shade((length(e - vec2(-R * 0.36, R * 0.46)) - R * 0.15) * SQ, vec3(1.0), 0.20);
}

// ---------------------------------------------------------------- him
void toad(vec2 q, float t, float A, float flare) {
  float ey = 1.0 - p_blink * step(0.90, hash(vec2(floor(t * 0.7), 3.0))) * exp(-22.0 * fract(t * 0.7));
  float R = 0.148 * p_eyesize;
  vec2 L = vec2(-0.190, 0.290), Rr = vec2(0.190, 0.290);

  // Long thin toes, splayed wide and forward: the still has spidery feet, not fat ones.
  for (int s2 = 0; s2 < 2; s2++) {
    float sg = float(s2) * 2.0 - 1.0;
    vec2 an = vec2(sg * 0.285, -0.350);
    for (int i = 0; i < 4; i++) {
      float a = mix(-0.10, 1.25, float(i) / 3.0);
      vec2 tip = an + vec2(sg * sin(a) * 1.12, -cos(a) * 0.92 - 0.05) * 0.215;
      D(sdSeg(q, an, tip) - 0.027, HIDE);
    }
    D(sdEll(q - an, vec2(0.095, 0.068)), HIDE);
  }

  // One squat mass: the haunches, the body, the head and the eyes all blended, so the line
  // runs right round the lot of him and he reads as one animal.
  float haunch = smin(sdEll(q - vec2(-0.385, -0.215), vec2(0.130, 0.160)),
                      sdEll(q - vec2( 0.385, -0.215), vec2(0.130, 0.160)), 0.04);
  float body = smin(sdEll(q - vec2(0.0, -0.150), vec2(0.405, 0.265)),
                    sdEll(q - vec2(0.0, 0.105), vec2(0.280, 0.205)), 0.15);
  body = smin(body, haunch, 0.10);
  body = smin(body, (length((q - L) / vec2(1.0, 0.84)) - R * 1.02) * 0.84, 0.09);
  body = smin(body, (length((q - Rr) / vec2(1.0, 0.84)) - R * 1.02) * 0.84, 0.09);
  D(body, HIDE);
  shade(sdEll(q - vec2(0.0, 0.180), vec2(0.265, 0.190)), HIDE2, 0.85);  // lighter over the top
  shade(haunch, DARK, 0.38);                                            // a hint of shadow on them

  // Blotches over his back and shoulders, with the little "c" ticks on them.
  if (p_patches > 0.01) {
    float k = p_patches;
    D(blob(q - vec2(-0.275, 0.055), 0.085 * k, 0.45, 1.1), DARK);
    D(blob(q - vec2( 0.300, 0.010), 0.075 * k, 0.45, 2.3), DARK);
    D(blob(q - vec2(-0.150, 0.255), 0.055 * k, 0.45, 0.4), DARK);
    D(blob(q - vec2( 0.115, 0.285), 0.045 * k, 0.45, 3.1), DARK);
    D(blob(q - vec2(-0.330, -0.155), 0.060 * k, 0.45, 1.9), DARK);
    D(blob(q - vec2( 0.345, -0.185), 0.055 * k, 0.45, 0.8), DARK);
    gLw *= 0.55;                                    // the ticks are drawn with a finer nib
    D(wart(q, vec2(-0.290, 0.030), 0.019, 0.6), DARK2);
    D(wart(q, vec2( 0.310, -0.020), 0.017, 2.4), DARK2);
    D(wart(q, vec2(-0.375, -0.245), 0.016, 1.4), DARK2);
    D(wart(q, vec2( 0.390, -0.210), 0.016, 3.6), DARK2);
    D(wart(q, vec2(-0.180, 0.235), 0.014, 0.2), DARK2);
    D(wart(q, vec2( 0.150, 0.270), 0.014, 2.9), DARK2);
    gLw /= 0.55;
  }

  // Throat and belly: pale khaki, its top edge running right across him as the mouth.
  float mouth = q.y - (0.020 - 0.070 * pow(clamp(abs(q.x) / 0.33, 0.0, 1.0), 2.0));
  float belly = max(sdEll(q - vec2(0.0, -0.185), vec2(0.305, 0.235)), mouth);
  D(belly, CREAM);
  gCol = mix(gCol, CREAM2, (1.0 - smoothstep(-gPx, gPx, belly * gS))
             * smoothstep(-0.20, -0.36, q.y) * 0.55);     // soft shading low in the belly

  // The collar: a mauve strap round the neck with the buckle off centre and the tag hanging.
  if (p_collar > 0.01) {
    float cw = 0.020 * p_collar;
    float cy = q.y + 0.055 - 0.085 * pow(clamp(abs(q.x) / 0.33, 0.0, 1.0), 2.0);
    D(max(abs(cy) - cw, body + 0.012), COLL);
    gLw *= 0.6;
    for (int i = 0; i < 5; i++) {                        // the stitch holes along the strap
      float sx = -0.255 + float(i) * 0.055;
      float sy = -0.055 + 0.085 * pow(clamp(abs(sx) / 0.33, 0.0, 1.0), 2.0);
      D(length(q - vec2(sx, sy)) - 0.0055, INK);
    }
    gLw /= 0.6;
    D(sdEll(q - vec2(0.055, -0.060), vec2(0.030, 0.024)), MINT);   // buckle
    D(sdSeg(q, vec2(0.0, -0.075), vec2(0.0, -0.120)) - 0.008, MINT);
    D(sdEll(q - vec2(0.0, -0.160), vec2(0.040, 0.044)), MINT);     // tag
  }

  // Nostrils, and the two little brow curls the cartoon puts on the top of his head.
  D(sdEll(q - vec2(-0.048, 0.145), vec2(0.012, 0.016)), INK);
  D(sdEll(q - vec2( 0.048, 0.145), vec2(0.012, 0.016)), INK);
  gLw *= 0.6;
  D(wart(q, vec2(-0.082, 0.380), 0.028, -0.5), INK);
  D(wart(q, vec2( 0.082, 0.380), 0.028, 3.6), INK);
  gLw /= 0.6;

  // And the eyes, on top.
  if (ey > 0.15) {
    eye(q, L, R, t, A, flare);
    eye(q, Rr, R, t, A, flare);
  } else {
    D(sdEll(q - L, vec2(R, R * 0.11)), HIDE);
    D(sdEll(q - Rr, vec2(R, R * 0.11)), HIDE);
  }
}

// ---------------------------------------------------------------- the picture
vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> the bob and the flare
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> the geometry and the rings
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> palette and line-work

  float bb = barBeat(), t = u_beat;
  float H = p_hue + (p_follow > 0.5 ? u_hue : 0.0) + 0.11 * C;
  float PAL = max(2.0, floor(p_palette + 0.5));

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;

  gPx = u_px * 0.8;
  gLw = p_ink > 0.004 ? max(p_ink * 0.0042, u_px * 1.1) : 0.0;
  gInk = 0.0;

  // ---- the hypno rings behind him: wavy concentric bands on a small quantised palette, so it
  // reads as drawn rather than as a rainbow gradient. The wobble is what makes them crawl.
  float r = length(p), a = atan(p.y, p.x);
  float wob = p_wave * (0.09 * sin(a * 7.0 + t * 0.35) + 0.05 * sin(a * 11.0 - t * 0.2));
  float ph = r * max(1.0, p_bands) - t * p_bandspin + wob * max(1.0, p_bands);
  float bandI = floor(ph);
  float idx = mod(bandI, PAL);
  vec3 bg = hsv(fract(H + (idx / PAL) * 0.18), 0.92 * p_sat, mix(0.28, 1.0, mod(bandI, 2.0)));
  gCol = bg * (0.55 + 0.45 * p_glow);
  // A glow coming off him, so he sits in the middle of it rather than on top of it.
  gCol += hsv(fract(H + 0.06), 0.8 * p_sat, 1.0) * exp(-r * 3.2) * 0.30 * (0.4 + 0.9 * A) * p_glow;

  // ---- sacred geometry over the bands, in a thin bright line
  float gd = 1e9;
  float S = max(0.04, p_scale);
  float N = max(1.0, floor(p_detail + 0.5));
  vec2 gp = rot(t * p_spin * TAU + B * 0.6) * p;
  if (p_mode < 0.5) {
    // Flower of Life: circles of radius S on a hex lattice of the same spacing.
    float jj = gp.y / (S * 0.866025), ii = gp.x / S - 0.5 * jj;
    vec2 base = floor(vec2(ii, jj));
    for (int i = -2; i <= 2; i++) for (int j = -2; j <= 2; j++) {
      vec2 ij = base + vec2(float(i), float(j));
      vec2 c = vec2((ij.x + 0.5 * ij.y) * S, ij.y * 0.866025 * S);
      if (length(c) / S > N - 0.5) continue;
      gd = min(gd, abs(length(gp - c) - S));
    }
    gd = min(gd, abs(length(gp) - (N + 0.5) * S));
  } else if (p_mode < 1.5) {
    // Metatron's Cube: thirteen circles and the lines between their centres.
    float rr = S * 0.62;
    for (int i = 0; i < 13; i++) {
      float fi = float(i);
      float ai = mod(fi - 1.0, 6.0) * PI / 3.0 + PI / 6.0;
      vec2 ci = fi < 0.5 ? vec2(0.0) : vec2(cos(ai), sin(ai)) * rr * (fi < 6.5 ? 2.0 : 4.0);
      gd = min(gd, abs(length(gp - ci) - rr));
      for (int j = 0; j < 13; j++) {
        if (j <= i) continue;
        float fj = float(j);
        float aj = mod(fj - 1.0, 6.0) * PI / 3.0 + PI / 6.0;
        vec2 cj = vec2(cos(aj), sin(aj)) * rr * (fj < 6.5 ? 2.0 : 4.0);
        gd = min(gd, sdSeg(gp, ci, cj));
      }
    }
  } else {
    // A mandala: concentric rings crossed by spokes, which is the plainest sacred thing there is
    // and the one that sits behind him without arguing.
    float ga = atan(gp.y, gp.x), gr = length(gp);
    gd = min(abs(fract(gr / S) - 0.5) * S * 2.0,
             abs(fract(ga * N / TAU + 0.5) - 0.5) * TAU / N * max(gr, 0.02));
    gd = min(gd, abs(gr - S * (N + 0.5)));
  }
  float lw = p_width * (0.0016 + 0.9 * u_px);
  float line = 1.0 - smoothstep(lw, lw + 1.4 * u_px, gd);
  gCol = mix(gCol, hsv(fract(H + 0.10), 0.30 * p_sat, 1.0), line * (0.30 + 0.50 * C));

  // ---- him, bobbing
  float lag = 0.0;
  float wobl = sin(TAU * (bb / max(loopBeats(p_aloop), 0.5) - lag));
  float up = max(0.0, wobl), down = max(0.0, -wobl);
  float hop = p_bob * (0.035 + 0.11 * A) * up;
  float squash = 1.0 + p_bob * (0.05 + 0.20 * A) * down;

  // His art runs from about -0.50 (toes) to +0.46 (top of the eyes), so he sits very slightly
  // below centre and gets three quarters of the height -- enough to leave the geometry visible
  // round him rather than filling the frame with toad.
  float Sz = p_size * 0.66;
  gS = max(Sz, 1e-4);
  vec2 c = (p - vec2(0.0, 0.01 + hop * Sz)) / Sz;
  // Squash on the landing, pivoting on his feet; he is a toad, he does not stretch upward.
  c.x /= squash;
  c.y = (c.y + 0.5) * squash - 0.5;
  c = rot(p_bob * 0.055 * sin(TAU * (bb / max(loopBeats(p_aloop), 0.5) * 0.5))) * (c + vec2(0.0, 0.5)) - vec2(0.0, 0.5);

  // He has to read against whatever the rings are doing behind him, and his brown is not far
  // off their orange. A soft shadow roughly his shape, darkening the card, separates him
  // without putting a keyline round every part of him -- which the flat artwork does not have.
  if (p_halo > 0.004) {
    float hs = sdEll(p - vec2(0.0, 0.01 + hop * Sz - 0.05 * Sz), vec2(0.60 * Sz, 0.54 * Sz));
    gCol *= mix(1.0, 0.40, p_halo * (1.0 - smoothstep(-0.10 * Sz, 0.30 * Sz, hs)));
  }

  toad(c, t, A, 0.35 + 0.9 * A);

  vec3 col = mix(gCol, INK, clamp(gInk, 0.0, 1.0));
  // Tint pulls the whole thing, him included, towards the show's hue. Zero leaves him alone.
  if (p_tint > 0.004) {
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, hsv(fract(H + 0.02), 0.75 * p_sat, 1.0) * (0.25 + 1.35 * l), p_tint);
  }
  col *= 1.0 - 0.26 * pow(clamp(length(p * vec2(0.85, 1.25)), 0.0, 1.0), 3.0);
  return col;
}
