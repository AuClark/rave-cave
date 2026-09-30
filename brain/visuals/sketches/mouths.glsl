// Mouths: one huge cartoon mouth filling the wall, acting its heart out to the music.
//
// It is a rig, not a set of drawings. The mouth is four curves across its width -- the inner and
// outer edge of each lip -- worked out from a short vector of controls: how open, how wide, each
// corner's height on its own (which is what makes a smirk or a sinister grin lopsided), a sneer
// on either side of the upper lip, the lower lip's pout, how boxy or round the opening is, how
// much of the upper and lower teeth and gums show, clenched or apart, the tongue, lip thickness,
// a nervous wobble, a lip bite. Each emotion is one keyframe of that vector (emoKey), and the
// mouth morphs from one to the next on the bar with a spring's overshoot and a stretch while it
// moves, so a change is a cartoon take, never a cut.
//
// Fourteen of them: a big toothy grin, a smirk, a Cheshire-wide sinister grin, a yell, a belly
// laugh, a gasp, a grimace, a pout, tongue out, a lip bite, a snarl over one canine, belting, the
// anime nervous wobble, and BASS FACE: lips pushed out, a sneer on both sides pulling up to the
// nose, the bottom lip caught under the top teeth. Heavy sustained low end, and above all the
// drop, pulls the mouth into bass face whatever it was doing, and lets it go again.
//
// It dances: the jaw pumps on the kick, the opening follows the mids like a singer, the hats flick
// quick consonant shapes (M, F, O, E) through it, and the whole mouth bobs, sways and squashes.
//
// Styles (kind fixed): 0 anime -- clean line, one hard shadow step, a glossy lip, a cute fang, speed
// lines, sweat and an anger mark; 1 cartoon -- thick ink with weight, flat colour, rubber hose;
// 2 detailed -- shaded teeth with enamel and gaps, gums, a wet grooved tongue, saliva strings, lip
// creases, a deep throat; 3 pop art -- Lichtenstein red and black with Ben-Day dots.
//
// Drivers (docs/reactive.md): A Hit -> the jaw pump, the bob and the squash; B Move -> the
// consonant flicks and the sway; C Change -> how exaggerated it all is and the background swell.
// Params are p_* uniforms; ranges and defaults are in mouths.json.
uniform float p_size, p_exag, p_elastic, p_face, p_fang, p_tword,
              p_change, p_emo, p_mood, p_bass, p_drop,
              p_pump, p_sync, p_talk, p_bob,
              p_style, p_ink, p_gloss, p_spit,
              p_bg, p_busy,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_sat, p_follow, p_tint;

#define TAU 6.2831853
#define PI 3.1415927

// ---------------------------------------------------------------- the emotions
// Six vec4s per emotion:
//   A open, width, left corner, right corner       B share of the opening above the line, boxiness
//                                                    (low = boxy, 0.5 round), sneer left, sneer right
//   C top teeth, bottom teeth, gums, clench        D tongue out, tongue height, lip thickness, pout
//   E wobble, lip bite, cheek push, menace          F laugh shake, tremble, sweat, anger
const vec4 BA = vec4(0.10, 0.78, -0.32, -0.20), BB = vec4(0.60, 0.50, 0.08, 0.34),
           BC = vec4(1.00, 0.00, 0.08, 0.00),   BD = vec4(0.00, 0.00, 1.40, 1.00),
           BE = vec4(0.00, 0.80, 1.00, 0.10),   BF = vec4(0.00, 0.00, 0.00, 0.30);

void emoKey(float i, out vec4 a, out vec4 b, out vec4 c, out vec4 d, out vec4 e, out vec4 f) {
  if (i < 0.5) {         // 0 big gaping smile
    a = vec4(0.85, 1.12, 0.44, 0.44); b = vec4(0.16, 0.60, 0.0, 0.0); c = vec4(1.0, 0.45, 0.35, 0.0);
    d = vec4(0.0, 0.50, 0.80, 0.0); e = vec4(0.0, 0.0, 1.0, 0.0); f = vec4(0.0);
  } else if (i < 1.5) {  // 1 smirk
    a = vec4(0.10, 0.92, -0.10, 0.52); b = vec4(0.62, 0.60, 0.0, 0.14); c = vec4(0.35, 0.0, 0.0, 0.4);
    d = vec4(0.0, 0.30, 1.0, 0.10); e = vec4(0.0, 0.0, 0.7, 0.0); f = vec4(0.0);
  } else if (i < 2.5) {  // 2 sinister grin
    a = vec4(0.30, 1.34, 0.56, 0.56); b = vec4(0.45, 0.30, 0.0, 0.0); c = vec4(1.0, 1.0, 0.0, 1.0);
    d = vec4(0.0, 0.20, 0.45, 0.0); e = vec4(0.0, 0.0, 0.9, 1.0); f = vec4(0.0, 0.15, 0.0, 0.0);
  } else if (i < 3.5) {  // 3 yell
    a = vec4(1.25, 0.86, -0.12, -0.12); b = vec4(0.30, 0.38, 0.12, 0.12); c = vec4(0.55, 0.45, 0.2, 0.0);
    d = vec4(0.0, 0.12, 1.0, 0.0); e = vec4(0.0, 0.0, 0.5, 0.0); f = vec4(0.0, 0.4, 0.0, 0.8);
  } else if (i < 4.5) {  // 4 belly laugh
    a = vec4(1.10, 1.02, 0.30, 0.30); b = vec4(0.34, 0.45, 0.0, 0.0); c = vec4(1.0, 0.25, 0.55, 0.0);
    d = vec4(0.0, 0.65, 0.90, 0.0); e = vec4(0.0, 0.0, 1.0, 0.0); f = vec4(1.0, 0.0, 0.0, 0.0);
  } else if (i < 5.5) {  // 5 shocked gasp
    a = vec4(0.72, 0.40, -0.04, -0.04); b = vec4(0.45, 0.50, 0.0, 0.0); c = vec4(0.25, 0.12, 0.0, 0.0);
    d = vec4(0.0, 0.20, 1.25, 0.35); e = vec4(0.0); f = vec4(0.0, 0.35, 0.5, 0.0);
  } else if (i < 6.5) {  // 6 grimace
    a = vec4(0.32, 1.16, -0.30, -0.24); b = vec4(0.50, 0.28, 0.06, 0.06); c = vec4(1.0, 1.0, 0.55, 1.0);
    d = vec4(0.0, 0.0, 0.70, 0.0); e = vec4(0.18, 0.0, 0.7, 0.2); f = vec4(0.0, 0.7, 0.6, 0.4);
  } else if (i < 7.5) {  // 7 pout
    a = vec4(0.0, 0.52, -0.14, -0.12); b = vec4(0.50, 0.60, 0.0, 0.0); c = vec4(0.0);
    d = vec4(0.0, 0.0, 1.35, 1.0); e = vec4(0.0); f = vec4(0.0);
  } else if (i < 8.5) {  // 8 tongue out
    a = vec4(0.30, 0.90, 0.16, 0.12); b = vec4(0.60, 0.50, 0.0, 0.0); c = vec4(0.45, 0.0, 0.0, 0.0);
    d = vec4(1.0, 0.50, 1.0, 0.0); e = vec4(0.0, 0.0, 0.4, 0.0); f = vec4(0.4, 0.0, 0.0, 0.0);
  } else if (i < 9.5) {  // 9 lip bite
    a = vec4(0.08, 0.95, 0.20, 0.00); b = vec4(0.55, 0.60, 0.0, 0.04); c = vec4(0.9, 0.0, 0.0, 0.0);
    d = vec4(0.0, 0.0, 1.10, 0.20); e = vec4(0.0, 1.0, 0.45, 0.0); f = vec4(0.0, 0.3, 0.0, 0.0);
  } else if (i < 10.5) { // 10 snarl
    a = vec4(0.30, 0.96, -0.10, 0.02); b = vec4(0.62, 0.45, 0.05, 0.40); c = vec4(0.85, 0.5, 0.55, 0.8);
    d = vec4(0.0, 0.0, 0.90, 0.0); e = vec4(0.0, 0.0, 0.8, 0.4); f = vec4(0.0, 0.5, 0.0, 1.0);
  } else if (i < 11.5) { // 11 singing, belting
    a = vec4(0.95, 0.68, 0.06, 0.06); b = vec4(0.40, 0.55, 0.0, 0.0); c = vec4(0.6, 0.2, 0.1, 0.0);
    d = vec4(0.0, 0.35, 1.10, 0.0); e = vec4(0.0, 0.0, 0.3, 0.0); f = vec4(0.0, 0.3, 0.0, 0.0);
  } else if (i < 12.5) { // 12 nervous wobble
    a = vec4(0.14, 0.85, -0.04, 0.02); b = vec4(0.50, 0.60, 0.0, 0.0); c = vec4(0.4, 0.25, 0.0, 0.8);
    d = vec4(0.0, 0.0, 0.80, 0.0); e = vec4(1.0, 0.0, 0.0, 0.0); f = vec4(0.0, 0.8, 1.0, 0.0);
  } else {               // 13 bass face
    a = BA; b = BB; c = BC; d = BD; e = BE; f = BF;
  }
}

