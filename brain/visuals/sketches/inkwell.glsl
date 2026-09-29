// Inkwell: rubber hose cartoons, after Fleischer's Out of the Inkwell, arranged down a tunnel.
//
// The pen is thin and hard. Bold here comes from contrast -- near-black ink against fills at
// full saturation on a dark card -- and not from thickness, so the line is held just above one
// pixel and the edge is feathered by about a pixel and no more. A fat soft line at this scale
// turns to mush the moment anything moves.
//
// Arms, stems, spouts and handles are hoses: one thickness, round ends, bending in a curve
// rather than hinging at a joint. That is where the style gets its name.
//
// The shapes are used as masks. Each one is filled with a little log-polar tunnel of its own,
// drawn in the subject's local coordinates so the pattern travels, turns and squashes with the
// shape instead of sliding about underneath it. With the faces off -- which is the default --
// the interiors are what carry the picture.
//
// The layout is the same trick one level up: log-polar repetition, log(r) against the angle,
// so the cast recedes into the middle forever. Both spin and zoom are one term each on those
// two axes, and both are in cycles per beat like every other speed in the repo. The row layout
// is still there for a wide surface that wants a chorus line rather than a tunnel.
//
// Sixteen of them, and they dance: a hop, a squash on the landing, a rock from the feet and a
// shimmy across, each cell a step behind the one before it so the row ripples rather than
// pumping as one. The rock and the shimmy run at different fractions of the loop on purpose.
//
// Drivers (docs/reactive.md): A Hit -> the bounce, the squash on the landing and the eye pop;
// B Move -> the noodle in the hoses and the kaleidoscope turning; C Change -> the palette, who
// the cast reaches for next, and (through Faces on C) whether they have faces at all.
// Params are p_* uniforms; ranges and defaults are in inkwell.json.
uniform float p_layout, p_cast, p_swap, p_size, p_bounce, p_dance,
              p_spin, p_zoom,
              p_ink, p_boil, p_noodle,
              p_pat, p_patmode, p_patscale, p_patspin,
              p_face, p_facec, p_faceodds,
              p_prop, p_propodds,
              p_kal, p_rosette, p_bg, p_film,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_palette, p_spread, p_sat, p_follow;

#define TAU 6.2831853

// The picture is painted shape over shape into these: a fill colour and the ink laid over it.
// gS carries a distance in the cast's own units out to surface units, so one pen width stays
// one pen width whether a subject fills the screen or is six rings down the tunnel.
vec3 gCol, gC1, gC2, gC3;
float gInk, gPx, gLw, gS, gNoodle, gPat, gFill, gEye, gMouth, gProp, gTurn, gCell;

const vec3 INK = vec3(0.045, 0.035, 0.050);
const vec3 WHITE = vec3(0.98, 0.97, 0.91);

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

