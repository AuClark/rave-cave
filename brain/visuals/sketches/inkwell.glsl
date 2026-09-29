// Inkwell: a rubber hose chorus line coming up out of the inkwell, after Fleischer, early Disney
// and everything Cuphead borrowed from them.
//
// Everything is a character. A teapot, a tree, an alarm clock and a bomb each get pie-cut eyes,
// a grin that opens on the kick, noodle arms that end in white four-finger gloves, and noodle
// legs down to big round shoes. The feet stay planted on the floor and the body bobs over them,
// so on every beat the legs bow out like rubber and the body squashes -- wider and shorter,
// holding its volume -- then stretches on the way back up. That one move is most of the style.
//
// The line is thick and confident, drawn in the character's own units so it scales with them,
// and it boils: the whole drawing is re-inked four times a beat, a slightly different wobble and
// a slightly different weight each time, the way a stack of hand-inked cels does.
//
// The shapes are masks. Each body is filled with a pattern drawn in its own coordinates --
// checkers or stripes spiralling into a little log-polar tunnel of their own, polka dots, or op
// rings -- so the fill squashes and turns with the shape instead of sliding about under it.
//
// The layout is the same log-polar trick one level up: log(r) against the angle, repeated on
// both, so the cast is an endless ring of rings, every row standing on its own floor, with an
// ink pool in the middle that they climb out of (or fall back into). Spin and Zoom are one term
// each, in cycles per beat. The row layout is a stage with a floor, for a wide surface.
//
// Colour is a set of designed palettes -- five inks each, a card, a floor and the fills -- not a
// hue wheel, because a handful of chosen colours with hard edges is what makes this look printed.
//
// Drivers (docs/reactive.md): A Hit -> the bounce, the squash on the landing, eyes popping and
// the mouths opening, the candle flame, the radio's speaker, the bomb's spark. B Move -> the
// noodle in the hoses, the gloves wiggling their fingers, and how often they blink. C Change ->
// the fills swelling (more pattern, bigger, into the second colour), who the cast is next, and
// (through Faces on C) whether they have faces at all.
// Params are p_* uniforms; ranges and defaults are in inkwell.json.
uniform float p_layout, p_cast, p_swap, p_size, p_bounce, p_dance, p_limbs,
              p_spin, p_zoom,
              p_ink, p_boil, p_noodle,
              p_pat, p_patmode, p_patscale, p_patspin, p_shade,
              p_face, p_facec, p_faceodds,
              p_prop, p_propodds,
              p_kal, p_rosette, p_bg, p_film,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_palette, p_spread, p_sat, p_follow;

#define TAU 6.2831853
#define PI 3.1415927

// The picture is painted shape over shape into gCol, with the ink laid over it in gInk.
// gS carries a distance in the cast's own units out to surface units.
vec3 gCol, gC1, gC2, gC3, gAlt;
float gInk, gTop, gPx, gLw, gS, gPat, gFill, gShade, gDot, gSide, gNoodle;
// The palette: card, floor, three fills, the pattern's second colour, and the limbs.
vec3 P_BG, P_FL, P_1, P_2, P_3, P_PAT, P_LIMB, P_MOUTH, P_TONGUE;