vec4 oneHot(float k) { return max(1.0 - abs(vec4(0.0, 1.0, 2.0, 3.0) - k), 0.0); }

// Which emotion is up for period n. A mood is a list of emotions to draw from; stepping through it
// by the golden ratio moves one or two places each time, so it never repeats itself back to back.
float pickEmo(float n) {
  float m = floor(p_mood + 0.5);
  float g = floor(n * 1.618 + 0.4);
  if (m < 0.5) return mod(g * 5.0, 13.0);                                  // everything but bass face
  vec4 s0, s1; float cnt;
  if (m < 1.5)      { s0 = vec4(0.0, 4.0, 8.0, 11.0);  s1 = vec4(1.0, 0.0, 0.0, 0.0);  cnt = 5.0; }  // happy
  else if (m < 2.5) { s0 = vec4(10.0, 6.0, 3.0, 2.0);  s1 = vec4(13.0, 9.0, 0.0, 0.0); cnt = 6.0; }  // gremlin
  else if (m < 3.5) { s0 = vec4(1.0, 8.0, 9.0, 7.0);   s1 = vec4(2.0, 0.0, 0.0, 0.0);  cnt = 6.0; }  // cheeky
  else if (m < 4.5) { s0 = vec4(11.0, 5.0, 11.0, 0.0); s1 = vec4(11.0, 3.0, 7.0, 0.0); cnt = 7.0; }  // diva
  else if (m < 5.5) { s0 = vec4(12.0, 5.0, 3.0, 4.0);  s1 = vec4(8.0, 0.0, 6.0, 0.0);  cnt = 7.0; }  // anime chaos
  else if (m < 6.5) { s0 = vec4(2.0, 1.0, 2.0, 10.0);  s1 = vec4(2.0, 9.0, 0.0, 0.0);  cnt = 6.0; }  // sinister
  else              { s0 = vec4(13.0, 10.0, 13.0, 6.0); s1 = vec4(13.0, 2.0, 0.0, 0.0); cnt = 6.0; } // stank
  float k = mod(g, cnt);
  return dot(s0, oneHot(k)) + dot(s1, oneHot(k - 4.0));
}

// ---------------------------------------------------------------- the lip curves
// The rig, after the morph. x is across the mouth in mouth units (half width about 1).
float gSn, gW, gOpen, gCL, gCR, gUp, gK, gSL, gSR, gTh, gPout, gWav, gWph, gBite;

// The inner and outer edge of each lip at x: (upper inner, lower inner, upper outer, lower outer).
vec4 lips(float x) {
  float s = x / gW, s2 = s * s;
  float e0 = max(1.0 - s2, 0.0) + 1e-5;
  float pin = max(1.0 - (1.0 - abs(s)) * 3.0, 0.0);
  float env = pow(e0, gK) * (1.0 - pin * pin), se = sqrt(e0);
  float cor = mix(gCL, gCR, clamp(0.5 + 0.5 * s, 0.0, 1.0)) * min(s2, 1.0);
  float wv = gWav * 0.07 * sin(s * 11.0 + gWph) * se;
  float zl = s + 0.52, zr = s - 0.52;
  float sn = (gSL * exp(-zl * zl * 10.0) + gSR * exp(-zr * zr * 10.0)) * se;
  gSn = sn;
  float yu = cor + gOpen * gUp * env + sn + wv;
  float yl = cor - gOpen * (1.0 - gUp) * env + wv * 0.6;
  float bs = abs(s) - 0.2;
  float bow = 1.0 - 0.3 * exp(-s2 * 80.0) + 0.2 * exp(-bs * bs * 60.0);    // the Cupid's bow
  float pk = 1.0 - pin * pin * 0.7;                       // lips come to a point at the corners
  // Lip thickness: full in the middle, thinning to the corners -- but meeting them at an angle,
  // not straight up (a sqrt does that), or the outline has no true distance there and spikes.
  float fe = e0 * 1.6 / (e0 + 0.6);
  float tU = gTh * 0.15 * fe * bow * pk;
  float tL = gTh * (0.19 + 0.1 * gPout) * fe * pk * (1.0 - 0.5 * gBite * exp(-s2 * 3.0));
  return vec4(yu, yl, yu + tU, yl - tL);
}