// Turn a colour's hue without touching how saturated or how bright it is: a rotation about the
// grey axis. Mixing towards a tint instead, which is the obvious way, washes the colour out --
// which is the one thing this sketch cannot afford.
vec3 hueRot(vec3 c, float turns) {
  vec3 k = vec3(0.57735027);
  float ca = cos(turns * TAU), sa = sin(turns * TAU);
  return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

// A hose: a bent tube of one thickness with round ends. The curve is walked in a few straight
// pieces, which is close enough at this line weight and much cheaper than solving the cubic.
float hose(vec2 p, vec2 a, vec2 b, vec2 c, float r) {
  float d = 1e9;
  vec2 pr = a;
  for (int i = 1; i <= 6; i++) {
    float t = float(i) / 6.0;
    vec2 q = mix(mix(a, b, t), mix(b, c, t), t);
    d = min(d, sdSeg(p, pr, q));
    pr = q;
  }
  return d - r;
}

// Paint a shape: fill it, hide what was behind it, lay the outline on top.
void draw(float d, vec3 c) {
  float f = 1.0 - smoothstep(-gPx, gPx, d);
  float e = 1.0 - smoothstep(gLw - gPx, gLw + gPx, abs(d));
  gCol = mix(gCol, c, f);
  gInk = max(gInk * (1.0 - f), e);
}
// The same, for shapes given in the cast's units.
void D(float d, vec3 c) { draw(d * gS, c); }

// A fill, banded by whatever the interior pattern is doing at this pixel. gPat is worked out
// once per pixel before the subject is drawn, so this costs a multiply per shape.
vec3 sk(vec3 base) {
  return gFill < 0.004 ? base : mix(base, base * (0.30 + 0.95 * gPat), gFill);
}

// The rubber hose eye: a big white oval, a black pupil that looks where it is told, and the
// bright dot the animators put in so the pupil reads as an eye and not as a hole.
void eye(vec2 q, vec2 at, float r, vec2 look, float open, float pop) {
  if (gEye < 0.05) return;                 // this one is not in the eyes half of the cast
  vec2 e = q - at;
  float rr = r * mix(0.55, 1.0, gEye) * (1.0 + 0.35 * pop);
  D(sdEll(e, vec2(rr * 0.84, rr * mix(0.12, 1.15, open))), WHITE);
  vec2 pu = e - look * rr * 0.34;
  D(length(pu) - rr * 0.40 * open, INK);
  D(length(pu - vec2(rr * 0.17, rr * 0.18)) - rr * 0.17 * open, WHITE);
}

// A wide grin: inside an ellipse and under an arc, with a tongue in the bottom of it.
void grin(vec2 q, vec2 at, float w, float h, float curve) {
  if (gMouth < 0.05) return;               // fewer mouths than eyes, on purpose
  float ms = mix(0.50, 1.0, gMouth);
  w *= ms; h *= ms;
  vec2 m = q - at;
  float tx = clamp(m.x / w, -1.0, 1.0);
  float d = max(sdEll(m, vec2(w, h)), m.y - (-curve * h * (1.0 - tx * tx)));
  D(d, vec3(0.08, 0.025, 0.045));        // near-black: a dark red mouth is lost on a banded fill
  D(max(d + 0.012, sdEll(m - vec2(0.0, -h * 0.45), vec2(w * 0.52, h * 0.40))), vec3(0.92, 0.22, 0.34));
}

// ---------------------------------------------------------------- the cast
// Every subject is drawn inside roughly -0.5..0.5, standing on y = -0.5. The faces are on a
// slider and off by default: below a trace of Faces the eye and grin calls are skipped
// outright, so they cost nothing and leave no stray ink behind.
void subject(vec2 q, float which, float A, float pop) {
  // They look where they are turning, which is most of what sells the turn.
  vec2 look = vec2(clamp(gTurn * 1.5, -1.0, 1.0) * 0.6 + 0.20 * sin(u_beat * 0.23),
                   0.25 * sin(u_beat * 0.17));
  float n = gNoodle;
  float hasFace = step(0.05, max(gEye, gMouth));
  // A blink now and then, and it has to be quick: a slow one reads as falling asleep.
  float ey = 1.0 - 0.95 * step(0.86, hash(vec2(floor(u_beat * 0.8), 3.0)))
                        * exp(-26.0 * fract(u_beat * 0.8));
  vec3 c1 = sk(gC1), c2 = sk(gC2), c3 = sk(gC3);

  if (which < 0.5) {
    // 0 -- a cartoon face: jug ears, a bulb nose, and a grin that does not fit on it.
    D(length(q - vec2(-0.43, 0.02)) - 0.12, c2);
    D(length(q - vec2( 0.43, 0.02)) - 0.12, c2);
    D(sdEll(q - vec2(0.0, 0.02), vec2(0.40, 0.44)), c1);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.155, 0.16), 0.128, look, ey, pop);
      eye(q, vec2( 0.155, 0.16), 0.128, look, ey, pop);
      grin(q, vec2(0.0, -0.20), 0.26, 0.15, 0.55);
    }
    D(length(q - vec2(0.0, -0.02)) - 0.085, c3);
    D(hose(q, vec2(-0.18, 0.44), vec2(0.0, 0.56 + n), vec2(0.16, 0.42), 0.022), c3);

  } else if (which < 1.5) {
    // 1 -- a bird. Hose legs, and the wing flaps on the hit.
    D(hose(q, vec2(-0.09, -0.16), vec2(-0.13 + n, -0.34), vec2(-0.16, -0.47), 0.022), c3);
    D(hose(q, vec2( 0.07, -0.16), vec2( 0.11 - n, -0.34), vec2( 0.14, -0.47), 0.022), c3);
    D(sdEll(q - vec2(-0.16, -0.48), vec2(0.09, 0.030)), c3);
    D(sdEll(q - vec2( 0.14, -0.48), vec2(0.09, 0.030)), c3);
    D(sdEll(rot(-0.5) * (q - vec2(-0.30, -0.02)), vec2(0.17, 0.08)), c2);    // tail
    D(sdEll(q - vec2(0.0, -0.06), vec2(0.26, 0.23)), c1);
    D(sdEll(rot(0.5 + 0.7 * A) * (q - vec2(0.04, -0.02)), vec2(0.17, 0.09)), c2);
    D(sdEll(q - vec2(0.05, 0.26), vec2(0.19, 0.18)), c1);
    // Beak: a wedge, closed off at the head end. Two half-planes alone leave it open to the
    // left and it swallows the frame; the divisor keeps the outline the same width as the rest.
    vec2 bk = q - vec2(0.16, 0.26);
    D(max((abs(bk.y) * 2.2 + bk.x * 0.55 - 0.14) / 2.27, -bk.x), c3);
    if (hasFace > 0.5) eye(q, vec2(0.08, 0.31), 0.100, look, ey, pop);

  } else if (which < 2.5) {
    // 2 -- a tree. The canopy is five circles of one colour laid over each other: each fill
    // wipes the outline of the one before, so all that survives is the scalloped edge round
    // the outside, which is how foliage was drawn.
    D(hose(q, vec2(0.0, -0.50), vec2(-0.06 + n * 0.5, -0.22), vec2(0.03, 0.02), 0.095), c3);
    D(hose(q, vec2(-0.01, -0.46), vec2(-0.20, -0.46), vec2(-0.28, -0.50), 0.035), c3);
    D(hose(q, vec2( 0.01, -0.46), vec2( 0.20, -0.46), vec2( 0.28, -0.50), 0.035), c3);
    D(hose(q, vec2(0.0, -0.10), vec2(-0.16, -0.02), vec2(-0.24, 0.10), 0.030), c3);
    D(hose(q, vec2(0.0, -0.06), vec2( 0.16, 0.02), vec2( 0.25, 0.12), 0.030), c3);
    D(length(q - vec2(-0.24, 0.20)) - 0.175, c1);
    D(length(q - vec2( 0.24, 0.22)) - 0.165, c1);
    D(length(q - vec2(-0.09, 0.37)) - 0.190, c1);
    D(length(q - vec2( 0.15, 0.38)) - 0.170, c1);
    D(length(q - vec2( 0.02, 0.22)) - 0.200, c1);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.098, -0.18), 0.082, look, ey, pop);
      eye(q, vec2( 0.098, -0.18), 0.082, look, ey, pop);
      grin(q, vec2(0.0, -0.33), 0.11, 0.065, 0.5);
    }

  } else if (which < 3.5) {
    // 3 -- a desk lamp. The arm is the hose the whole style is named after, and the shade has
    // to be tall and properly conical or the whole thing reads as a mushroom with a face on it.
    D(sdEll(q - vec2(0.0, -0.45), vec2(0.26, 0.055)), c2);
    D(sdEll(q - vec2(0.0, -0.40), vec2(0.14, 0.045)), c3);
    D(hose(q, vec2(0.0, -0.42), vec2(0.20 + n, -0.16), vec2(-0.01, 0.06), 0.036), c3);
    // The shade: a trapezoid, wide at the bottom. Writing it as two sloping half-planes is the
    // obvious thing and it collapses to a point wherever the slopes happen to cross.
    float ty = clamp((q.y - 0.06) / 0.36, 0.0, 1.0);
    D(max(abs(q.y - 0.24) - 0.18, abs(q.x) - mix(0.30, 0.11, ty)), c1);
    D(sdEll(q - vec2(0.0, 0.06), vec2(0.30, 0.042)), c2);                    // the rim
    D(length(q - vec2(0.0, 0.005)) - 0.075, mix(vec3(1.0, 0.95, 0.60), WHITE, 0.3 + 0.5 * A));
    if (hasFace > 0.5) {
      eye(q, vec2(-0.105, 0.23), 0.084, look, ey, pop);
      eye(q, vec2( 0.105, 0.23), 0.084, look, ey, pop);
    }

  } else if (which < 4.5) {
    // 4 -- a shopping trolley, wonky wheel and all.
    D(hose(q, vec2(-0.27, -0.18), vec2(-0.35, 0.06), vec2(-0.36, 0.26), 0.028), c3);
    D(hose(q, vec2(-0.36, 0.26), vec2(-0.31 - n, 0.37), vec2(-0.17, 0.33), 0.028), c3);
    float ty = clamp((q.y + 0.26) / 0.40, 0.0, 1.0);                         // wider at the top
    float bk = max(abs(q.y + 0.06) - 0.20, abs(q.x - 0.02) - mix(0.20, 0.30, ty));
    D(bk, c1);
    for (int i = 0; i < 2; i++) {                                            // the wire basket,
      float fx = (float(i) * 2.0 - 1.0) * 0.17;                              // clear of the face
      D(max(bk + 0.018, abs(q.x - 0.02 - fx) - 0.017), c2);
    }
    D(length(q - vec2(-0.20, -0.40)) - 0.085, c3);
    D(length(q - vec2( 0.22, -0.40)) - 0.085, c3);
    D(length(q - vec2(-0.20, -0.40)) - 0.032, c2);
    D(length(q - vec2( 0.22, -0.40)) - 0.032, c2);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.105, -0.02), 0.086, look, ey, pop);
      eye(q, vec2( 0.145, -0.02), 0.086, look, ey, pop);
      grin(q, vec2(0.02, -0.19), 0.13, 0.07, 0.5);
    }

  } else if (which < 5.5) {
    // 5 -- a teapot. Spout one way, handle the other, both hoses.
    D(hose(q, vec2(0.20, 0.02), vec2(0.42 + n, 0.06), vec2(0.38, 0.26), 0.034), c3);
    D(hose(q, vec2(-0.20, 0.10), vec2(-0.44 - n, 0.02), vec2(-0.18, -0.16), 0.032), c3);
    D(sdEll(q - vec2(0.0, -0.08), vec2(0.30, 0.26)), c1);
    D(sdEll(q - vec2(0.0, -0.40), vec2(0.15, 0.045)), c3);
    D(sdEll(q - vec2(0.0, 0.18), vec2(0.17, 0.055)), c2);
    D(length(q - vec2(0.0, 0.25)) - 0.045, c3);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.115, -0.03), 0.089, look, ey, pop);
      eye(q, vec2( 0.115, -0.03), 0.089, look, ey, pop);
      grin(q, vec2(0.0, -0.21), 0.14, 0.08, 0.55);
    }

  } else if (which < 6.5) {
    // 6 -- a flower, on a stem that cannot keep still.
    D(hose(q, vec2(0.0, -0.50), vec2(0.10 + n * 1.4, -0.16), vec2(-0.01, 0.06), 0.026), c3);
    D(sdEll(rot(0.7) * (q - vec2(-0.20, -0.20)), vec2(0.14, 0.055)), c3);
    D(sdEll(rot(-0.7) * (q - vec2(0.19, -0.32)), vec2(0.13, 0.05)), c3);
    for (int i = 0; i < 6; i++) {
      float a = float(i) * TAU / 6.0 + u_beat * 0.02;
      D(sdEll(rot(-a) * (q - vec2(0.0, 0.22) - vec2(cos(a), sin(a)) * 0.245),
              vec2(0.150, 0.105)), c2);
    }
    D(length(q - vec2(0.0, 0.22)) - 0.215, c1);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.080, 0.26), 0.075, look, ey, pop);
      eye(q, vec2( 0.080, 0.26), 0.075, look, ey, pop);
      grin(q, vec2(0.0, 0.115), 0.105, 0.062, 0.5);
    }

  } else if (which < 7.5) {
    // 7 -- a fish, blowing one bubble per beat.
    D(sdEll(rot(0.45) * (q - vec2(-0.32, 0.02)), vec2(0.16, 0.10)), c2);     // tail
    D(sdEll(rot(-0.45) * (q - vec2(-0.32, -0.10)), vec2(0.16, 0.10)), c2);
    D(sdEll(q - vec2(0.02, -0.04), vec2(0.30, 0.21)), c1);
    D(sdEll(rot(0.3) * (q - vec2(0.0, -0.20)), vec2(0.12, 0.06)), c2);       // belly fin
    D(sdEll(q - vec2(0.0, 0.18), vec2(0.11, 0.07)), c2);                     // dorsal
    D(sdEll(q - vec2(0.29, -0.04), vec2(0.055, 0.045)), c3);                 // lips
    if (hasFace > 0.5) eye(q, vec2(0.15, 0.04), 0.090, look, ey, pop);

  } else if (which < 8.5) {
    // 8 -- an umbrella. The scalloped rim is three discs of the canopy colour laid under it,
    // so their outlines are wiped and only the bumps along the bottom edge survive.
    D(hose(q, vec2(0.0, 0.10), vec2(0.0, -0.36), vec2(-0.18 + n, -0.44), 0.026), c3);
    for (int i = 0; i < 3; i++)
      D(length(q - vec2((float(i) - 1.0) * 0.26, 0.06)) - 0.145, c1);
    D(max(length(q - vec2(0.0, 0.06)) - 0.40, 0.06 - q.y), c1);
    D(length(q - vec2(0.0, 0.46)) - 0.035, c3);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.105, 0.20), 0.082, look, ey, pop);
      eye(q, vec2( 0.105, 0.20), 0.082, look, ey, pop);
    }

  } else if (which < 9.5) {
    // 9 -- a toadstool.
    D(hose(q, vec2(0.0, -0.48), vec2(0.05 + n * 0.4, -0.24), vec2(-0.02, 0.02), 0.078), c3);
    D(sdEll(q - vec2(0.0, -0.45), vec2(0.20, 0.050)), c3);
    D(max(sdEll(q - vec2(0.0, 0.02), vec2(0.42, 0.30)), 0.02 - q.y), c1);
    D(length(q - vec2(-0.21, 0.13)) - 0.075, c2);
    D(length(q - vec2( 0.13, 0.19)) - 0.060, c2);
    D(length(q - vec2( 0.27, 0.07)) - 0.045, c2);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.085, -0.16), 0.074, look, ey, pop);
      eye(q, vec2( 0.085, -0.16), 0.074, look, ey, pop);
      grin(q, vec2(0.0, -0.31), 0.10, 0.055, 0.5);
    }

  } else if (which < 10.5) {
    // 10 -- a cactus in a pot, with its arms up.
    float pty = clamp((q.y + 0.48) / 0.22, 0.0, 1.0);
    D(max(abs(q.y + 0.37) - 0.11, abs(q.x) - mix(0.16, 0.23, pty)), c3);
    D(hose(q, vec2(-0.04, -0.10), vec2(-0.27 - n, -0.06), vec2(-0.27, 0.15), 0.065), c1);
    D(hose(q, vec2( 0.04, -0.02), vec2( 0.27 + n, 0.02), vec2( 0.27, 0.23), 0.065), c1);
    D(hose(q, vec2(0.0, -0.28), vec2(0.0, 0.05), vec2(0.0, 0.34), 0.115), c1);
    D(length(q - vec2(0.0, 0.41)) - 0.055, c2);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.062, 0.10), 0.062, look, ey, pop);
      eye(q, vec2( 0.062, 0.10), 0.062, look, ey, pop);
      grin(q, vec2(0.0, -0.03), 0.075, 0.045, 0.5);
    }

  } else if (which < 11.5) {
    // 11 -- a snail. Its shell is three discs, which is a spiral once the fill pattern is on.
    D(hose(q, vec2(-0.36, -0.38), vec2(0.0, -0.48), vec2(0.34, -0.30), 0.085), c3);
    D(sdEll(q - vec2(0.31, -0.22), vec2(0.13, 0.11)), c3);
    D(hose(q, vec2(0.34, -0.14), vec2(0.36 + n, 0.06), vec2(0.40, 0.16), 0.018), c3);
    D(hose(q, vec2(0.26, -0.14), vec2(0.20 - n, 0.04), vec2(0.16, 0.14), 0.018), c3);
    D(length(q - vec2(0.40, 0.18)) - 0.045, c2);
    D(length(q - vec2(0.16, 0.16)) - 0.045, c2);
    D(length(q - vec2(-0.06, -0.05)) - 0.30, c1);
    D(length(q - vec2(-0.02, -0.01)) - 0.195, c2);
    D(length(q - vec2( 0.01, 0.02)) - 0.105, c1);
    if (hasFace > 0.5) eye(q, vec2(0.33, -0.21), 0.062, look, ey, pop);

  } else if (which < 12.5) {
    // 12 -- an ice cream, three scoops and a cherry.
    float ty = clamp((q.y + 0.48) / 0.44, 0.0, 1.0);
    D(max(abs(q.y + 0.26) - 0.22, abs(q.x) - mix(0.02, 0.24, ty)), c3);
    D(length(q - vec2(-0.10, 0.01)) - 0.19, c1);
    D(length(q - vec2( 0.12, 0.08)) - 0.17, c2);
    D(length(q - vec2(-0.01, 0.25)) - 0.15, c1);
    D(length(q - vec2( 0.02, 0.42)) - 0.055, c2);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.075, 0.24), 0.066, look, ey, pop);
      eye(q, vec2( 0.075, 0.24), 0.066, look, ey, pop);
    }

  } else if (which < 13.5) {
    // 13 -- an alarm clock, permanently about to go off.
    D(length(q - vec2(-0.30, 0.29)) - 0.11, c3);
    D(length(q - vec2( 0.30, 0.29)) - 0.11, c3);
    D(hose(q, vec2(-0.17, -0.34), vec2(-0.23, -0.47), vec2(-0.29, -0.48), 0.022), c3);
    D(hose(q, vec2( 0.17, -0.34), vec2( 0.23, -0.47), vec2( 0.29, -0.48), 0.022), c3);
    D(length(q - vec2(0.0, -0.02)) - 0.36, c1);
    D(length(q - vec2(0.0, -0.02)) - 0.285, c2);
    D(sdSeg(q - vec2(0.0, -0.02), vec2(0.0), vec2(0.0, 0.19)) - 0.020, c3);
    D(sdSeg(q - vec2(0.0, -0.02), vec2(0.0), vec2(0.15, -0.07)) - 0.020, c3);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.115, 0.08), 0.070, look, ey, pop);
      eye(q, vec2( 0.115, 0.08), 0.070, look, ey, pop);
    }

  } else if (which < 14.5) {
    // 14 -- a rocket. The flame is the one thing here that answers the kick directly.
    D(sdEll(q - vec2(0.0, -0.42 - 0.06 * A), vec2(0.10, 0.11 + 0.12 * A)),
      mix(vec3(1.0, 0.72, 0.12), WHITE, 0.25 + 0.5 * A));
    D(sdEll(rot(0.55) * (q - vec2(-0.21, -0.25)), vec2(0.15, 0.055)), c2);
    D(sdEll(rot(-0.55) * (q - vec2(0.21, -0.25)), vec2(0.15, 0.055)), c2);
    D(sdEll(q - vec2(0.0, -0.04), vec2(0.17, 0.30)), c1);
    float ty = clamp((q.y - 0.24) / 0.22, 0.0, 1.0);
    D(max(abs(q.y - 0.35) - 0.11, abs(q.x) - mix(0.17, 0.015, ty)), c3);
    D(length(q - vec2(0.0, 0.06)) - 0.105, c2);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.048, 0.07), 0.055, look, ey, pop);
      eye(q, vec2( 0.048, 0.07), 0.055, look, ey, pop);
    }

  } else {
    // 15 -- a hot air balloon, which is the only one of them not standing on anything.
    D(sdSeg(q, vec2(-0.15, -0.08), vec2(-0.11, -0.30)) - 0.015, c3);
    D(sdSeg(q, vec2( 0.15, -0.08), vec2( 0.11, -0.30)) - 0.015, c3);
    float ty = clamp((q.y + 0.47) / 0.17, 0.0, 1.0);
    D(max(abs(q.y + 0.385) - 0.085, abs(q.x) - mix(0.10, 0.15, ty)), c3);
    D(sdEll(q - vec2(0.0, -0.13), vec2(0.17, 0.11)), c1);
    D(sdEll(q - vec2(0.0, 0.15), vec2(0.34, 0.35)), c1);
    D(max(sdEll(q - vec2(0.0, 0.15), vec2(0.34, 0.35)) + 0.020, abs(q.x) - 0.065), c2);
    D(max(sdEll(q - vec2(0.0, 0.15), vec2(0.34, 0.35)) + 0.020, abs(abs(q.x) - 0.22) - 0.050), c2);
    if (hasFace > 0.5) {
      eye(q, vec2(-0.115, 0.17), 0.072, look, ey, pop);
      eye(q, vec2( 0.115, 0.17), 0.072, look, ey, pop);
      grin(q, vec2(0.0, 0.02), 0.095, 0.052, 0.5);
    }
  }
}