const vec3 INK = vec3(0.05, 0.035, 0.045);
const vec3 GLOVE = vec3(0.99, 0.97, 0.92);
const vec3 MOUTH = vec3(0.30, 0.04, 0.07);
const vec3 TONGUE = vec3(0.95, 0.36, 0.40);

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
float sdEll(vec2 p, vec2 r) { return (length(p / r) - 1.0) * min(r.x, r.y); }
float sdBox(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
// A pie slice opening along +y, half-angle given as (sin, cos) -- the notch in a pie-cut eye.
float sdPie(vec2 p, vec2 c, float r) {
  p.x = abs(p.x);
  float l = length(p) - r;
  float m = length(p - c * clamp(dot(p, c), 0.0, r));
  return max(l, m * sign(c.y * p.x - c.x * p.y));
}

// Turn a colour's hue about the grey axis without washing it out.
vec3 hueRot(vec3 c, float turns) {
  vec3 k = vec3(0.57735027);
  float ca = cos(turns * TAU), sa = sin(turns * TAU);
  return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

// A hose: one thickness, round ends, bending in a curve rather than hinging at a joint. The
// curve is walked in four straight pieces, which is plenty at this weight.
float hose(vec2 p, vec2 a, vec2 b, vec2 c, float r) {
  vec2 q1 = mix(mix(a, b, 0.25), mix(b, c, 0.25), 0.25);
  vec2 q2 = mix(mix(a, b, 0.5), mix(b, c, 0.5), 0.5);
  vec2 q3 = mix(mix(a, b, 0.75), mix(b, c, 0.75), 0.75);
  return min(min(sdSeg(p, a, q1), sdSeg(p, q1, q2)), min(sdSeg(p, q2, q3), sdSeg(p, q3, c))) - r;
}

// Paint a shape given in the cast's units: fill it, hide what was behind, lay the ink on top.
// It also keeps the distance to the edge of whichever shape is on top (gTop), which is all the
// halftone shading needs, so that is worked out once at the end rather than in every shape.
void D(float d, vec3 c) {
  d *= gS;
  float f = 1.0 - smoothstep(-gPx, gPx, d);
  float e = 1.0 - smoothstep(gLw - gPx, gLw + gPx, abs(d));
  gCol = mix(gCol, c, f);
  gTop = mix(gTop, d, f);
  gInk = max(gInk * (1.0 - f), e);
}

// The same in clean white, for gloves and eyes, which the halftone leaves alone.
void DW(float d) {
  d *= gS;
  float f = 1.0 - smoothstep(-gPx, gPx, d);
  float e = 1.0 - smoothstep(gLw - gPx, gLw + gPx, abs(d));
  gCol = mix(gCol, GLOVE, f);
  gTop = mix(gTop, 1.0, f);
  gInk = max(gInk * (1.0 - f), e);
}

// A fill with the pattern in it: the mask idea. Only the main shapes get it.
vec3 sk(vec3 base) { return mix(base, gAlt, gPat * gFill); }

// ---------------------------------------------------------------- the rig
// Every character stands in -0.5..0.5 with its shoes on y = -0.5. These say where its face,
// shoulders and hips are, in its own body space.
vec3 gFace;          // x, y, scale
vec2 gSh, gHip;
float gLim;         // how far out a hand may go, in body space      // right shoulder, right hip (the left ones are mirrored)
float gLegs, gMouthOK, gHands;

void anchors(float w) {
  gFace = vec3(0.0, 0.02, 1.0); gSh = vec2(0.27, -0.02); gHip = vec2(0.12, -0.22);
  gLegs = 1.0; gMouthOK = 1.0;
  if (w < 0.5)       { gFace = vec3(0.0, 0.20, 1.0);  gSh = vec2(0.13, -0.08); gHip = vec2(0.08, -0.25); }  // critter
  else if (w < 1.5)  { gFace = vec3(0.03, -0.01, 1.05); gSh = vec2(0.28, -0.06); gHip = vec2(0.12, -0.20); } // teapot
  else if (w < 2.5)  { gFace = vec3(0.0, 0.26, 0.9);  gSh = vec2(0.07, 0.00);  gHip = vec2(0.06, -0.24); }  // tree
  else if (w < 3.5)  { gFace = vec3(0.0, 0.23, 0.85); gSh = vec2(0.03, -0.10); gHip = vec2(0.03, -0.25); }  // flower
  else if (w < 4.5)  { gFace = vec3(0.0, 0.03, 1.0); }                                                        // clock
  else if (w < 5.5)  { gFace = vec3(0.0, -0.08, 0.72); gSh = vec2(0.15, -0.10); gHip = vec2(0.08, -0.26); } // toadstool
  else if (w < 6.5)  { gFace = vec3(0.0, 0.13, 0.8);  gSh = vec2(0.13, 0.00);  gHip = vec2(0.08, -0.24); }  // cactus
  else if (w < 7.5)  { gFace = vec3(0.0, 0.20, 0.85); gSh = vec2(0.14, -0.02); gHip = vec2(0.05, -0.25); }  // ice cream
  else if (w < 8.5)  { gFace = vec3(0.0, -0.01, 1.0); gSh = vec2(0.28, -0.04); }                            // bomb
  else if (w < 9.5)  { gFace = vec3(0.0, 0.21, 0.8);  gSh = vec2(0.27, -0.06); gHip = vec2(0.14, -0.24); gMouthOK = 0.0; } // radio
  else if (w < 10.5) { gFace = vec3(0.0, 0.06, 0.8);  gSh = vec2(0.14, -0.02); gHip = vec2(0.08, -0.26); }  // candle
  else               { gFace = vec3(0.0, 0.14, 1.0);  gSh = vec2(0.24, 0.00);  gLegs = 0.0; }              // ghost
}

// A white cartoon glove: palm, three fat fingers and a thumb, and a cuff at the wrist. Fingers
// wiggle on the hats. Far down the tunnel it is a mitten, which is all that reads at that size.
void glove(vec2 q, vec2 at, vec2 dir, float side, float wig, float detail) {
  vec2 h = q - at;
  if (dot(h, h) > 0.030) return;
  h = vec2(dot(h, dir), dot(h, vec2(-dir.y, dir.x)) * side);
  float lw0 = gLw;
  gLw = max(gLw * 0.7, u_px * 0.8);
  DW(length(h - vec2(0.048, 0.0)) - 0.058);
  if (detail > 0.5) {
    for (int i = 0; i < 3; i++) {
      float a = (float(i) - 1.0) * 0.36 - 0.12 + wig * (float(i) - 0.6);
      DW(sdSeg(h, vec2(0.070, 0.0), vec2(0.070, 0.0) + vec2(cos(a), sin(a)) * 0.058) - 0.029);
    }
    DW(sdSeg(h, vec2(0.045, 0.030), vec2(0.070, 0.085)) - 0.025);
  }
  DW(sdEll(h - vec2(-0.006, 0.0), vec2(0.028, 0.066)));
  gLw = lw0;
}

// A noodle arm from the shoulder, and the glove on the end of it.
void arm(vec2 q, vec2 sh, float ang, float bend, float side, float wig, float detail) {
  vec2 hand = sh + vec2(cos(ang), sin(ang)) * 0.24;
  // The cell is all a character has, so the hand stays inside it with room for the glove: the
  // arm bends instead of the glove being cut off at the edge.
  hand.x = clamp(hand.x, -gLim, gLim);
  vec2 dd = hand - sh, mid = (sh + hand) * 0.5;
  vec2 ctrl = mid + vec2(-dd.y, dd.x) * bend;
  vec2 dq = q - mid;
  if (dot(dq, dq) < 0.075) D(hose(q, sh, ctrl, hand, 0.021), P_LIMB);
  glove(q, hand, normalize(hand - ctrl), side, wig, detail);
}

// The pie-cut eyes and the grin. The eyes touch, the pupils are tall black ovals with the pie
// notch cut out of them, the lids come down on a blink, and the mouth opens on the kick.
void face(vec2 q, float A, float blink, vec2 look, float mouth, float detail) {
  vec2 f = (q - gFace.xy) / gFace.z;
  if (dot(f, f) > 0.075) return;
  float sc = gFace.z;
  float pop = 1.0 + 0.22 * A;
  float lw0 = gLw;
  gLw = max(gLw * 0.6, u_px * 0.8);          // a finer nib for the features
  for (int i = 0; i < 2; i++) {
    vec2 e = f - vec2(float(i) * 0.124 - 0.062, 0.035);
    vec2 r = vec2(0.062, 0.094) * pop;
    DW(sdEll(e, vec2(r.x, r.y * mix(1.0, 0.10, blink))) * sc);
    if (blink < 0.5) {
      vec2 pe = e - vec2(look.x * 0.020, look.y * 0.022 - 0.016);
      float dp = sdEll(pe, vec2(0.031, 0.052) * pop);
      if (detail > 0.5) dp = max(dp, -sdPie(rot(0.70) * (pe - vec2(0.004, 0.006)), vec2(0.40, 0.92), 0.08));
      D(dp * sc, INK);
    }
  }
  if (mouth > 0.5) {
    vec2 m = f - vec2(0.0, -0.105);
    float w = 0.115, h = 0.030 + 0.070 * A;
    float tx = clamp(m.x / w, -1.0, 1.0);
    float d = max(sdEll(m, vec2(w, h + 0.02)), m.y - (-0.15 * h + 0.9 * h * tx * tx) - 0.005);
    D(d * sc, P_MOUTH);
    if (detail > 0.5) D(max(d + 0.008, sdEll(m - vec2(0.0, -h * 0.8), vec2(w * 0.45, h * 0.6))) * sc, P_TONGUE);
  }
  gLw = lw0;
}

// A quaver, for the ones that sing.
void note(vec2 q, vec2 at, float k) {
  vec2 n = q - at;
  if (dot(n, n) > 0.03) return;
  D(sdEll(rot(0.45) * n, vec2(0.040, 0.028) * k), INK);
  D(max(abs(n.x - 0.034 * k) - 0.008 * k, abs(n.y - 0.07 * k) - 0.075 * k), INK);
  D(hose(n, vec2(0.034, 0.14) * k, vec2(0.08, 0.12) * k, vec2(0.075, 0.06) * k, 0.008 * k), INK);
}

// ---------------------------------------------------------------- the cast
// Twelve bodies, each with its limbs and face drawn by the rig. The main shape of each carries
// the fill pattern (sk); the rest are flat.
void body(vec2 q, float w, float A, float B) {
  vec3 c1 = sk(gC1);
  float n = gNoodle;
  if (w < 0.5) {
    // 0 -- a critter: round head, round ears, pear body. The house mascot.
    D(sdEll(q - vec2(0.0, -0.11), vec2(0.15, 0.16)), c1);
    D(length(q - vec2(-0.185, 0.40)) - 0.105, gC3);
    D(length(q - vec2( 0.185, 0.40)) - 0.105, gC3);
    D(length(q - vec2(0.0, 0.20)) - 0.225, gC2);
    D(sdEll(q - vec2(0.0, 0.10), vec2(0.045, 0.032)), INK);
  } else if (w < 1.5) {
    // 1 -- a teapot, spout up in the air.
    D(hose(q, vec2(-0.22, 0.02), vec2(-0.42, 0.04 + n), vec2(-0.43, 0.26), 0.036), gC2);
    D(sdEll(q - vec2(0.0, -0.01), vec2(0.30, 0.22)), c1);
    D(sdEll(q - vec2(0.0, 0.21), vec2(0.17, 0.05)), gC2);
    D(length(q - vec2(0.0, 0.28)) - 0.042, gC3);
  } else if (w < 2.5) {
    // 2 -- a tree: a trunk that dances and a canopy of five scallops, each fill wiping the
    // outline of the one before so only the scalloped edge survives.
    D(hose(q, vec2(0.0, -0.26), vec2(n, -0.10), vec2(0.0, 0.10), 0.075), gC3);
    D(length(q - vec2(-0.22, 0.20)) - 0.16, c1);
    D(length(q - vec2( 0.22, 0.22)) - 0.155, c1);
    D(length(q - vec2(-0.10, 0.37)) - 0.17, c1);
    D(length(q - vec2( 0.13, 0.38)) - 0.16, c1);
    D(length(q - vec2( 0.0, 0.24)) - 0.19, c1);
  } else if (w < 3.5) {
    // 3 -- a flower on a stem that cannot keep still: one scalloped disc for the petals.
    D(hose(q, vec2(0.0, -0.26), vec2(n * 1.5, -0.10), vec2(0.0, 0.08), 0.030), gC3);
    vec2 v = q - vec2(0.0, 0.23);
    float a = atan(v.y, v.x) + u_beat * 0.25;
    D((length(v) - 0.265 - 0.055 * cos(6.0 * a)) * 0.8, c1);
    D(length(v) - 0.165, gC2);
  } else if (w < 4.5) {
    // 4 -- an alarm clock, permanently about to go off.
    float ring = 0.03 * sin(u_beat * TAU * 4.0) * A;
    D(length(q - vec2(-0.21 - ring, 0.33)) - 0.10, gC3);
    D(length(q - vec2( 0.21 + ring, 0.33)) - 0.10, gC3);
    D(length(q - vec2(0.0, 0.03)) - 0.31, c1);
    D(length(q - vec2(0.0, 0.03)) - 0.225, P_PAT);
    if (gHands > 0.5) {                                        // no face, so it gets its hands back
      vec2 o = q - vec2(0.0, 0.03);
      D(sdSeg(o, vec2(0.0), vec2(0.0, 0.16)) - 0.018, INK);
      D(sdSeg(o, vec2(0.0), rot(-u_beat * PI * 0.5) * vec2(0.0, 0.19)) - 0.012, INK);
    }
  } else if (w < 5.5) {
    // 5 -- a toadstool: a spotted cap on a pale stem with the face on it.
    D(sdEll(q - vec2(0.0, -0.09), vec2(0.155, 0.19)), P_PAT);
    D(max(sdEll(q - vec2(0.0, 0.08), vec2(0.43, 0.32)), 0.08 - q.y), c1);
    D(length(q - vec2(-0.22, 0.20)) - 0.070, gC2);
    D(length(q - vec2( 0.10, 0.30)) - 0.060, gC2);
    D(length(q - vec2( 0.27, 0.15)) - 0.045, gC2);
  } else if (w < 6.5) {
    // 6 -- a cactus with a flower in its hat.
    D(length(q - vec2(0.0, 0.43)) - 0.065, gC2);
    D(sdSeg(q, vec2(0.0, -0.22), vec2(0.0, 0.29)) - 0.145, c1);
  } else if (w < 7.5) {
    // 7 -- an ice cream: a cone, a scoop dripping over it, and a cherry.
    float ty = clamp((q.y + 0.27) / 0.30, 0.0, 1.0);
    D(max(abs(q.y + 0.12) - 0.15, abs(q.x) - mix(0.03, 0.17, ty)), gC2);
    D(length(q - vec2(-0.11, 0.02)) - 0.075, c1);
    D(length(q - vec2( 0.10, 0.01)) - 0.070, c1);
    D(length(q - vec2(0.0, 0.18)) - 0.21, c1);
    D(hose(q, vec2(0.03, 0.42), vec2(0.06, 0.48), vec2(0.10, 0.50), 0.010), gC3);
    D(length(q - vec2(0.03, 0.42)) - 0.055, gC3);
  } else if (w < 8.5) {
    // 8 -- a bomb, fuse lit.
    D(hose(q, vec2(0.0, 0.34), vec2(0.08 + n, 0.46), vec2(0.17, 0.44), 0.017), P_PAT);
    D(sdBox(q - vec2(0.0, 0.30), vec2(0.075, 0.045)), gC2);
    D(length(q - vec2(0.0, -0.01)) - 0.295, sk(gC3));
    D(sdEll(rot(0.6) * (q - vec2(-0.14, 0.14)), vec2(0.075, 0.035)), GLOVE);
  } else if (w < 9.5) {
    // 9 -- a cathedral radio. Its speaker is its mouth and it thumps on the kick.
    D(min(sdBox(q - vec2(0.0, -0.08), vec2(0.27, 0.16)), length(q - vec2(0.0, 0.08)) - 0.27), gC2);
    float g = 1.0 + 0.12 * A;
    D(sdEll(q - vec2(0.0, -0.03), vec2(0.18, 0.13) * g), c1);
    D(length(q - vec2(-0.14, -0.19)) - 0.035, gC3);
    D(length(q - vec2( 0.14, -0.19)) - 0.035, gC3);
  } else if (w < 10.5) {
    // 10 -- a candle. The flame flickers on the hats and flares on the kick.
    vec2 fq = q - vec2(0.03 * sin(u_beat * 9.0) * (0.3 + B), 0.38);
    D(sdEll(fq, vec2(0.065, 0.10 + 0.05 * A)), gC2);
    D(sdEll(fq + vec2(0.0, 0.02), vec2(0.030, 0.05 + 0.02 * A)), GLOVE);
    D(sdSeg(q, vec2(0.0, 0.22), vec2(0.0, 0.29)) - 0.012, INK);
    D(sdBox(q - vec2(0.0, -0.02), vec2(0.13, 0.22)) - 0.02, c1);
    D(sdEll(q - vec2(0.09, 0.14), vec2(0.035, 0.08)), P_PAT);
  } else {
    // 11 -- a ghost, which floats, so no legs; its hem ripples.
    float hem = -0.36 + 0.04 * sin(q.x * 24.0 + u_beat * PI);
    D(max(min(length(q - vec2(0.0, 0.12)) - 0.26, sdBox(q - vec2(0.0, -0.10), vec2(0.26, 0.24))),
          (hem - q.y) * 0.7), c1);
  }
}

// ---------------------------------------------------------------- the props
// One piece of business each, drawn over the top of its owner.
void props(vec2 q, float w, float A, float t) {
  float t1 = fract(t + 0.5);
  if (w < 0.5) {                                              // critter: a bowler that won't stay on
    float lift = 0.06 * (0.3 + 0.7 * A) * max(0.0, sin(TAU * t));
    vec2 h = rot(0.25 * sin(TAU * t)) * (q - vec2(0.02, 0.40 + lift));
    D(sdEll(h - vec2(0.0, -0.01), vec2(0.20, 0.028)), gC3);
    D(max(sdEll(h - vec2(0.0, 0.04), vec2(0.12, 0.10)), -0.01 - h.y), gC3);
  } else if (w < 1.5 || w > 9.5 && w < 10.5) {              // teapot, candle: steam and smoke
    vec2 o = w < 1.5 ? vec2(-0.43, 0.30) : vec2(0.0, 0.50);
    D(length(q - o - vec2(0.05 * sin(TAU * t * 2.0), t * 0.22)) - 0.050 * (1.0 - t), P_PAT);
    D(length(q - o - vec2(0.05 * sin(TAU * t1 * 2.0), t1 * 0.22)) - 0.050 * (1.0 - t1), P_PAT);
  } else if (w < 2.5) {                                       // tree: a leaf coming down
    D(sdEll(rot(2.2 * t) * (q - vec2(0.36 - 0.10 * sin(TAU * t * 1.5), 0.36 - t * 0.70)),
            vec2(0.065, 0.030)), gC2);
  } else if (w < 3.5) {                                       // flower: a bee doing the rounds
    vec2 b = q - vec2(0.0, 0.23) - vec2(cos(TAU * t) * 0.40, sin(TAU * t) * 0.24);
    D(sdEll(b, vec2(0.045, 0.032)), P_2);
  } else if (w < 4.5) {                                       // clock: the ringing
    float ring = exp(-6.0 * fract(u_beat)) * (0.4 + 0.6 * A);
    D(sdSeg(q, vec2(-0.36, 0.44), vec2(-0.44 - 0.06 * ring, 0.52 + 0.04 * ring)) - 0.012, INK);
    D(sdSeg(q, vec2( 0.36, 0.44), vec2( 0.44 + 0.06 * ring, 0.52 + 0.04 * ring)) - 0.012, INK);
  } else if (w < 5.5) {                                       // toadstool: spores
    D(length(q - vec2(-0.30, 0.10 + t * 0.40)) - 0.024 * (1.0 - t), P_PAT);
    D(length(q - vec2( 0.32, 0.10 + t1 * 0.40)) - 0.024 * (1.0 - t1), P_PAT);
  } else if (w < 6.5) {                                       // cactus: one fly, going nowhere
    D(length(q - vec2(0.34 * sin(TAU * t), 0.36 + 0.10 * sin(TAU * t * 1.7))) - 0.024, INK);
  } else if (w < 7.5) {                                       // ice cream: a drip, inevitably
    D(sdEll(q - vec2(-0.14, -0.02 - t * 0.30), vec2(0.030, 0.050 * (1.0 - 0.5 * t))), gC1);
  } else if (w < 8.5) {                                       // bomb: the spark
    vec2 s = q - vec2(0.18, 0.45);
    float k = 0.7 + 0.8 * A;
    D(min(sdEll(rot(u_beat * 3.0) * s, vec2(0.075, 0.018) * k),
          sdEll(rot(u_beat * 3.0 + 1.57) * s, vec2(0.075, 0.018) * k)), P_2);
  } else {                                                    // radio, ghost: they sing
    note(q, vec2(0.30 + 0.06 * sin(TAU * t * 1.5), 0.10 + t * 0.34), 0.9 * (1.0 - t * t));
  }
}

// The interior pattern, in the body's own coordinates, as a field and its local frequency (for
// antialiasing a hard edge without derivatives, which WebGL1 does not have).
float patternAt(vec2 c, float t, float k) {
  float v, fq;
  if (p_patmode < 1.5) {
    vec2 v0 = c - vec2(0.0, 0.05);
    float r = max(length(v0), 0.02), a = atan(v0.y, v0.x);
    float lr = log(r);
    if (p_patmode < 0.5) {
      // Checkers, spiralling down a log-polar tunnel inside the shape.
      float u = lr * k * 0.9 - t, s = a * 8.0 / TAU + lr * 0.8;
      v = sin(TAU * u) * sin(TAU * s) * 2.5;
      fq = (k * 0.9 + 1.3) / r;
    } else {
      // Candy stripes: the barber's pole, wound into the same tunnel.
      v = cos(TAU * (lr * k * 0.7 + a * 3.0 / TAU - t)) * 1.6;
      fq = (k * 0.7 + 0.5) / r;
    }
  } else if (p_patmode < 2.5) {
    // Polka dots, drifting on the diagonal.
    vec2 g = rot(0.5) * c * k * 3.0 + vec2(t, 0.0);
    v = (0.30 - length(fract(g) - 0.5)) * 4.0;
    fq = k * 3.0;
  } else {
    // Op rings: a target, the rings running out from the middle.
    v = cos(TAU * (length(c - vec2(0.0, 0.05)) * k * 2.6 - t)) * 1.4;
    fq = k * 2.6;
  }
  float aa = min(1.0, 2.5 * fq * u_px / max(gS, 1e-5));
  return smoothstep(-aa, aa, v);
}

void palette(float i) {
  if (i < 0.5) {        // inkwell: red, mustard and teal on a plum-black card, cream limbs
    P_BG = vec3(0.13, 0.09, 0.14); P_FL = vec3(0.32, 0.17, 0.24);
    P_1 = vec3(0.90, 0.22, 0.18); P_2 = vec3(0.98, 0.74, 0.22); P_3 = vec3(0.10, 0.52, 0.55);
    P_PAT = vec3(0.98, 0.92, 0.78); P_LIMB = vec3(0.98, 0.92, 0.78);
  } else if (i < 1.5) { // sunday comic: process red, yellow and blue on newsprint
    P_BG = vec3(0.95, 0.90, 0.77); P_FL = vec3(0.85, 0.78, 0.62);
    P_1 = vec3(0.90, 0.16, 0.18); P_2 = vec3(1.00, 0.82, 0.12); P_3 = vec3(0.10, 0.48, 0.80);
    P_PAT = vec3(0.97, 0.93, 0.82); P_LIMB = INK;
  } else if (i < 2.5) { // silent: the greys of a nitrate print
    P_BG = vec3(0.74, 0.72, 0.67); P_FL = vec3(0.56, 0.55, 0.51);
    P_1 = vec3(0.95, 0.94, 0.90); P_2 = vec3(0.52, 0.51, 0.49); P_3 = vec3(0.27, 0.27, 0.27);
    P_PAT = vec3(0.16, 0.16, 0.16); P_LIMB = INK;
  } else if (i < 3.5) { // neon: pink, yellow and cyan on midnight, violet in the fills
    P_BG = vec3(0.05, 0.04, 0.13); P_FL = vec3(0.12, 0.06, 0.25);
    P_1 = vec3(1.00, 0.22, 0.56); P_2 = vec3(1.00, 0.90, 0.20); P_3 = vec3(0.08, 0.80, 0.95);
    P_PAT = vec3(0.30, 0.08, 0.62); P_LIMB = vec3(0.98, 0.95, 0.88);
  } else if (i < 4.5) { // two-strip technicolor: orange-red and sea green on peach
    P_BG = vec3(0.94, 0.75, 0.56); P_FL = vec3(0.80, 0.56, 0.44);
    P_1 = vec3(0.90, 0.33, 0.20); P_2 = vec3(0.36, 0.68, 0.62); P_3 = vec3(0.42, 0.22, 0.18);
    P_PAT = vec3(0.99, 0.89, 0.72); P_LIMB = INK;
  } else if (i < 5.5) { // hellfire: orange and gold on oxblood
    P_BG = vec3(0.22, 0.03, 0.04); P_FL = vec3(0.38, 0.06, 0.05);
    P_1 = vec3(0.97, 0.38, 0.10); P_2 = vec3(1.00, 0.80, 0.26); P_3 = vec3(0.98, 0.88, 0.70);
    P_PAT = vec3(0.24, 0.02, 0.03); P_LIMB = vec3(1.00, 0.84, 0.40);
  } else if (i < 6.5) { // seaside: coral, butter and navy on a sky blue
    P_BG = vec3(0.60, 0.83, 0.88); P_FL = vec3(0.44, 0.68, 0.80);
    P_1 = vec3(0.98, 0.50, 0.46); P_2 = vec3(1.00, 0.88, 0.54); P_3 = vec3(0.18, 0.28, 0.55);
    P_PAT = vec3(0.99, 0.97, 0.92); P_LIMB = INK;
  } else {              // acid: lime, pink and blue on a swamp green
    P_BG = vec3(0.04, 0.10, 0.07); P_FL = vec3(0.07, 0.20, 0.11);
    P_1 = vec3(0.72, 0.96, 0.12); P_2 = vec3(1.00, 0.40, 0.72); P_3 = vec3(0.20, 0.55, 1.00);
    P_PAT = vec3(0.05, 0.13, 0.08); P_LIMB = vec3(0.98, 0.95, 0.88);
  }
}

vec3 grade(vec3 c, float H) {
  c = hueRot(c, H);
  return mix(vec3(dot(c, vec3(0.30, 0.55, 0.15))), c, p_sat);
}

// ---------------------------------------------------------------- the picture
vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> the bounce, squash, eyes, mouths
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> the noodle, fingers, blinks
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> the fills swell, the cast, faces

  float bb = barBeat();
  float H = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  palette(floor(p_palette + 0.5));
  float bgk = 0.30 + 1.40 * p_bg;
  P_BG = grade(P_BG, H) * bgk; P_FL = grade(P_FL, H) * bgk;
  P_1 = grade(P_1, H); P_2 = grade(P_2, H); P_3 = grade(P_3, H);
  P_PAT = grade(P_PAT, H); P_LIMB = grade(P_LIMB, H);
  P_MOUTH = grade(MOUTH, H); P_TONGUE = grade(TONGUE, H);

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  // Off the axis by a hair: atan(0, x) comes back on the wrong side of the cut on some GPUs,
  // which draws a hard line straight through the middle of the tunnel.
  p.y = -p.y + 1.3e-5;
  float WX = max(u_aspect, 0.55) * 0.5;

  // Boil: the drawing re-inked four times a beat.
  float bt = floor(u_beat * 4.0);
  vec2 bph = vec2(hash(vec2(bt, 1.7)), hash(vec2(bt, 9.1))) * TAU;

  gPx = u_px * 0.75;
  gInk = 0.0;
  gTop = 1.0;
  gShade = 0.0;
  float count = clamp(floor(p_cast + 0.5), 1.0, 8.0);

  // ---- where the cast stands: c is the cast's own space, in cells
  vec2 c;
  float ci, cj, fade = 1.0, wedge;
  float S = 1.0, halfW = 0.6;
  if (p_layout < 0.5) {
    // A stage: a row of them along a floor, and a rosette on the wall behind.
    count = min(count, max(1.0, floor(u_aspect * 2.9)));
    float cw = 2.0 * WX / count;
    ci = clamp(floor((p.x + WX) / cw), 0.0, count - 1.0);
    cj = 0.0;
    S = p_size * min(cw * 1.02, 0.80);
    float floorY = -0.34;
    c = (vec2(p.x + WX - (ci + 0.5) * cw, p.y - floorY) - vec2(0.0, 0.5 * S)) / max(S, 1e-4);
    gS = max(S, 1e-4);
    halfW = 0.5 * cw / gS;
    // The wall is a title card: rays turning slowly out of a ring, the way the old shorts opened.
    vec2 wp = p - vec2(0.0, 0.06);
    float kseg = TAU / 16.0;
    float ka = atan(wp.y, wp.x) + u_beat * (p_spin * TAU + 0.02 * B);
    wedge = mod(floor(ka / kseg), 2.0);
    float wr = length(wp);
    float disc = 1.0 - smoothstep(0.30 - gPx, 0.30 + gPx, wr);
    gCol = mix(P_BG, P_FL, p_rosette * 0.5 * wedge * (1.0 - disc));
    gCol = mix(gCol, mix(P_BG, P_2, 0.28), p_rosette * disc);
    gCol = mix(gCol, INK, (1.0 - smoothstep(0.0, gPx * 2.0 + 0.004, abs(wr - 0.30))) * p_rosette);
    gCol *= 1.0 - 0.35 * smoothstep(0.3, 1.1, wr);
    if (p.y < floorY) gCol = P_FL * (1.0 - 0.12 * p_rosette * mod(floor(p.x * 7.0), 2.0)) * (1.0 - 0.3 * (floorY - p.y) / 0.3);
    gCol = mix(gCol, INK, 1.0 - smoothstep(0.0, gPx * 2.0 + 0.0035, abs(p.y - floorY)));
  } else {
    // A tunnel: log(r) against the angle, repeated on both. Square cells in that space keep
    // every character the same shape at every depth, and the scale is exactly r.
    count = max(3.0, count);
    float seg = TAU / count;
    float r = max(length(p), 1e-5);
    float a = mod(atan(p.y, p.x) + u_beat * p_spin * TAU + TAU, TAU);
    float lr = log(r) + u_beat * p_zoom * seg + 0.05 * A;
    cj = floor(lr / seg);
    ci = floor(a / seg);
    vec2 cell = vec2(a - (ci + 0.5) * seg, lr - (cj + 0.5) * seg) / seg;   // -0.5..0.5
    float sz = max(p_size, 0.05);
    c = cell / sz;
    halfW = 0.5 / sz;
    gS = seg * sz * r;
    // Each ring is a floor under the feet and a wall behind, and the wedges alternate.
    wedge = mod(ci, 2.0);
    float floorC = -0.5 * sz;
    gCol = mix(P_BG, P_FL, p_rosette * 0.45 * wedge);
    if (cell.y < floorC) gCol = mix(P_FL, P_BG, p_rosette * 0.3 * wedge) * 1.12;
    gCol = mix(gCol, INK, 1.0 - smoothstep(0.0, gPx * 2.0 + 0.004 * r, abs(cell.y - floorC) * seg * r));
    // The inkwell in the middle: a pool of ink the cast climbs out of, and a haze of ink as
    // the rings go down to it, which also takes them out before they are specks.
    float rH = max(0.035, 16.0 * u_px / seg);
    fade = smoothstep(rH * 1.05, rH * 2.6, r);
    if (r < rH * 1.2) {
      float edge = rH * (1.0 + 0.04 * sin(atan(p.y, p.x) * 7.0 + bph.x));
      vec3 pool = mix(INK, vec3(0.20, 0.18, 0.26), 0.6 * smoothstep(rH * 0.9, rH * 0.2, length(p - vec2(-0.3, 0.3) * rH)));
      return mix(mix(P_BG * 0.2, INK, 0.8), pool, 1.0 - smoothstep(edge - gPx, edge + gPx, r));
    }
  }
  vec3 bgCol = gCol;
  bgCol = hueRot(bgCol, p_kal * (wedge - 0.5));
  gCol = bgCol;

  // Level of detail: how many pixels one cast unit is.
  float cpx = gS / max(u_px, 1e-6);
  float detail = step(70.0, cpx);

  // Shadow on the floor, under the feet, before anything is drawn.
  float shd = sdEll(c - vec2(0.0, -0.50), vec2(0.30, 0.035));
  gCol = mix(gCol, gCol * 0.55, (1.0 - smoothstep(-0.01, 0.01, shd)) * fade);
  bgCol = gCol;

  // Nothing of the cast reaches past this; below a trace of a cell it is not drawn at all.
  if (fade > 0.01 && abs(c.x) < 0.70 && c.y > -0.62 && c.y < 0.66) {
    float turn = floor(bb / max(p_swap * 4.0, 1.0)) + floor(C * 3.0);
    float which = mod(turn + ci * 5.0 + cj * 7.0, 12.0);
    float cell = ci * 7.0 + cj * 13.0;

    // The boil: a wobble of the drawing and of the pen's weight, re-rolled four times a beat.
    c += p_boil * 0.014 * vec2(sin(c.y * 9.0 + bph.x), sin(c.x * 8.0 + bph.y));
    gLw = clamp(0.012 * p_ink * gS, u_px * 0.9, 0.022)
        * (1.0 + p_boil * 0.35 * sin(dot(c, vec2(13.0, 7.0)) + bph.y));

    anchors(which);
    // The bounce. Feet stay on the floor; the body bobs over them, squashing wide on the
    // landing (on the beat, harder on a loud kick) and stretching tall on the way up.
    float L = max(loopBeats(p_aloop), 0.5);
    float s = fract(bb / L);
    float air = sin(PI * s);
    float land = exp(-10.0 * s);
    float bob = p_bounce * (0.035 + 0.05 * A) * air + (1.0 - gLegs) * 0.04 * sin(TAU * bb / 4.0);
    float sy = 1.0 + p_bounce * (0.08 * air * (1.0 - air) * 3.0 - (0.06 + 0.26 * A) * land);
    float sx = 1.0 / sy;
    // The dance: a rock from the hips and a shimmy across, each cell a step behind the last.
    float lag = ci * 0.17 + cj * 0.29;
    float dph = TAU * (bb / (2.0 * L) - lag);
    float lookT = p_dance * 0.5 * sin(dph + 1.1);
    float ra = p_dance * 0.14 * sin(dph);
    float ox = p_dance * 0.05 * sin(dph * 0.5);
    sx *= max(0.6, cos(lookT * 0.8));
    vec2 P0 = vec2(0.0, gHip.y);
    vec2 q = P0 + (rot(-ra) * (c - P0 - vec2(ox, bob))) / vec2(sx, sy);
    gLim = max(0.30, (halfW - abs(ox) - 0.04) / sx - 0.18);

    // Who has what, decided per cell.
    float faceAmt = clamp(p_face + C * p_facec, 0.0, 1.0);
    float hasEye = step(hash(vec2(cell, 21.0)), p_faceodds * faceAmt * 1.0001) * step(0.02, faceAmt);
    float hasMouth = hasEye * step(hash(vec2(cell, 47.0)), 0.85) * gMouthOK;
    float hasLimbs = step(hash(vec2(cell, 31.0)), p_limbs * 1.0001) * step(0.02, p_limbs) * step(28.0, cpx);
    float hasProp = step(hash(vec2(cell, 83.0)), p_propodds) * step(0.02, p_prop) * detail;

    // Three fills per cell, the same three inks in an order of its own (Spread says how often
    // the order is shuffled), and a pattern whose second colour swells in on the chords.
    float rr = hash(vec2(cell, 11.0));
    float ro = rr < p_spread ? floor(hash(vec2(cell, 3.0)) * 2.999) : 0.0;
    gC1 = ro < 0.5 ? P_1 : ro < 1.5 ? P_2 : P_3;
    gC2 = ro < 0.5 ? P_2 : ro < 1.5 ? P_3 : P_1;
    gC3 = ro < 0.5 ? P_3 : ro < 1.5 ? P_1 : P_2;
    gAlt = mix(P_PAT, gC2, clamp(1.6 * C, 0.0, 0.85));
    gFill = clamp(p_pat * (0.55 + 1.3 * C), 0.0, 1.0);
    gPat = gFill > 0.004 ? patternAt(q, u_beat * p_patspin, p_patscale * (1.0 + 0.6 * C)) : 0.0;
    gNoodle = p_noodle * 0.05 * sin(u_beat * PI * 0.5 + ci * 1.3 + cj) * (0.5 + 2.0 * B);

    // Halftone shading, light from the upper left.
    if (p_shade > 0.01 && detail > 0.5) {
      gShade = p_shade * 0.42;
      vec2 hg = rot(0.26) * p / max(u_px * 7.0, 0.004);
      gDot = length(fract(hg) - 0.5) * 1.6;
      gSide = smoothstep(-0.25, 0.35, q.x - q.y - 0.05);
    }

    // ---- legs, in the cast's space: from the hips (wherever the bob has put them) down to
    // shoes planted on the floor, bowing out like rubber as the body comes down on them.
    if (gLegs * hasLimbs > 0.5 && c.y < gHip.y * sy + bob + 0.1) {
      for (int i = 0; i < 2; i++) {
        float sd = float(i) * 2.0 - 1.0;
        vec2 hip = P0 + vec2(ox, bob) + rot(ra) * vec2(sd * gHip.x * sx, 0.0);
        float tap = p_dance * 0.05 * max(0.0, sin(TAU * bb / L)) * step(0.5, mod(floor(bb / L) + float(i), 2.0));
        vec2 foot = vec2(sd * (0.16 + 0.02 * p_dance), -0.44 + tap);
        float len = length(hip - foot);
        vec2 ctrl = (hip + foot) * 0.5 + vec2(sd * (0.02 + 1.4 * max(0.0, 0.26 - len)) + gNoodle, 0.0);
        D(hose(c, hip, ctrl, foot, 0.022), P_LIMB);
        D(sdEll(c - foot - vec2(sd * 0.04, -0.015), vec2(0.095, 0.050)), mix(gC3, INK, 0.55));
        if (detail > 0.5) D(sdEll(c - foot - vec2(sd * 0.075, 0.005), vec2(0.022, 0.012)), GLOVE);
      }
    }

    // ---- the body, the face, the arms, the business
    gHands = 1.0 - hasEye;
    body(q, which, A, B);
    if (hasEye > 0.5 && cpx > 20.0) {
      vec2 look = vec2(clamp(lookT * 1.6, -1.0, 1.0), 0.3 * sin(u_beat * 0.37 + cell));
      float e8 = floor(u_beat * 2.0);
      float blink = step(hash(vec2(cell, e8)), 0.05 + 0.30 * B) * step(fract(u_beat * 2.0), 0.35);
      if (detail < 0.5) blink = 0.0;
      face(q, A, blink, look, hasMouth, detail);
    }
    if (hasLimbs > 0.5) {
      // Arm poses, re-picked every four bars: the charleston (alternating), hands in the air
      // waving, or a swing with the elbows out.
      float pose = floor(hash(vec2(cell, 61.0 + floor(bb / 16.0))) * 2.999);
      float sw = sin(dph * 2.0);
      float aR, aL, bend;
      if (pose < 0.5)      { aR = mix(-1.2, 0.9, 0.5 + 0.5 * sw); aL = PI - mix(-1.2, 0.9, 0.5 - 0.5 * sw); bend = 0.45; }
      else if (pose < 1.5) { aR = 1.05 + 0.35 * sw; aL = PI - 1.05 + 0.35 * sw; bend = -0.40; }
      else                 { aR = -0.35 + 0.55 * sw; aL = PI + 0.35 + 0.55 * sw; bend = 0.60; }
      float wig = 0.30 * B * sin(u_beat * TAU * 2.0) + 0.15 * sin(u_beat * 3.0 + cell);
      arm(q, gSh, aR, bend + gNoodle * 4.0, 1.0, wig, detail);
      arm(q, vec2(-gSh.x, gSh.y), aL, -bend + gNoodle * 4.0, -1.0, wig, detail);
    }
    if (hasProp > 0.5) props(q, which, A, fract(u_beat * 0.5 + hash(vec2(cell, 5.0))));
  }

  // Halftone: a printed dot screen fixed to the surface, coming in towards the edge of every
  // shape on the side away from the light.
  if (gShade > 0.0) {
    float rim = clamp(1.0 + gTop / (0.16 * gS), 0.0, 1.0) * gSide * step(gTop, 0.0);
    gCol *= 1.0 - gShade * smoothstep(rim * 0.95 + 0.12, rim * 0.95 - 0.12, gDot);
  }
  vec3 col = mix(gCol, INK, clamp(gInk, 0.0, 1.0));
  col = mix(bgCol, col, fade);
  if (p_layout > 0.5) col = mix(INK, col, 0.35 + 0.65 * fade);
  // Film: grain, a flicker, the odd scratch, and the edge of the gate.
  col *= 1.0 + p_film * (0.10 * hash(p * 620.0 + u_time * 41.0) - 0.05
                         + 0.05 * (hash(vec2(floor(u_beat * 8.0), 4.0)) - 0.5));
  col = mix(col, GLOVE, step(0.9993, hash(vec2(floor(p.x * 260.0), floor(u_beat * 6.0)))) * 0.45 * p_film);
  col *= 1.0 - 0.35 * p_film * pow(clamp(length(p * vec2(0.80, 1.25)), 0.0, 1.0), 3.0);
  return col;
}