// Intersection with rounded outside corners, so the corners of the mouth don't come out square.
float isect(float a, float b) { return length(max(vec2(a, b), 0.0)) + min(max(a, b), 0.0); }
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float gLp;                                             // one pixel in mouth units
float fillA(float d) { return 1.0 - smoothstep(-gLp, gLp, d); }
float lineA(float d, float w) { return (1.0 - smoothstep(w - gLp, w + gLp, abs(d))) * clamp(w / gLp, 0.0, 1.0); }

// The mouth is painted surface by surface into a dark and a light colour and a light level, which
// the style then turns into cel steps, flat colour, smooth shading or Ben-Day dots.
vec3 gDk, gLt; float gL;
void surf(float cov, vec3 dk, vec3 lt, float L) {
  gDk = mix(gDk, dk, cov); gLt = mix(gLt, lt, cov); gL = mix(gL, L, cov);
}

vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> jaw pump, bob, squash
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> consonant flicks, sway
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> exaggeration, background swell
  vec4 sw = oneHot(floor(p_style + 0.5));                // anime, cartoon, detailed, pop art
  float bb = barBeat();

  // ------------------------------------------------ which emotion, and the take into it
  float ch = floor(p_change + 0.5);
  float per = ch < 0.5 ? 0.0 : 4.0 * exp2(ch - 1.0);     // 1, 2, 4 or 8 bars
  float from, to, tIn;
  if (per < 0.5) { from = floor(p_emo + 0.5); to = from; tIn = 64.0; }
  else {
    float ba = bb + 0.15;                                 // the take starts a hair before the 1
    float n = floor(ba / per);
    tIn = ba - n * per; to = pickEmo(n); from = pickEmo(n - 1.0);
  }
  float over = 0.02 + 0.3 * p_elastic;                   // the spring: overshoot, then settle
  float kdm = -7.0 * log(over) / PI;
  float ex = exp(-kdm * tIn);
  float ease = 1.0 - ex * cos(7.0 * min(tIn, 3.0));
  float stretch = 0.25 * p_elastic * ex * sin(7.0 * min(tIn, 3.0));
  vec4 ka, kb, kc, kd, ke, kf, la, lb, lc, ld, le, lf;
  emoKey(from, ka, kb, kc, kd, ke, kf);
  emoKey(to, la, lb, lc, ld, le, lf);
  vec4 KA = mix(ka, la, ease), KB = mix(kb, lb, ease), KC = mix(kc, lc, ease),
       KD = mix(kd, ld, ease), KE = mix(ke, le, ease), KF = mix(kf, lf, ease);

  // ------------------------------------------------ bass face: the low end pulls it in
  // The face people pull is for the bass coming back in, so it fires hardest on that: how hard
  // the kick lands now against eight beats ago, and while it stays heavy it eases to a simmer.
  // Read at the beat onsets, because the low band is a flat floor with the kick spiking at each
  // beat and an average over the beat mostly misses it. Measured on a real rekordbox waveform
  // ("Iron Frequency", in the sim): onsets 0.73 through heavy sections, 0.26 in the breakdowns.
  float b0 = floor(u_beat) + 0.06;
  float kNow = max(wave(b0).y, wave(b0 - 1.0).y), kThen = max(wave(b0 - 8.0).y, wave(b0 - 9.0).y);
  float hNow = smoothstep(0.34, 0.46, kNow), hThen = smoothstep(0.34, 0.46, kThen);
  float heavy = min(1.0, 0.4 * hNow + clamp(hNow - hThen, 0.0, 1.0));
  float isDrop = 1.0 - step(0.5, abs(u_scene - 7.0));
  float pre = u_todrop >= 0.0 ? 0.35 * (1.0 - smoothstep(0.0, 2.0, u_todrop)) : 0.0;
  float dropPull = max(pre, isDrop * (0.35 + 0.65 * exp(-u_since / 12.0)));
  float bass = clamp(p_bass * heavy + p_drop * dropPull, 0.0, 1.0);
  bass = smoothstep(0.0, 1.0, bass);
  KA = mix(KA, BA, bass); KB = mix(KB, BB, bass); KC = mix(KC, BC, bass);
  KD = mix(KD, BD, bass); KE = mix(KE, BE, bass); KF = mix(KF, BF, bass);

  // ------------------------------------------------ the rig, then the dancing on top of it
  float exg = p_exag * (1.0 + 0.3 * C);
  gOpen = KA.x * exg; gW = 1.0 + (KA.y - 1.0) * exg; gCL = KA.z * exg; gCR = KA.w * exg;
  gUp = KB.x; gK = KB.y; gSL = KB.z * exg; gSR = KB.w * exg;
  float tt = KC.x, bt = KC.y, gum = KC.z, cln = KC.w;
  float tOut = KD.x, tLv = KD.y; gTh = KD.z; gPout = KD.w;
  gWav = KE.x; gBite = KE.y; float chk = KE.z, men = KE.w;
  float shk = KF.x, trm = KF.y, sweat = KF.z, anger = KF.w;

  float mid = wave(u_beat).z;
  gOpen *= mix(1.0, 0.5 + 1.1 * mid, p_sync);                       // the singer follows the mids
  gOpen *= 1.0 + shk * 0.35 * sin(u_beat * TAU * 2.0);               // ha ha ha, on the 8ths
  float pmp = p_pump * (1.0 - 0.6 * bass);                          // the jaw drops on the kick, closes between
  gOpen = gOpen * (1.0 - 0.45 * pmp + 1.1 * pmp * A) + A * pmp * (0.2 - 0.1 * cln);
  // Consonants, flicked by the hats: M (pressed shut), F (lip under the teeth), O, E.
  float cs = clamp(B * p_talk * 2.6, 0.0, 0.85) * (1.0 - bass);
  float hv = hash(vec2(floor(u_beat * 2.0), 3.7));
  float cm = cs * step(hv, 0.25), cf = cs * step(0.25, hv) * step(hv, 0.5);
  float co = cs * step(0.5, hv) * step(hv, 0.75), ce = cs * step(0.75, hv);
  gOpen *= 1.0 - cm; gTh *= 1.0 + 0.3 * cm;
  gBite = max(gBite, cf); gOpen = mix(gOpen, 0.05, cf); tt = max(tt, cf);
  gW = mix(gW, 0.5, co); gK = mix(gK, 0.5, co); gOpen = mix(gOpen, max(gOpen, 0.6), co); gPout = max(gPout, co * 0.6);
  gW *= 1.0 + 0.15 * ce; gOpen = mix(gOpen, 0.24, ce); tt = max(tt, ce); bt = max(bt, 0.6 * ce);
  gOpen = clamp(gOpen, 0.0, 1.6); gW = clamp(gW, 0.35, 1.42); gSL = min(gSL, 0.45); gSR = min(gSR, 0.45); gTh = max(gTh, 0.3); gK = clamp(gK, 0.2, 1.0);
  gWph = u_beat * PI * 2.0 * (0.5 + gWav) + trm * 3.0 * sin(u_beat * TAU * 3.0);

  // ------------------------------------------------ the head: bob, sway, tilt, squash
  vec2 P = (uv - 0.5) * vec2(u_aspect, 1.0); P.y = -P.y;
  float Sc = min(0.37 * u_aspect, 0.57) * p_size;
  float jit = trm * 0.006 * sin(u_beat * TAU * 6.0 + 1.3);
  vec2 head = vec2(0.035 * p_bob * sin(u_beat * PI) * (0.4 + B) + jit,
                   -0.035 * p_bob * A * (1.0 + 1.5 * bass) - 0.01 * shk * abs(sin(u_beat * TAU)));
  float tilt = 0.05 * p_bob * sin(u_beat * PI * 0.5) + 0.04 * (gCR - gCL);
  vec2 p = rot(tilt) * (P - head);
  vec2 q = p / Sc;
  q.y -= gOpen * (0.5 - gUp) * 0.5 - 0.03;             // keep the jaw's drop in frame
  float sq = 0.1 * p_bob * A * (1.0 + bass) - stretch;  // > 0 squash (wider, shorter)
  q.x /= 1.0 + sq; q.y *= 1.0 + sq;
  gLp = u_px / Sc * 1.2;

  // ------------------------------------------------ colours, per style
  float hue = p_hue + p_follow * u_hue + 0.08 * C;
  vec3 LIP  = sw.x * vec3(0.95, 0.30, 0.42) + sw.y * vec3(0.88, 0.08, 0.14) + sw.z * vec3(0.78, 0.26, 0.30) + sw.w * vec3(0.94, 0.06, 0.10);
  vec3 LIPD = sw.x * vec3(0.70, 0.13, 0.30) + sw.y * vec3(0.58, 0.03, 0.10) + sw.z * vec3(0.40, 0.07, 0.13) + sw.w * vec3(0.30, 0.00, 0.04);
  vec3 LIPT = hsv(hue + 0.5, 0.85, 0.95);
  LIP = mix(LIP, LIPT, p_tint); LIPD = mix(LIPD, LIPT * 0.6, p_tint);
  vec3 MOU  = sw.x * vec3(0.58, 0.10, 0.22) + sw.y * vec3(0.40, 0.04, 0.10) + sw.z * vec3(0.46, 0.08, 0.15) + sw.w * vec3(0.10, 0.02, 0.05);
  vec3 MOUD = sw.x * vec3(0.26, 0.03, 0.14) + sw.y * vec3(0.14, 0.01, 0.05) + sw.z * vec3(0.07, 0.00, 0.03) + sw.w * vec3(0.0);
  vec3 GUM  = sw.x * vec3(0.98, 0.52, 0.60) + sw.y * vec3(0.96, 0.45, 0.50) + sw.z * vec3(0.86, 0.40, 0.44) + sw.w * vec3(1.0, 0.50, 0.58);
  vec3 TTH  = sw.x * vec3(1.0) + sw.y * vec3(1.0, 0.98, 0.92) + sw.z * vec3(0.98, 0.95, 0.85) + sw.w * vec3(1.0);
  vec3 TTHD = sw.x * vec3(0.76, 0.80, 0.96) + sw.y * vec3(0.86, 0.82, 0.74) + sw.z * vec3(0.55, 0.47, 0.33) + sw.w * vec3(0.45, 0.70, 1.0);
  vec3 TNG  = sw.x * vec3(1.0, 0.46, 0.56) + sw.y * vec3(0.98, 0.38, 0.42) + sw.z * vec3(0.90, 0.40, 0.44) + sw.w * vec3(1.0, 0.42, 0.55);
  vec3 TNGD = sw.x * vec3(0.84, 0.24, 0.38) + sw.y * vec3(0.76, 0.18, 0.24) + sw.z * vec3(0.50, 0.12, 0.20) + sw.w * vec3(0.85, 0.05, 0.18);
  vec3 INK  = sw.x * vec3(0.16, 0.05, 0.12) + sw.y * vec3(0.02) + sw.z * vec3(0.16, 0.04, 0.06) + sw.w * vec3(0.0);

  // ------------------------------------------------ the curves here, and their slopes
  float h = 0.004;
  vec4 c0 = lips(q.x), c1 = lips(q.x + h);
  // Centred, and clamped loosely: the lips rise almost vertically out of the corners, and a tight
  // clamp there overstates the distance, thinning the outline to a hairline spike.
  vec4 cLo = lips(q.x - h);
  vec4 sl = clamp((c1 - cLo) / (2.0 * h), -40.0, 40.0);
  vec4 D = (q.y - c0) * inversesqrt(1.0 + sl * sl);     // signed distance to each curve (+ above)
  float s = q.x / gW, s2 = s * s;
  float e0v = max(1.0 - s2, 0.0), se = sqrt(e0v);
  float xb = abs(q.x) - gW;
  float dSil = isect(max(D.z, -D.w), xb);                  // the whole mouth
  float dIn  = isect(max(D.x, -D.y), xb);                  // the opening
  float dUL  = max(D.z, -D.x), dLL = max(D.y, -D.w);     // each lip
  float yu = c0.x, yl = c0.y;
  float yu0 = gOpen * gUp, yl0 = -gOpen * (1.0 - gUp), ym = mix(yl, yu, 0.5);
  float inO = fillA(dIn);

  gDk = MOUD; gLt = MOU; gL = 0.0;
  float obj = fillA(dSil);

  // Inside: the roof lighter, the throat falling away into the dark, the uvula hanging at the back.
  float depth = clamp(-dIn / (0.12 + 0.25 * gOpen), 0.0, 1.0);
  float roof = smoothstep(ym - 0.1, ym + 0.2, q.y);
  surf(inO, MOUD, MOU, (1.0 - depth) * 0.8 + 0.25 * roof);
  float thr = length((q - vec2(0.0, ym - 0.06 * gOpen)) / vec2(0.34 * gW, 0.42 * gOpen + 0.01)) - 1.0;
  float thrOn = smoothstep(0.35, 0.7, gOpen);
  surf(inO * fillA(thr * 0.2) * thrOn, MOUD * 0.35, MOUD * 0.6, 0.0);
  float uvY = yu0 - 0.2 - 0.14 * gOpen;
  vec2 uq = q - vec2(0.0, uvY);
  float uvu = length(uq / vec2(0.055, 0.1)) - 1.0;
  uvu = min(uvu, sdSeg(q, vec2(0.0, uvY), vec2(0.0, yu0)) / 0.03 - 1.0);
  float uvOn = inO * thrOn * fillA(uvu * 0.04);
  surf(uvOn, TNGD, TNG, 0.6 - 0.5 * (uq.y + 0.1) * 3.0);

  // The tongue: a mound on the floor of the mouth, grooved down the middle.
  float Ht = gOpen * (1.0 - gUp) * (0.3 + 1.1 * tLv);
  float st = s / 0.78;
  float yt = yl + Ht * max(1.0 - st * st, 0.0) - 0.02;
  float dT = (q.y - yt) / sqrt(1.0 + 4.0 * Ht * Ht);
  float tongIn = inO * fillA(dT);
  float tLight = clamp(0.35 + 2.5 * (q.y - yl) - 0.5 * abs(s), 0.0, 1.0);
  surf(tongIn, TNGD, TNG, tLight);

  // The teeth, cut into individual teeth. Upper row hangs from the gums under the upper lip.
  float gumH = gum * 0.10 * pow(e0v + 1e-4, 0.3);
  float ytop = yu - gSn - gumH;              // a sneer lifts the lip off the gum, not the teeth
  float N = mix(4.2, 8.5, men);
  float u = sign(s) * pow(abs(s) + 1e-4, 1.18) * N;
  float tid = floor(u), tf = fract(u);
  float dudx = N * 1.18 * pow(abs(s) + 0.03, 0.18) / gW;
  float edge = abs(tf - 0.5);                            // 0 at a tooth's middle, 0.5 at a gap
  float tl = tt * 0.27 * (1.0 - 0.45 * s2) * (0.92 + 0.16 * hash(vec2(tid, 1.0)) * sw.z);
  float canine = step(abs(abs(tid + 0.5) - 2.5), 0.1); // the third tooth out from the middle
  float point = max(men * 0.45, canine * (0.5 + 0.5 * KB.z + 0.5 * KB.w)) * (1.0 - 2.0 * edge);
  float round_ = 0.035 * (1.0 - sqrt(max(1.0 - 4.0 * edge * edge, 0.0)));
  // Tapers off gradually round the curve: a sqrt stayed deep to the end, then the teeth stopped in a wall.
  float bite = gBite * 0.2 * smoothstep(0.78, 0.15, abs(s));
  // A single cute fang: the right canine grown long and sharp. It is one of the teeth, not a shape
  // laid over them, so it keeps their outline and gaps and never sits on top of anything.
  // Tucked away in a bite, where it only notches the edge of the teeth on the lip.
  float fangT = step(abs(tid - 2.0), 0.1) * step(0.02, p_fang) * smoothstep(0.02, 0.12, tt + cln) * (1.0 - smoothstep(0.0, 0.04, bite));
  float fext = fangT * p_fang * (0.03 + 0.22 * tl) * pow(max(1.0 - 2.0 * edge, 0.0), 1.4);
  float ybt = mix(ytop - tl, ym, cln) - 0.06 * point * tt + round_ - fext;
  ybt = min(ybt, ytop - 0.001);
  float gapD = (0.5 - edge) / dudx;                      // distance to the nearest gap
  float gapW = 0.006 + 0.01 * sw.z;
  float scal = 0.025 * (1.0 - sqrt(max(1.0 - 4.0 * edge * edge, 0.0)));
  float dTU = max(q.y - (ytop - scal), ybt - q.y);
  float dBite = max(max(dTU, yl - bite - fext - q.y), q.y - yl - 0.01);   // the top teeth biting down over the lower lip
  float onLip = fillA(dLL) * step(0.001, bite + fext);
  // Summed, not max: the two halves meet at the lip edge, where max leaves a seam of lip showing.
  float upT = min(fillA(dTU) * inO + fillA(dBite) * onLip, 1.0) * step(0.02, tt + cln);
  float gumOn = inO * step(ytop - scal - 0.004, q.y) * step(0.001, gumH + gSn);
  surf(gumOn, GUM * 0.7, GUM, clamp(0.4 + 6.0 * (q.y - ytop), 0.0, 1.0));

  // Lower row stands up from the lower lip.
  float Nb = N * 1.2;
  float ub = sign(s) * pow(abs(s) + 1e-4, 1.18) * Nb;
  float edb = abs(fract(ub) - 0.5);
  float tlb = bt * 0.2 * (1.0 - 0.6 * s2);
  float ybase = yl + gum * 0.04 * se;
  float ytb = mix(ybase + tlb, ym, cln) - 0.025 * (1.0 - sqrt(max(1.0 - 4.0 * edb * edb, 0.0))) + 0.0 * men;
  float dTL = max(q.y - ytb, ybase - q.y);
  float loT = inO * fillA(dTL) * step(0.02, bt + cln);
  float gapDb = (0.5 - edb) / (dudx * 1.2);
  float tShade = (0.55 + 0.45 * (1.0 - 4.0 * edb * edb)) * (1.0 - 0.4 * s2);
  surf(loT, TTHD, TTH, tShade * (0.5 + 0.5 * smoothstep(ybase, ytb, q.y)) + 0.1);

  // The lower lip, then the tongue stuck out over it, then the top teeth (over the lip in a bite).
  float lipW = (yl - q.y) / max(yl - c0.w, 0.01);        // 0 at the inner edge, 1 at the outer
  float LLL = 0.55 + 0.45 * sin(PI * clamp(lipW * 1.1, 0.0, 1.0)) - 0.25 * s2;
  float lipTex = sw.z * 0.2 * sin(q.x * 70.0 + 3.0 * sin(q.x * 13.0)) * smoothstep(0.1, 0.5, 1.0 - lipW);
  float puckL = gPout * lineA((fract(s * 4.0 + 0.5) - 0.5) / (4.0 / gW), 0.005 * sin(PI * clamp((lipW - 0.5) / 0.4, 0.0, 1.0))) * step(abs(s), 0.8);
  surf(fillA(dLL), LIPD, LIP, LLL - lipTex);
  float tx = 0.06 * shk * sin(u_beat * TAU) + 0.04 * tOut * sin(u_beat * PI);
  // Grows as it comes out: full width at a sliver out made a big round blob over the teeth and
  // gums, half-way into the bass face or any other change.
  float tr = 0.3 * smoothstep(0.0, 0.7, tOut) * (0.8 + 0.2 * gW);
  vec2 tipC = vec2(tx, yl0 - 0.34 * tOut);
  // A broad root blended smoothly into a slightly wider rounded tip. Much narrower at the root
  // and it pinches in the middle like a peanut.
  float dRoot = sdSeg(q, vec2(tx * 0.5, yl0 + 0.05), tipC) - tr * 0.95;
  float dTip = length((q - tipC) / vec2(1.15, 1.0)) - tr * 1.05;
  float kT = 0.09, hT = clamp(0.5 + 0.5 * (dTip - dRoot) / kT, 0.0, 1.0);
  float dTo = mix(dTip, dRoot, hT) - kT * hT * (1.0 - hT);
  // Only where a tongue can be: in the opening, or hanging out below the lower lip's inner edge.
  // Unclipped, its root spilled up out of the top of the mouth as the lips closed on it in a change.
  float tOutOn = fillA(dTo) * step(0.02, tOut) * (1.0 - fillA(dUL)) * min(inO + fillA(q.y - yl), 1.0);   // summed: max seams at the lip
  // And always behind the top row: never up over the gums, or the teeth in a snarl or a clench.
  float yTop_ = mix(ytop - tt * 0.27 * (1.0 - 0.45 * s2), ym, cln);
  tOutOn *= fillA(q.y - yTop_ + 0.01) * (1.0 - gumOn);
  float tol = clamp(0.8 - 0.8 * (-dTo / max(tr, 0.01)) * 0.0 + 0.3 * (q.y - tipC.y) - 0.7 * max(abs(q.x - tx) / max(tr, 0.01) - 0.55, 0.0), 0.0, 1.0);
  surf(tOutOn, TNGD, TNG, tol);
  float tongAll = max(tongIn, tOutOn);
  obj = max(obj, tOutOn);

  float tShU = (0.55 + 0.45 * (1.0 - 4.0 * edge * edge)) * (1.0 - 0.4 * s2) * (0.55 + 0.45 * smoothstep(ytop, ytop - 0.05 - 0.1 * sw.x, q.y));
  surf(upT, TTHD, TTH, tShU + 0.1);

  // The upper lip, in its own shadow.
  float upW = (q.y - yu) / max(c0.z - yu, 0.01);
  float LUL = 0.25 + 0.3 * upW - 0.2 * s2;
  surf(fillA(dUL), LIPD, LIP, LUL - lipTex * 0.6);
  float puckU = gPout * lineA((fract(s * 4.0) - 0.5) / (4.0 / gW), 0.005 * sin(PI * clamp((upW - 0.45) / 0.4, 0.0, 1.0))) * step(abs(s), 0.7) * step(0.12, abs(s));

  // ------------------------------------------------ the style turns light levels into colour
  float shA = smoothstep(0.47, 0.53, gL);
  float shC = mix(0.25, 1.0, smoothstep(0.28, 0.34, gL));
  float shD = smoothstep(0.0, 1.0, gL);
  vec2 hp = rot(0.785) * P * (1.0 / 0.017);             // Ben-Day grid, fixed to the wall
  vec2 hc = fract(hp) - 0.5;
  float dotR = 0.62 * sqrt(clamp(1.0 - gL * 1.15, 0.0, 1.0));
  float bdot = 1.0 - smoothstep(dotR - 0.08, dotR + 0.08, length(hc));
  float shP = 1.0 - bdot * step(0.02, dotR);
  float sh = dot(sw, vec4(shA, shC, shD, shP));
  vec3 mcol = mix(gDk, gLt, sh);

  // Highlights: the lip gloss, the teeth's enamel, the wet tongue, saliva strings.
  float glossD = length(vec2((q.x + 0.18 * gW) / (0.3 * gW), (lipW - 0.45) / 0.2)) - 1.0;
  float gl2 = length(vec2((q.x - 0.28 * gW) / (0.08 * gW), (lipW - 0.5) / 0.14)) - 1.0;
  float gloss = fillA(dLL) * (1.0 - tOutOn) * p_gloss * dot(sw, vec4(fillA(min(glossD, gl2) * 0.1), fillA(glossD * 0.08) * 0.9,
                  smoothstep(0.3, -0.6, glossD) * 0.75, fillA(min(glossD, gl2) * 0.1)));
  float glossU = fillA(dUL) * p_gloss * 0.6 * (1.0 - sw.w) * fillA(length(vec2((q.x + 0.25 * gW) / (0.16 * gW), (upW - 0.62) / 0.16)) * 0.07 - 0.07);
  float enamel = sw.z * 0.6 * (1.0 - s2) * (upT * smoothstep(0.1, 0.0, abs(tf - 0.3) - 0.02)
               + loT * (1.0 - upT) * smoothstep(0.1, 0.0, abs(fract(ub) - 0.3) - 0.02));
  float tspec = tongIn * (1.0 - tOutOn) * (1.0 - smoothstep(0.02, 0.2, tOut)) * p_gloss * (sw.z * smoothstep(0.5, 0.0, length(vec2(q.x * 3.0 - 0.3, (q.y - yt) * 9.0 + 1.0))) * 0.8
              + (sw.x + sw.y) * fillA(length(vec2(q.x * 7.0 + 0.8, (q.y - yt) * 16.0 + 1.3)) * 0.02 - 0.02) * 0.9);
  vec2 tsq = (q - tipC - vec2(-0.35, 0.3) * tr) / max(tr, 0.01);
  tspec += tOutOn * p_gloss * (sw.z * smoothstep(0.5, 0.0, length(tsq * vec2(2.2, 1.3))) * 0.6
         + (sw.x + sw.y) * fillA(length(tsq * vec2(4.5, 2.8)) * 0.1 - 0.1) * 0.6);
  // The tongue's centre groove, and its texture in the detailed hand.
  float groove = tongAll * (1.0 - smoothstep(0.004, 0.012 + 0.01 * sw.z, abs(q.x - tx * step(0.5, tOutOn)))) * smoothstep(yt + 0.05, yt - 0.1, q.y) * 0.6;
  vec2 pc = q * 38.0; vec2 pi_ = floor(pc);
  float papil = tongAll * sw.z * step(0.82, hash(pi_)) * (1.0 - smoothstep(0.15, 0.3, length(fract(pc) - 0.5))) * 0.35;
  mcol = mix(mcol, gDk * 0.7, max(groove, papil) * (1.0 - upT) * (1.0 - loT));
  // Dark gaps between the teeth, in the detailed hand.
  float gapDark = sw.z * (upT * (1.0 - smoothstep(0.0, gapW + gLp, gapD)) + loT * (1.0 - upT) * (1.0 - smoothstep(0.0, gapW + gLp, gapDb)));
  mcol = mix(mcol, MOUD * 1.5, gapDark * 0.85);
  // Saliva strings across a wide-open mouth.
  float spitOn = p_spit * (sw.z + 0.35 * (1.0 - sw.z)) * smoothstep(0.4, 0.7, gOpen) * inO;
  float spit = 0.0;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float xs = gW * (fi == 0.0 ? -0.52 : fi == 1.0 ? 0.3 : 0.62);
    float tq = clamp((q.y - yl) / max(yu - yl, 0.01), 0.0, 1.0);
    float sag = 0.05 * sin(PI * tq) * (fi - 1.0) + 0.02 * sin(u_beat * PI + fi);
    float wS = (0.004 + 0.008 * (1.0 - sin(PI * tq))) + 0.012 * exp(-pow((tq - 0.4 - 0.1 * fi) * 9.0, 2.0));
    spit = max(spit, lineA(q.x - xs - sag, wS) * step(0.5, hash(vec2(fi, floor(bb / 4.0)))) );
  }
  spit *= spitOn * (1.0 - fillA(dTU)) ;
  mcol = mix(mcol, vec3(1.0), spit * 0.8);
  mcol = mix(mcol, vec3(1.0), clamp(gloss + glossU + enamel + tspec, 0.0, 1.0));
  // The words typed on the Visuals page, printed across the stuck-out tongue, a new one each bar.
  // Arched a little, as if round the tongue, and sized to it (an atlas row is 8:1).
  float twW = 3.2 * tr, twU = (q.x - tx) / max(twW, 1e-3) + 0.5;
  float twV = (tipC.y + 0.02 * tr - q.y) / max(twW * 0.125, 1e-3) + 0.5 - 1.2 * (twU - 0.5) * (twU - 0.5);
  float twC = p_tword > 0.5 && tr > 0.01 ? word(vec2(twU, twV), floor(bb / 4.0)) : 0.0;
  twC = smoothstep(0.35, 0.65, twC) * tOutOn * (1.0 - upT) * smoothstep(0.1, 0.4, tOut);
  mcol = mix(mcol, mix(INK, TNGD * 0.35, 0.3), twC * 0.9);

  // ------------------------------------------------ the ink
  float lw = 0.017 * p_ink * dot(sw, vec4(0.75, 1.45, 0.6, 1.35));
  float lwO = lw * mix(1.0, 1.0 + 0.9 * smoothstep(0.0, -0.4, q.y - yl0 * 0.5), sw.y) * mix(1.0, 0.35 + 0.65 * pow(se, 0.5), sw.x + sw.z);
  float ink = lineA(dSil, lwO);
  ink = max(ink, lineA(dIn, min(lw * (0.8 + 0.5 * step(gOpen, 0.05)), 0.028))
                 * (1.0 - fillA(dTU + 0.004) * smoothstep(0.0, 0.012, bite + fext) * step(0.02, tt + cln) * step(q.y, 0.5 * (yu + yl))));
  float tink = min(lw * 0.45, 0.011);
  float loV = loT * (1.0 - upT);                         // the lower teeth that can be seen
  ink = max(ink, upT * lineA(gapD, tink));
  ink = max(ink, upT * lineA(q.y - ybt, tink) * inO);
  // Just the teeth's bottom edge on the lip: all of dBite's outline included a flat top edge across the teeth.
  ink = max(ink, onLip * lineA(max(ybt - q.y, yl - bite - fext - q.y), tink * 1.3) * fillA(q.y - ytop) * step(0.02, tt + cln) * step(q.y, yl));
  ink = max(ink, loV * lineA(gapDb, tink));
  ink = max(ink, inO * lineA(dTU, tink) * step(0.02, tt + cln));
  ink = max(ink, inO * lineA(dTL, tink) * step(0.02, bt + cln) * (1.0 - upT));
  ink = max(ink, tongIn * lineA(dT, tink * 1.3) * (1.0 - fillA(dTL) * step(0.02, bt + cln)) * (1.0 - upT) * (1.0 - tOutOn));
  // Whatever the tongue lies over is hidden under it, lines included (only the top teeth are in
  // front of it). Stopping at the lip edge left the top half of the inner-lip line across it.
  ink *= 1.0 - tOutOn * (1.0 - upT);
  // Inside the mouth it keeps a finer line, or its thick outline stops dead at the lip.
  ink = max(ink, lineA(dTo, tink * 1.3) * step(0.02, tOut) * inO * (1.0 - fillA(dLL)) * (1.0 - upT) * fillA(q.y - yTop_ + 0.01) * (1.0 - gumOn));
  // Its thick outline only where it hangs out below the lip, the same as the fill: left unclipped,
  // the rim of its root showed above the mouth as it closed.
  ink = max(ink, lineA(dTo, lw * 0.9) * step(0.02, tOut) * (1.0 - fillA(dUL)) * (1.0 - upT) * (1.0 - fillA(dSil) * (1.0 - fillA(dLL))) * fillA(q.y - yl));
  ink = max(ink, (puckL * fillA(dLL) * (1.0 - tOutOn) + puckU * fillA(dUL)) * 0.8);
  ink = max(ink, lineA(uvu * 0.04, tink) * inO * thrOn * (1.0 - tongIn) * (1.0 - fillA(dTU)));

  // Face hints: the creases round the corners, the nose above, the chin below.
  float side = q.x < 0.0 ? gCL : gCR;
  float ax = abs(q.x);
  float yc = side + 0.1 + 0.16 * chk;
  float dy = q.y - yc;
  float xc = gW + 0.1 - 0.05 * chk + 1.3 * dy * dy;
  float dCr = (ax - xc) * inversesqrt(1.0 + 6.8 * dy * dy);
  float y0 = side - 0.18, y1 = side + 0.36 + 0.25 * chk;
  float tc = clamp((q.y - y0) / (y1 - y0), 0.0, 1.0);
  float crease = lineA(dCr, lw * (0.4 + 0.8 * chk) * sin(PI * tc)) * step(0.001, tc) * step(tc, 0.999);
  float nY = max(0.64, yu0 + 0.2 + 0.2 * (gSL + gSR)) + 0.06 * bass;
  float nx = abs(q.x) - 0.17 - 0.03 * bass;
  vec2 nq = vec2(nx - 0.04, q.y - nY - 0.07);              // the wings of the nose, like ( )
  float nost = lineA(length(nq) - 0.075, lw * 0.75 * smoothstep(0.09, -0.02, nq.y)) * step(nq.y, 0.05) * step(-0.02, nq.x);
  float tipA = abs(q.x) / 0.19;
  nost = max(nost, lineA(q.y - nY - 0.035 * tipA * tipA, lw * 0.6 * (1.0 - tipA * tipA)) * step(tipA, 1.0));
  float scr = (bass + 0.6 * (KB.z + KB.w)) * lineA(q.y - nY - 0.16 - 0.06 * floor(clamp((abs(q.x) - 0.02) / 0.06, 0.0, 2.0)), lw * 0.45)
            * step(abs(q.x), 0.14) * step(0.02, abs(q.x));
  float yC = c0.w * 0.0 + yl0 - gTh * 0.19 - 0.2 - 0.1 * gPout;
  float chin = lineA(q.y - yC - 1.4 * q.x * q.x, lw * 0.6 * (1.0 - smoothstep(0.12, 0.22, abs(q.x)))) * (0.3 + gPout + 0.5 * cln);
  float face = p_face * max(max(crease, nost * (1.0 - obj)), max(scr * (1.0 - obj), chin * (1.0 - obj)));
  face *= 1.0 - obj;

  // Anime extras: a sweat drop, an anger mark, a blush.
  vec2 sdq = q - vec2(gW * 0.95 + 0.18, max(gCR, 0.0) + 0.5);
  sdq.y -= 0.03 * sin(u_beat * PI);
  float dDrop = max(length(sdq) - 0.07, 0.0);
  dDrop = min(length(sdq) - 0.07, max(abs(sdq.x) - 0.07 * (1.0 - (sdq.y) / 0.16), max(-sdq.y, sdq.y - 0.16)));
  float anime = sw.x + 0.6 * sw.y;
  float dropOn = fillA(dDrop) * smoothstep(0.3, 0.6, sweat) * anime * (1.0 - obj);
  vec2 aq = q - vec2(-gW * 0.9 - 0.12, 0.5 + max(gCL, 0.0));
  aq *= 1.0 + 0.25 * A;
  aq = rot(0.785) * aq;
  vec2 aa = abs(aq);
  float dAng = abs(length(aa - vec2(0.15)) - 0.11) - lw * 1.2;        // four veins bowed in: the anger mark
  dAng = max(dAng, aa.x + aa.y - 0.2);
  dAng = max(dAng, 0.03 - min(aa.x, aa.y));
  float angOn = fillA(dAng)  * smoothstep(0.3, 0.6, anger) * anime * (1.0 - obj);
  vec2 blq = vec2(ax - gW - 0.04, q.y - side - 0.26);
  float blush = fillA((length(blq / vec2(0.16, 0.065)) - 1.0) * 0.065) * smoothstep(0.5, 0.9, chk) * smoothstep(0.1, 0.3, side) * sw.x * (1.0 - obj);
  float hatch = blush * lineA(fract((blq.x + blq.y * 0.7) * 16.0) - 0.5, 0.12) * 1.0;

  // ------------------------------------------------ the background
  vec2 bp = P - head;
  float r = length(bp), ang = atan(bp.y, bp.x);
  float big = clamp(gOpen * 0.8 + shk * 0.3 + bass * 0.6 + 0.2 * C, 0.0, 1.0);
  float bm = p_bg < 3.5 ? floor(p_bg + 0.5) : dot(sw, vec4(2.0, 0.0, 3.0, 1.0));
  vec4 bw = oneHot(bm);
  vec3 bgL = hsv(hue, 0.5 * p_sat, 1.0), bgD = hsv(hue + 0.05, 0.95 * p_sat, 0.86);
  // 0 radial burst
  float rays = floor(8.0 + 16.0 * p_busy);
  float rph = ang / TAU * rays + u_beat * 0.03 + 0.25 * C;
  float dRay = (abs(fract(rph) - 0.5) - 0.25) * TAU * r / rays;
  float burst = smoothstep(-u_px, u_px, dRay) * (0.4 + 0.6 * big);
  // 1 halftone field, pulsing out from the mouth
  vec2 hq = rot(0.785) * bp * (1.0 / (0.03 + 0.02 * (1.0 - p_busy)));
  float hr = (0.12 + 0.5 * smoothstep(0.1, 0.9, r) + 0.2 * A) * (0.6 + 0.4 * big);
  float halft = 1.0 - smoothstep(hr - 0.06, hr + 0.06, length(fract(hq) - 0.5));
  // 2 speed lines rushing in from the edges
  float cell = floor((ang / TAU + 0.5) * (70.0 + 90.0 * p_busy));
  float fl = floor(u_beat * 2.0);
  float hs = hash(vec2(cell, fl)), hs2 = hash(vec2(cell, fl + 17.0));
  float r0 = 0.45 + 0.5 * hs2 - 0.3 * big;
  float spd = step(hs, 0.35 + 0.45 * p_busy) * smoothstep(r0, r0 + 0.2, r) * (1.0 - smoothstep(0.0, 1.0, abs(fract((ang / TAU + 0.5) * (70.0 + 90.0 * p_busy)) - 0.5) * 2.0 / clamp((r - r0) * 3.0, 0.05, 1.0)));
  // 3 flat colour pulsing, with a ring going out on the kick
  float ring = 1.0 - smoothstep(0.0, 0.02, abs(r - (0.3 + 0.9 * fract(u_beat))) - 0.02 * (1.0 + p_busy));
  float flat_ = ring * (1.0 - fract(u_beat)) * (0.5 + 0.5 * p_busy);
  float pat = dot(bw, vec4(burst, halft, spd, flat_));
  vec3 bg = mix(bgL * (0.92 + 0.08 * A * bw.w), bgD, pat * mix(1.0, 0.7, bw.z));
  bg = mix(bg, INK * 0.0 + vec3(0.1, 0.05, 0.12), spd * bw.z * 0.85);

  // ------------------------------------------------ put it together
  vec3 col = mix(bg, mcol, obj);
  col = mix(col, vec3(1.0, 0.55, 0.65), blush * 0.8);
  col = mix(col, vec3(0.8, 0.3, 0.4), hatch * 0.8);
  col = mix(col, vec3(0.75, 0.92, 1.0), dropOn);
  col = mix(col, vec3(0.95, 0.12, 0.15), angOn);
  float inkAll = max(max(ink, face), lineA(dDrop, lw * 0.6) * smoothstep(0.3, 0.6, sweat) * anime * (1.0 - obj));
  inkAll = max(inkAll, ink * tOutOn);
  col = mix(col, INK, clamp(inkAll, 0.0, 1.0));
  return col;
}