// ---------------------------------------------------------------- the props
// One piece of business each, drawn over the top of its owner: steam off the teapot, a leaf
// off the tree, a hat that will not stay on. A cast that only bounces reads as a pattern; a
// cast that is each doing something reads as a scene. Which of them get one is decided per
// cell, and the ones that do not skip this whole function.
void props(vec2 q, float which, float A) {
  float k = gProp;
  float t = fract(u_beat * 0.5 + hash(vec2(gCell, 5.0)));     // one turn of the business per 2 beats
  float t1 = fract(t + 0.5);

  if (which < 0.5) {                                          // face: a hat that keeps lifting
    float lift = 0.055 * (0.4 + 0.6 * A) * max(0.0, sin(TAU * t));
    D(sdEll(q - vec2(0.0, 0.38 + lift), vec2(0.30 * k, 0.028)), gC3);
    D(max(abs(q.y - (0.46 + lift)) - 0.075, abs(q.x) - 0.17 * k), gC2);
  } else if (which < 1.5) {                                   // bird: a feather, going down
    D(sdEll(rot(3.0 * t) * (q - vec2(-0.34 + 0.10 * sin(TAU * t * 2.0), 0.28 - t * 0.66)),
            vec2(0.075 * k, 0.025 * k)), gC2);
  } else if (which < 2.5) {                                   // tree: a leaf, likewise
    D(sdEll(rot(2.2 * t) * (q - vec2(0.30 - 0.14 * sin(TAU * t * 1.5), 0.30 - t * 0.72)),
            vec2(0.070 * k, 0.030 * k)), gC1);
  } else if (which < 3.5) {                                   // lamp: the pool it is casting
    D(sdEll(q - vec2(0.0, -0.495), vec2(0.34 * k * (0.7 + 0.5 * A), 0.038 * k)),
      mix(vec3(1.0, 0.93, 0.58), WHITE, 0.3));
  } else if (which < 4.5) {                                   // trolley: something leaving it
    D(length(q - vec2(-0.02 + 0.52 * t, 0.18 + 0.60 * t - 1.35 * t * t)) - 0.055 * k, gC2);
  } else if (which < 5.5) {                                   // teapot: steam off the spout
    D(length(q - vec2(0.40 + 0.06 * sin(TAU * t * 2.0), 0.30 + t * 0.26)) - 0.052 * k * (1.0 - t), WHITE);
    D(length(q - vec2(0.40 + 0.06 * sin(TAU * t1 * 2.0), 0.30 + t1 * 0.26)) - 0.052 * k * (1.0 - t1), WHITE);
  } else if (which < 6.5) {                                   // flower: a bee doing the rounds
    D(length(q - vec2(0.0, 0.22) - vec2(cos(TAU * t) * 0.42, sin(TAU * t) * 0.26)) - 0.036 * k,
      vec3(1.0, 0.84, 0.12));
  } else if (which < 7.5) {                                   // fish: the bubbles, as before
    D(length(q - vec2(0.36 + t * 0.13, -0.02 + t * 0.46)) - 0.038 * k * (1.0 - t), WHITE);
    D(length(q - vec2(0.36 + t1 * 0.13, -0.02 + t1 * 0.46)) - 0.038 * k * (1.0 - t1), WHITE);
  } else if (which < 8.5) {                                   // umbrella: the reason for it
    float r1 = fract(t * 1.5), r2 = fract(t * 1.5 + 0.5);
    D(sdEll(q - vec2(-0.24, 0.56 - r1 * 0.40), vec2(0.015 * k, 0.045 * k)), vec3(0.62, 0.84, 1.0));
    D(sdEll(q - vec2( 0.26, 0.56 - r2 * 0.40), vec2(0.015 * k, 0.045 * k)), vec3(0.62, 0.84, 1.0));
  } else if (which < 9.5) {                                   // toadstool: spores going up
    D(length(q - vec2(-0.22, -0.06 + t * 0.52)) - 0.022 * k * (1.0 - t), WHITE);
    D(length(q - vec2( 0.20, -0.06 + t1 * 0.52)) - 0.022 * k * (1.0 - t1), WHITE);
  } else if (which < 10.5) {                                  // cactus: one fly, going nowhere
    D(length(q - vec2(0.36 * sin(TAU * t), 0.28 + 0.16 * sin(TAU * t * 1.7))) - 0.026 * k, INK);
  } else if (which < 11.5) {                                  // snail: what it leaves behind
    D(length(q - vec2(-0.44 - t * 0.12, -0.46)) - 0.028 * k * (1.0 - t), WHITE);
    D(length(q - vec2(-0.44 - t1 * 0.12, -0.46)) - 0.028 * k * (1.0 - t1), WHITE);
  } else if (which < 12.5) {                                  // ice cream: a drip, inevitably
    D(sdEll(q - vec2(-0.13 + 0.05 * t, 0.02 - t * 0.40),
            vec2(0.032 * k, 0.055 * k * (1.0 - 0.5 * t))), gC1);
  } else if (which < 13.5) {                                  // clock: it is always about to go
    float ring = exp(-6.0 * fract(u_beat)) * (0.4 + 0.6 * A);
    D(sdSeg(q, vec2(-0.42, 0.40), vec2(-0.52 - 0.08 * ring, 0.50 + 0.05 * ring)) - 0.016 * k, gC2);
    D(sdSeg(q, vec2( 0.42, 0.40), vec2( 0.52 + 0.08 * ring, 0.50 + 0.05 * ring)) - 0.016 * k, gC2);
  } else if (which < 14.5) {                                  // rocket: smoke, dropping away
    D(length(q - vec2(0.09 * sin(TAU * t * 1.5), -0.52 - t * 0.05)) - 0.052 * k * (1.0 - t), WHITE);
    D(length(q - vec2(0.09 * sin(TAU * t1 * 1.5), -0.52 - t1 * 0.05)) - 0.052 * k * (1.0 - t1), WHITE);
  } else {                                                    // balloon: ballast over the side
    D(length(q - vec2(0.11, -0.46 - t * 0.12)) - 0.020 * k * (1.0 - t), gC2);
    D(length(q - vec2(0.11, -0.46 - t1 * 0.12)) - 0.020 * k * (1.0 - t1), gC2);
  }
}

// The interior pattern. Four graphic languages rather than one spiral: which of them is on
// does more for how considered this looks than any other control here, so it is a knob and
// not a constant. Each gives a field and its local frequency in cycles per local unit; the
// frequency is what lets a hard edge be antialiased at all, WebGL1 having no derivatives.
float patternAt(vec2 c, float t) {
  float r = max(length(c), 0.05), a = atan(c.y, c.x), k = p_patscale;
  float v, fq;
  if (p_patmode < 0.5) {
    // Guilloche: two engine-turned line fields crossing, as on a banknote or a share
    // certificate. Machine-made, repeatable, nothing like a tie-dye.
    v = sin(TAU * (r * k * 3.2 + a * 3.0 / TAU - t))
      * sin(TAU * (r * k * 3.2 - a * 5.0 / TAU + t * 0.7)) * 1.7;
    fq = k * 3.2 + 5.0 / (TAU * r);
  } else if (p_patmode < 1.5) {
    // Halftone: a rotated dot screen, the dots swelling and shrinking in slow rings. Printed.
    vec2 g = rot(0.55) * c * k * 6.5;
    v = (0.15 + 0.30 * (0.5 + 0.5 * cos(TAU * (r * 2.2 - t))) - length(fract(g) - 0.5)) * 3.0;
    fq = k * 6.5;
  } else if (p_patmode < 2.5) {
    // Op: hard concentric rings on uneven spacing, after Riley. Precise rather than woozy.
    v = cos(TAU * (r * k * 2.6 + 0.30 * sin(r * 7.0) - t));
    fq = k * 3.4;
  } else {
    // The log-polar spiral: an endless tunnel inside the shape, same trick as the layout.
    v = cos(TAU * (log(r) * k + a * 2.0 / TAU - t));
    fq = (k + 0.32) / r;
  }
  float aa = min(0.9, 3.2 * fq * u_px / max(gS, 1e-5));
  return smoothstep(-aa, aa, v);
}

// ---------------------------------------------------------------- the picture
vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> the bounce and the squash
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> the noodle and the wedges
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> palette, cast, and faces

  float bb = barBeat();
  float H = p_hue + (p_follow > 0.5 ? u_hue : 0.0) + 0.12 * C;

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;
  float WX = max(u_aspect, 0.55) * 0.5;

  // Boil: the drawing re-inked a few times a second. It has to stay small now -- a thin hard
  // line shows every bit of jitter, where the old fat soft one swallowed it.
  float bt = floor(u_time * (6.0 + 8.0 * p_boil));
  p += (vec2(hash(vec2(bt, 1.7)), hash(vec2(bt, 9.1))) - 0.5) * p_boil * 0.006;

  // Thin, and never thinner than a pixel or it strobes as it moves. The feather is about one
  // pixel across, full stop: any more and a line this fine is a grey smudge.
  gPx = u_px * 0.7;
  gLw = max(p_ink * 0.0045, u_px * 1.1);
  gInk = 0.0;
  gFill = p_pat;

  float count = clamp(floor(p_cast + 0.5), 1.0, 8.0);
  float PAL = max(2.0, floor(p_palette + 0.5));

  // Background: a rosette, not a sunburst. Wedges mirrored at the same count as the cast, hard
  // concentric bands, and every colour a step of the same small palette. A continuous rainbow
  // is the one thing that makes work like this look like a screensaver; a handful of hues with
  // hard edges between them looks chosen. The kaleidoscope hue turn is quantised for the same
  // reason -- a smooth rotation would just smear the palette back into a gradient.
  float kseg = TAU / max(count, 3.0);
  float kang = abs(mod(atan(p.y, p.x) + u_beat * (0.004 + 0.012 * B) + kseg * 0.5, kseg) - kseg * 0.5)
             / (kseg * 0.5);
  float kr = length(p);
  float bandI = floor(kr * 9.0 - u_beat * p_zoom * 0.7);
  float wedgeI = floor(kang * 2.999);
  float kalShift = wedgeI * 0.667 - 0.667;
  vec3 plain = hsv(fract(H + 0.5), 0.55 * p_sat, p_bg);
  // Structure by value, in one hue, rather than by hue: stepping the hue at this brightness
  // just makes mud. Two tones of ring crossed with two tones of wedge reads as a built thing.
  vec3 rose = hsv(fract(H + 0.5 + 0.045 * mod(bandI, 2.0)), 0.52 * p_sat,
                  p_bg * mix(0.74, 1.22, mod(bandI, 2.0)) * mix(0.90, 1.12, mod(wedgeI, 2.0)));
  gCol = mix(plain, rose, p_rosette);
  vec3 bgCol = gCol;

  // ---- where the cast stands
  vec2 c;
  float ci, cj, S, fade = 1.0, floorY = -0.30;

  if (p_layout < 0.5) {
    // A row along the floor. A narrow surface cannot hold a line of them, so on anything
    // squarer than 16:9 the cast thins out rather than shrinking to specks.
    count = min(count, max(1.0, floor(u_aspect * 2.9)));
    float cw = 2.0 * WX / count;
    ci = clamp(floor((p.x + WX) / cw), 0.0, count - 1.0);
    cj = 0.0;
    S = p_size * min(cw * 1.05, 0.76);
    draw(p.y - floorY, hsv(fract(H + 0.5), 0.60 * p_sat, p_bg * 1.25));
    bgCol = gCol;
    c = (vec2(p.x + WX - (ci + 0.5) * cw, p.y) - vec2(0.0, floorY + 0.5 * S)) / max(S, 1e-4);
    gS = max(S, 1e-4);
  } else {
    // A tunnel. log(r) against the angle, repeated on both, which is an endless receding ring
    // of them for the price of the row. Square cells in that space (the ring spacing equal to
    // the wedge) keep every subject the same shape however far down it is, because the map is
    // conformal; the scale it introduces is exactly r, which goes straight into gS so that the
    // pen stays one width at every depth.
    count = max(3.0, count);
    float seg = TAU / count;
    float r = max(length(p), 1e-5);
    float a = mod(atan(p.y, p.x) + u_beat * p_spin * TAU + TAU, TAU);
    float lr = log(r) + u_beat * p_zoom * seg;
    cj = floor(lr / seg);
    ci = floor(a / seg);
    c = vec2(a - (ci + 0.5) * seg, lr - (cj + 0.5) * seg) / (seg * max(p_size, 0.05));
    gS = seg * max(p_size, 0.05) * r;
    // Near the middle the cells fall below a few pixels across and turn to noise. Fade them
    // into the card before that happens, and skip drawing them at all once they are gone.
    fade = smoothstep(9.0, 26.0, seg * r / max(u_px, 1e-6));
  }

  float turn = floor(bb / max(p_swap * 4.0, 1.0)) + floor(C * 3.0);
  float which = mod(turn + ci * 3.0 + cj * 5.0, 16.0);

  // The bounce. Each one is a little behind the last; A says how hard they land.
  float lag = ci * 0.15 + cj * 0.25;
  float wob = sin(TAU * (bb / max(loopBeats(p_aloop), 0.5) - lag));
  float up = max(0.0, wob), down = max(0.0, -wob);
  float hop = p_bounce * (0.05 + 0.20 * A) * up;
  float squash = 1.0 + p_bounce * (0.06 + 0.26 * A) * down;

  // Dance: a shimmy across, a turn to face left and right, and a rock from the feet, on top of
  // the hop. Each runs at a different fraction of the loop so they drift apart rather than
  // reading as one metronome, and each cell is a step behind the one before it.
  float dph = TAU * (bb / max(loopBeats(p_aloop), 0.5) - lag);
  gTurn = p_dance * 0.55 * sin(dph * 0.5 + 1.1);
  c.x -= p_dance * 0.085 * sin(dph * 0.5);
  c.y -= hop;
  // Squash on the landing: wider and shorter, never the other way round, and pivoting on the
  // feet. Scaling about the middle instead pushes them through the floor as they flatten.
  c.x /= squash;
  c.y = (c.y + 0.5) * squash - 0.5;
  // Turning to face left and right: lean into it, then foreshorten. Two cheap tricks which
  // together read as a sprite pivoting on the spot, where either alone reads as a squeeze.
  c.x += gTurn * 0.11 * (c.y + 0.5);
  c.x /= max(0.45, cos(gTurn));
  // The rock pivots on the feet too, for the same reason the squash does.
  c = rot(p_dance * 0.20 * sin(dph)) * (c + vec2(0.0, 0.5)) - vec2(0.0, 0.5);

  if (p_layout < 0.5) {
    // Cast, not drawn: no pen goes near it, and it darkens the floor rather than being a black
    // shape, or the bottom of the frame welds into one bar.
    float shd = sdEll(vec2(p.x + WX - (ci + 0.5) * (2.0 * WX / count), p.y - floorY),
                      vec2(S * 0.36 * (1.0 - hop * 1.2), S * 0.05));
    gCol = mix(gCol, gCol * 0.40, (1.0 - smoothstep(-S * 0.02, S * 0.015, shd)) * 0.85);
    bgCol = gCol;
  }

  // Who this one is. Eyes, a mouth and a prop are each decided per cell, so a row of five is
  // two with eyes, one of those with a mouth and a couple carrying something, rather than five
  // identical grinning things.
  gCell = ci * 7.0 + cj * 13.0;
  float faceAmt = clamp(p_face + C * p_facec, 0.0, 1.0);
  gEye = step(hash(vec2(gCell, 21.0)), p_faceodds) * faceAmt;
  gMouth = step(hash(vec2(gCell, 47.0)), p_faceodds * 0.55) * gEye;
  gProp = step(hash(vec2(gCell, 83.0)), p_propodds) * p_prop;

  // Three flat colours per cell, every one of them a step of the same small palette.
  float i1 = floor(hash(vec2(gCell, 11.0)) * PAL);
  float i2 = mod(i1 + 1.0 + floor(hash(vec2(gCell, 3.0)) * (PAL - 1.0)), PAL);
  float i3 = mod(i1 + 2.0 + floor(hash(vec2(gCell, 17.0)) * (PAL - 1.0)), PAL);
  gC1 = hsv(fract(H + p_spread * (i1 / PAL - 0.5) * 2.0), 0.98 * p_sat, 1.0);
  gC2 = hsv(fract(H + p_spread * (i2 / PAL - 0.5) * 2.0), 1.00 * p_sat, 0.97);
  gC3 = hsv(fract(H + p_spread * (i3 / PAL - 0.5) * 2.0), 0.92 * p_sat, 0.80);
  gNoodle = p_noodle * 0.05 * sin(u_beat * (1.1 + 0.6 * hash(vec2(gCell, 7.0))) + ci) * (0.4 + 1.6 * B);

  // The interior, drawn in the subject's own coordinates so it belongs to the shape. Hard
  // bands, never a smooth ramp: a ramp airbrushes the fills and the whole thing stops looking
  // like ink and starts looking like a 1970s tour poster.
  gPat = patternAt(c, u_beat * p_patspin);

  if (fade > 0.01) {
    subject(c, which, A, A * 0.5);
    if (gProp > 0.02) props(c, which, A);
  }

  vec3 col = mix(gCol, INK, clamp(gInk, 0.0, 1.0));
  col = mix(bgCol, col, fade);
  col = hueRot(col, p_kal * kalShift);                   // a turn of the hue, not a wash
  col *= 0.96 + 0.09 * hash(p * 620.0 + u_time * 41.0) * p_film;
  col = mix(col, WHITE, step(0.9991, hash(vec2(floor(p.x * 240.0), floor(u_time * 20.0)))) * 0.4 * p_film);
  col *= 1.0 - 0.28 * p_film * pow(clamp(length(p * vec2(0.85, 1.30)), 0.0, 1.0), 3.0);
  return col;
}
