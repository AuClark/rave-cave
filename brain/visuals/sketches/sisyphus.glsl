// Sisyphus: Khepri the scarab rolling the sun up a hill, forever. A dung beetle in its real
// pushing pose -- head down, walking backwards, hind legs up on the ball -- shoves the sun
// towards a summit it never reaches. On the last bar or two of every climb the sun gets away,
// rolls back down and bowls the beetle over with it, and the next climb starts on the phrase.
// The sky is lit by the sun itself: night at the bottom, dawn on the way up, full day near
// the top, and a crash back to dusk when it falls. One must imagine the beetle happy.
//
// Hand redraws the whole thing: 0 wax crayon, 1 rubber-hose ink (1930s film), 2 acid,
// 3 pencil flipbook (every drawing held for a quarter beat), 4 cycles the four.
//
// Drivers (docs/reactive.md): A Hit -> the push (strides, shove, dust, heat); B Move -> the
// sun's rays and sparkle; C Change -> the sky's colour swell.
// Params are p_* uniforms; ranges and defaults are in sisyphus.json.
uniform float p_hill, p_climb, p_size, p_legs, p_night,
              p_style, p_swap, p_boil, p_ink, p_fade,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_follow;

#define TAU 6.2831853
#define PI 3.1415927

// The picture is painted shape by shape into these: a fill colour, the ink over it, how much
// of it is "something drawn" rather than sky, and how much of it is the sun.
vec3 gCol;
float gInk, gObj, gFig, gFigOn, gSun, gPx, gLw, gBleed, gSk, gSkOff, WX, HH;

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
// A capsule that tapers from radius ra at a to rb at b.
float sdCap(vec2 p, vec2 a, vec2 b, float ra, float rb) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - mix(ra, rb, h);
}
float sdEll(vec2 p, vec2 r) { return (length(p / r) - 1.0) * min(r.x, r.y); }

// Paint a shape: fill it, hide what was behind it, lay its outline on top. gBleed pushes the
// fill past its own line or leaves it short (crayon); gSk adds the pencil's second, looser
// construction line beside the real one.
void draw(float d, vec3 c) {
  float ip = 0.5 / gPx;                                             // linear edges: cheap, and as smooth
  float f = clamp(0.5 - (d - gBleed) * ip, 0.0, 1.0);
  float e = clamp(0.5 - (abs(d) - gLw) * ip, 0.0, 1.0);
  e = max(e, gSk * clamp(0.5 - (abs(d - gSkOff) - gLw * 0.5) * ip, 0.0, 1.0));
  gCol = mix(gCol, c, f);
  gInk = max(gInk * (1.0 - f), e);
  gObj = mix(gObj, 1.0, f);
  gFig = mix(gFig, gFigOn, f);
  gSun *= 1.0 - f;
}
// Fill with no outline (highlights, dust).
void fill(float d, vec3 c, float a) {
  gCol = mix(gCol, c, (1.0 - smoothstep(-gPx, gPx, d)) * a);
}

// A driver as in COMMON, but on a clock we choose, so the flipbook can hold its frames, and
// with one band read instead of three (cheaper on a CPU rasteriser).
float drv(float bd, float rate, float shape, float amt, float bb, float ub) {
  float L = loopBeats(rate), ph = fract(bb / L), n = floor(bb / L);
  float hit = band(bd, shape < 0.5 ? ub : n * L + 0.25);          // one read: the level now, or at the fire
  float v;
  if      (shape < 0.5) v = hit;
  else if (shape < 1.5) v = hit * exp(-5.0 * ph * max(L, 1.0));
  else if (shape < 2.5) v = hit * ph;
  else if (shape < 3.5) v = hit * (0.5 - 0.5 * cos(TAU * ph));
  else if (shape < 4.5) v = hit * step(ph, 0.5);
  else                  v = hit * hash(vec2(n, bd));
  return amt * clamp(v, 0.0, 1.0);
}

// The hill: rises left to right and crests just short of the right edge, so the summit is
// always in view and always a little further than they get.
float gy(float x) {
  float t = (x + WX) / (2.0 * WX);
  return -0.40 + HH * sin(t / 0.88 * PI * 0.5);
}
float gslope(float x) {
  float t = (x + WX) / (2.0 * WX);
  return HH * cos(t / 0.88 * PI * 0.5) * (PI * 0.5 / 0.88) / (2.0 * WX);
}

// One step of the gait. Stance (first 60%): the foot is planted and slides back as the body
// lurches past it, fast on the beat and settling after. Swing: lifted and carried forward.
vec2 gait(float ph) {
  ph = fract(ph);
  if (ph < 0.6) return vec2(1.0 - 2.0 * (1.0 - pow(1.0 - ph / 0.6, 2.5)), 0.0);
  float s = (ph - 0.6) / 0.4;
  return vec2(-1.0 + 2.0 * s * s * (3.0 - 2.0 * s), sin(PI * s));
}

// A jointed leg from hip to foot: femur, then a tibia widening to a digging shovel.
float leg(vec2 q, vec2 hip, vec2 foot, float l1, float l2, float bend, float w) {
  vec2 d = foot - hip;
  float dl = max(length(d), 1e-4);
  vec2 dn = d / dl;
  dl = min(dl, (l1 + l2) * 0.995);
  float a = (l1 * l1 - l2 * l2 + dl * dl) / (2.0 * dl);
  vec2 knee = hip + dn * a + vec2(-dn.y, dn.x) * sqrt(max(l1 * l1 - a * a, 0.0)) * bend;
  return min(sdCap(q, hip, knee, w, w * 0.8), sdCap(q, knee, hip + dn * dl, w * 0.75, w * 1.3));
}

// Three legs of one side, painted as one shape. q is in the frame of the ball's contact point
// (x uphill), C0/tl place the body, bc is the ball's centre, ph is this side's gait phase.
void legs(vec2 q, vec2 C0, float tl, vec2 bc, float R, float BS, float ph, float amp, float far, vec3 c) {
  mat2 tb = rot(tl);
  float w = BS * 0.10;
  vec2 fl = vec2(-BS * 0.12, 0.0) * far;                          // far feet sit a little further on
  // front pair: out ahead (downhill) of the head, on the ground
  vec2 g = gait(ph + 0.5 * far);
  vec2 hip = C0 + tb * vec2(-BS * 1.15, -BS * 0.30);
  float d = leg(q, hip, vec2(hip.x - BS * 1.15 + g.x * BS * 0.55 * amp, g.y * BS * 0.40 * amp) + fl,
                BS * 0.62, BS * 0.78, -1.0, w);
  // middle pair: under the body
  g = gait(ph + 0.5 - 0.5 * far);
  hip = C0 + tb * vec2(-BS * 0.50, -BS * 0.48);
  d = min(d, leg(q, hip, vec2(hip.x + BS * 0.15 + g.x * BS * 0.55 * amp, g.y * BS * 0.40 * amp) + fl,
                 BS * 0.62, BS * 0.72, 1.0, w));
  // hind pair: long, up on the ball, walking it round
  g = gait(ph + 0.5 * far);
  hip = C0 + tb * vec2(BS * 0.10, -BS * 0.52);
  float th = 1.95 + 0.20 * far + 0.30 * g.x * amp;
  d = min(d, leg(q, hip, bc + (R + g.y * BS * 0.30 * amp) * vec2(cos(th), sin(th)),
                 BS * 0.95, BS * 1.10, 1.0, w));
  draw(d, c);
}

vec3 content(vec2 uv) {
  float bbR = barBeat();

  // Which hand is drawing: fixed, or the four in turn, changing on a bar line.
  float st = p_style < 3.5 ? floor(p_style + 0.5) : mod(floor(bbR / max(p_swap * 4.0, 1.0)), 4.0);
  float crayon = step(abs(st), 0.5), inkS = step(abs(st - 1.0), 0.5);
  float acid = step(abs(st - 2.0), 0.5), pencil = step(abs(st - 3.0), 0.5);

  // The clock. The flipbook holds every drawing for a quarter beat, so it moves in steps that
  // land on the beat; everything else runs smooth. fr is the redraw frame for the boil.
  float ub = pencil > 0.5 ? floor(u_beat * 4.0) * 0.25 : u_beat;
  float bb = bbR + (ub - u_beat);
  float fr = floor(u_beat * 4.0);
  float A = drv(p_aband, p_aloop, p_ashape, p_aamt, bb, ub);
  float B = drv(p_bband, p_bloop, p_bshape, p_bamt, bb, ub);
  float C = drv(p_cband, p_cloop, p_cshape, p_camt, bb, ub);
  float H = fract(p_hue + (p_follow > 0.5 ? u_hue : 0.0));

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;
  WX = u_aspect * 0.5;

  // Boil: the same picture redrawn slightly differently four times a beat.
  vec2 jit = vec2(hash(vec2(fr, 1.7)), hash(vec2(fr, 9.1))) - 0.5;
  p += jit * p_boil * (0.010 * crayon + 0.003 * inkS + 0.004 * acid + 0.005 * pencil);
  if (crayon + pencil > 0.5)
    p += (vec2(vnoise(p * 6.0 + fr), vnoise(p * 6.0 + fr + 31.0)) - 0.5)
       * (0.016 * crayon + 0.006 * pencil) * p_boil;
  if (acid > 0.5)
    p += vec2(sin(p.y * 8.0 + bb * PI * 0.25), cos(p.x * 6.0 - bb * PI * 0.125)) * 0.028 * p_boil * (0.3 + B);

  gPx = u_px * (1.0 + 1.5 * crayon + 0.4 * pencil);
  float nL = vnoise(p * 24.0);                                        // line weight wanders (crayon, brush)
  gLw = p_ink * (crayon > 0.5 ? 0.0090 * (0.6 + 0.8 * nL)
               : inkS > 0.5   ? 0.0060 * (0.65 + 0.7 * nL)
               : acid > 0.5   ? 0.0045 : 0.0030);
  gLw = min(gLw * mix(0.6, 1.0, clamp((WX - 0.28) / 0.6, 0.0, 1.0)), 0.012);   // thinner on a narrow surface
  gBleed = 0.0; gSk = 0.0; gSkOff = 0.0;
  if (crayon + pencil > 0.5) {
    float nB = vnoise(p * 7.5 + 11.0 + fr * 1.7 * pencil) - 0.5;
    gBleed = nB * (0.020 * crayon + 0.005 * pencil);
    gSk = pencil * clamp(0.35 + 0.65 * p_boil, 0.0, 1.0);
    gSkOff = nB * 0.014;
  }
  gInk = 0.0; gObj = 0.0; gFig = 0.0; gFigOn = 0.0; gSun = 0.0;

  // ---- sizes. Everything shrinks on a narrow surface so the pair and the hill still fit.
  float S = clamp(WX / 0.8, 0.55, 1.0);
  float R = min(0.105 * p_size * S, WX * 0.24), BS = R * 0.76;       // the pair never outgrows the surface
  HH = mix(0.14, 0.60, clamp((p_hill - 0.1) / 1.1, 0.0, 1.0)) * clamp(WX / 0.7, 0.8, 1.0);
  HH = min(HH, 0.83 - 2.9 * R);                                   // the sun never leaves the top

  // ---- the climb: p_climb bars. Up in one lurch per stride, then on the last bar (two, on a
  // long climb) it gets away and rolls back, so the next climb starts on the phrase.
  float total = max(floor(p_climb + 0.5), 1.0) * 4.0;
  float Tf = total >= 64.0 ? 8.0 : 4.0;
  float Tc = total - Tf;
  float Ls = min(loopBeats(p_aloop), 2.0);                       // beats per stride
  float k = mod(bb, total);
  float pos, ff = 0.0, fc = 0.0, falling = step(Tc, k);
  if (falling < 0.5) {
    float sN = k / Ls;
    float lu = 1.0 - pow(1.0 - min(fract(sN) / 0.6, 1.0), 2.5);
    pos = (0.3 * sN + 0.7 * (floor(sN) + lu)) / (Tc / Ls);
  } else {
    ff = (k - Tc) / Tf;
    fc = pow(clamp((ff - 0.15) / 0.65, 0.0, 1.0), 1.8);
    pos = 1.0 - fc + 0.010 * sin(k * TAU * 2.0) * (1.0 - smoothstep(0.0, 0.15, ff));  // teeters first
  }
  float x0 = -WX + R * 1.1 + BS * 3.2, x1 = max(WX * 0.60, x0);
  float xs = mix(x0, x1, pos);
  float sl = atan(gslope(xs));
  vec2 nrm = vec2(-sin(sl), cos(sl));
  vec2 contact = vec2(xs, gy(xs));
  float hop = abs(sin(fc * PI * 4.0)) * (1.0 - fc) * R * 0.7 * falling;   // bounces on the way down
  vec2 sunC = contact + nrm * R + vec2(0.0, hop);

  // The sun lights the sky: night at the foot of the hill, day near the top.
  float L = mix(1.0 - p_night, 1.0, smoothstep(0.0, 0.6, pos));
  float Ld = smoothstep(0.0, 0.5, L), Lf = smoothstep(0.5, 1.0, L);

  // ---- sky. C Change is the chord swell: the horizon glow rises and floods with colour.
  float hb = clamp((p.y + 0.20) / (0.62 + 0.45 * C), 0.0, 1.0);
  vec3 zen = mix(vec3(0.02, 0.02, 0.08), mix(vec3(0.20, 0.15, 0.40), vec3(0.28, 0.55, 0.88), Lf), Ld);
  vec3 hor = mix(vec3(0.10, 0.06, 0.20), mix(hsv(fract(H - 0.04), 0.78, 1.0), vec3(1.0, 0.88, 0.66), Lf * 0.8), Ld);
  hor = mix(hor, hsv(fract(H - 0.08), 0.85, 1.0) * (0.55 + 0.45 * Ld), C * 0.55);
  gCol = mix(hor, zen, sqrt(hb));
  gCol += hsv(fract(H + 0.92), 0.65, 1.0) * C * 0.30 * exp(-max(p.y + 0.2, 0.0) * 3.5) * (0.4 + 0.6 * Ld);

  if (acid > 0.5) {
    // An acid sky is a sunburst: wedges wheeling round the sun, hue running round the wheel.
    vec2 sq = p - sunC;
    float an = atan(sq.y, sq.x);
    float w = step(0.5, fract(an / TAU * 14.0 + bb * 0.125));
    gCol = mix(hsv(fract(H + 0.50 + bb * 0.03125), 0.85, 0.95), hsv(fract(H + 0.78 + bb * 0.03125), 0.9, 0.60), w);
    gCol *= (0.6 + 0.4 * Ld) * (0.8 + 0.4 * C);
  }

  // Stars, when the sun is low. They twinkle on the hats.
  float nt = (1.0 - smoothstep(0.2, 0.65, L)) * (1.0 - acid);
  if (nt > 0.01) {
    vec2 sg = p * 22.0, sid = floor(sg);
    float sh = hash(sid);
    vec2 sc = fract(sg) - 0.5 - (vec2(hash(sid + 1.3), hash(sid + 2.7)) - 0.5) * 0.6;
    float star = (1.0 - smoothstep(0.0, 0.09, length(sc))) * step(0.84, sh) * smoothstep(-0.15, 0.1, p.y);
    float tw = 0.45 + 0.55 * step(0.5, hash(sid + floor(ub * 2.0))) * (0.4 + B);
    gCol += vec3(1.0, 0.96, 0.84) * star * nt * tw;
  }

  // Two clouds, drifting a little each bar.
  vec3 cloudC = mix(vec3(0.16, 0.14, 0.30), mix(hor, vec3(1.0, 0.97, 0.92), 0.6 + 0.3 * Lf), Ld);
  float lw0 = gLw;
  gLw *= 0.7;
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    vec2 cq = p - vec2(mod(fi * 1.13 + bb * 0.006 * (1.0 + 0.6 * fi), 2.0 * WX + 0.5) - WX - 0.25,
                       0.33 - 0.10 * fi);
    cq /= S * (1.0 - 0.25 * fi);
    float cd = min(min(length(cq - vec2(-0.065, 0.0)) - 0.042, length(cq - vec2(0.0, 0.018)) - 0.060),
                   length(cq - vec2(0.070, -0.002)) - 0.040);
    draw(max(cd, -cq.y - 0.028) * S * (1.0 - 0.25 * fi), cloudC);
  }

  // ---- the far desert: a dune ridge and two pyramids, hazed into the sky behind them.
  gLw = lw0 * 0.45;
  vec3 sand = mix(vec3(0.11, 0.10, 0.22), mix(vec3(0.60, 0.34, 0.30), vec3(0.88, 0.64, 0.36), Lf), Ld);
  vec3 farC = mix(sand * 0.85, hor, 0.45);
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    float ph = (0.075 - 0.025 * fi) * S, pw = ph * 1.3;
    vec2 pq = p - vec2(-WX * (0.60 - 0.14 * fi), -0.215);
    draw(max((abs(pq.x) * ph + pq.y * pw - pw * ph) / sqrt(ph * ph + pw * pw), -pq.y),
         farC * (pq.x > 0.0 ? 0.74 : 1.0));                        // lit face, shaded face
  }
  float fy = -0.20 + 0.030 * sin(p.x * 4.0 + 1.3) + 0.016 * sin(p.x * 9.0 + 0.4);
  draw((p.y - fy) * 0.9, mix(farC, hor, 0.15));
  gLw = lw0;

  // ---- the hill
  float m = gslope(p.x), dg = (p.y - gy(p.x)) / sqrt(1.0 + m * m);
  vec3 hillC = sand * (0.80 + 0.20 * smoothstep(-0.3, 0.3, p.x));
  hillC *= 1.0 - 0.40 * smoothstep(0.0, 0.5, -dg);                    // darker deeper in
  hillC += hillC * 0.35 * (1.0 - smoothstep(0.0, 0.018, -dg));        // a lit lip along the ridge
  hillC *= 1.0 - 0.10 * smoothstep(0.75, 1.0, sin(dg * 70.0 + sin(p.x * 6.0) * 2.0)) * step(dg, -0.03);
  if (acid > 0.5)                                                   // op-art contours flowing downhill
    hillC = mix(hsv(fract(H + 0.30 + bb * 0.03125), 0.9, 0.8), hsv(fract(H + 0.10 + bb * 0.03125), 0.9, 0.45),
                step(0.5, fract(-dg * 14.0 + bb * 0.5)));
  draw(dg, hillC);
  // a few stones along the ridge
  if (abs(dg) < 0.03) {
    float cell = floor(p.x * 7.0), h1 = hash(vec2(cell, 4.2));
    if (h1 > 0.62) {
      float sx = (cell + 0.25 + 0.5 * hash(vec2(cell, 7.7))) / 7.0, sr = (0.005 + 0.007 * h1) * S;
      float lwS = gLw; gLw *= 0.6;
      draw(sdEll(p - vec2(sx, gy(sx) + sr * 0.6), vec2(sr * 1.5, sr)), sand * 0.72);
      gLw = lwS;
    }
  }

  gFigOn = 1.0;                                                     // the cast from here on
  gLw = min(gLw, BS * 0.11);                                        // a line never swamps a small figure

  // ---- the sun: heat on the kick, rays and sparkle on the hats
  vec2 s = p - sunC;
  float rs = length(s), an = atan(s.y, s.x);
  float roll = -(xs - x0) / max(R, 0.02);
  float dropAmt = step(6.5, u_scene) * step(u_scene, 7.5) * (1.0 - smoothstep(0.0, 8.0, u_since));
  float heat = 0.35 + 0.9 * A + 1.2 * dropAmt;
  vec3 sunCol = hsv(H, 0.72, 1.0);
  gCol += sunCol * exp(-max(0.0, rs - R) * (18.0 - 7.0 * A)) * heat * (0.25 + 0.45 * (1.0 - L)) * (1.0 - 0.5 * acid);

  if (rs < R * 2.9) {                                               // only near the sun
  float ra = (an - roll) / TAU * 12.0;
  float alt = mod(floor(ra + 0.5) + floor(ub * 2.0), 2.0);          // alternate rays swap on the 8ths
  float rl = R * (0.20 + 0.60 * B * (0.35 + 0.65 * alt) + 0.12 * A);
  float wr = abs(fract(ra + 0.5) - 0.5) * 2.0;
  float gr = rl * 1.7 * 12.0 / (PI * max(rs, 1e-3));
  float dRay = (rs - R * 1.02 - rl * max(0.0, 1.0 - wr * 1.7)) / sqrt(1.0 + gr * gr * 0.25);
  draw(dRay, hsv(fract(H + 0.04), 0.85, 1.0));
  draw(rs - R, sunCol);
  gSun = max(gSun, 1.0 - smoothstep(-gPx, gPx, min(dRay, rs - R)));
  float sw = vnoise(rot(roll) * s / max(R, 0.02) * 3.0);
  fill(rs - R, hsv(fract(H + 0.03), 0.45, 1.0), smoothstep(0.50, 0.66, sw) * 0.55);

  // Its face: resigned at the bottom, straining near the top, wide-eyed when it gets away.
  vec2 f = s / max(R, 0.02);
  float shock = falling * smoothstep(0.0, 0.08, ff) * (1.0 - smoothstep(0.80, 0.97, ff));
  float strain = (1.0 - falling) * pos;
  float lidv = mix(0.6 * strain, 0.0, shock);
  vec2 look = normalize(vec2(-0.7, mix(-0.5, 0.9, shock))) * 0.09;
  for (int i = 0; i < 2; i++) {
    vec2 e = f - vec2((float(i) * 2.0 - 1.0) * 0.33, 0.22);
    draw(sdEll(e, vec2(0.19, 0.27 - 0.14 * lidv)) * R, vec3(0.99, 0.97, 0.92));
    draw((length(e - look) - mix(0.085, 0.060, shock)) * R, vec3(0.05, 0.04, 0.06));
  }
  float curve = mix(0.45, -0.75, strain), tx = clamp(f.x / 0.40, -1.0, 1.0);
  float dBar = max(abs(f.y - (-0.28 - curve * 0.25 * (1.0 - tx * tx))) - 0.07, abs(f.x) - 0.38);
  draw(mix(dBar, length((f - vec2(0.0, -0.32)) * vec2(1.0, 0.8)) - 0.17, shock) * R, vec3(0.30, 0.06, 0.07));
  float sweat = smoothstep(0.55, 0.9, strain) * (0.4 + A);
  if (sweat > 0.08)
    draw((length((f - vec2(-0.70, 0.45 - fract(ub * 0.5) * 0.5)) * vec2(1.0, 0.72)) - 0.09 * min(sweat, 1.0)) * R,
         vec3(0.62, 0.86, 1.0));

  // Sparkle: two glints per 8th round the sun, on the hats.
  for (int i = 0; i < 2; i++) {
    float fi = float(i), e8 = floor(ub * 2.0);
    float ga = TAU * hash(vec2(fi, e8 + 3.0));
    vec2 gq = abs(p - sunC - R * (1.45 + 0.7 * hash(vec2(e8, fi))) * vec2(cos(ga), sin(ga)));
    float sz = R * 0.55 * B * (1.0 - 0.7 * fract(ub * 2.0));
    float gl = max(1.0 - (gq.x + gq.y * 7.0) / max(sz, 1e-4), 1.0 - (gq.y + gq.x * 7.0) / max(sz, 1e-4));
    gCol += vec3(1.0, 0.97, 0.85) * max(gl, 0.0) * (1.0 - pencil * 0.5);
  }
  }

  // ---- the beetle, in the frame of the ball's contact point: x uphill, y off the slope.
  vec2 q = rot(-sl) * (p - contact);
  vec2 bc = vec2(0.0, R + hop);
  float tl = 0.72 + 0.08 * A;                                        // body tilt: rear up on the ball
  vec2 ax = vec2(cos(tl), sin(tl));
  vec2 C0 = bc + R * 0.97 * vec2(cos(2.28), sin(2.28)) - ax * BS * (1.08 - 0.10 * A);
  vec2 qc = q - C0;
  bool inB = falling > 0.5 ? length(qc - vec2(0.0, BS * 0.8 * sin(PI * fc))) < BS * 4.6
                           : (qc.x > -BS * 4.8 && qc.x < BS * 2.4 && q.y > -BS * 0.9 && qc.y < BS * 2.6);
  if (falling > 0.5) {                                               // bowled over, and over
    vec2 piv = C0 + vec2(0.0, BS * 0.8 * sin(PI * fc));
    q = rot(-TAU * 2.0 * fc) * (q - piv) + C0;
  }
  float amp = clamp(p_legs * (0.65 + 0.9 * A), 0.0, 1.6) * (1.0 - falling * 0.5);
  float gph = bb / Ls;
  vec3 shell = mix(vec3(0.05, 0.05, 0.08), hsv(fract(H + 0.52), 0.60, 0.55), 0.45);

  if (inB) {                                                        // only near the beetle
  // Dust kicked up by the front feet on every stride, bigger on a harder kick.
  float sp = fract(gph);
  float kickHit = band(p_aband, floor(gph) * Ls + 0.05) * p_aamt;   // how hard this stride landed
  if (falling < 0.5 && kickHit > 0.02) {
    vec2 dq = q - (C0 + rot(tl) * vec2(-BS * 1.15, -BS * 0.30) + vec2(-BS * 1.2, 0.0));
    float dr = BS * (0.18 + 0.40 * sp) * (0.5 + 0.5 * kickHit);
    float dd = min(length(dq - vec2(-dr * 0.8, dr * 0.4)), min(length(dq - vec2(dr * 0.2, dr * 0.9)), length(dq + vec2(dr * 1.7, -dr * 0.2))))
             - dr;
    fill(dd, mix(sand, vec3(1.0, 0.95, 0.85), 0.5), (1.0 - sp) * min(kickHit * 2.0, 1.0) * 0.9);
  }

  legs(q, C0, tl, bc, R, BS, gph, amp, 1.0, shell * 0.55);           // far side, in shadow
  vec2 bq = rot(-tl) * (q - C0);                                     // body frame: x to the rear
  draw(sdEll(bq, vec2(BS * 1.08, BS * 0.76)), shell);                // wing cases
  gInk = max(gInk, (1.0 - smoothstep(gLw * 0.35, gLw * 0.35 + gPx * 1.5,
          abs(sdEll(bq - vec2(0.0, -BS * 0.08), vec2(BS * 0.86, BS * 0.52))))) * step(-BS * 0.1, bq.y) * 0.8);
  fill(sdEll(rot(-0.25) * (bq - vec2(-BS * 0.15, BS * 0.42)), vec2(BS * 0.48, BS * 0.12)),
       shell + vec3(0.55, 0.60, 0.70), 0.75);                        // the shine on a beetle's back
  draw(sdEll(bq - vec2(-BS * 1.12, -BS * 0.06), vec2(BS * 0.50, BS * 0.52)), shell * 1.15);   // pronotum
  vec2 hv = bq - vec2(-BS * 1.66, -BS * 0.16);
  float tooth = abs(sin(hv.y / BS * 11.0));
  draw(length(hv) - BS * 0.40 * (1.0 + 0.09 * tooth * tooth * step(hv.x, -BS * 0.2)), shell * 0.9);  // toothed head
  draw(sdCap(bq, vec2(-BS * 1.85, BS * 0.12), vec2(-BS * 2.12, BS * 0.42), BS * 0.035, BS * 0.035), shell * 0.7);
  draw(sdEll(bq - vec2(-BS * 2.16, BS * 0.48), vec2(BS * 0.12, BS * 0.08)), shell * 0.9);      // antenna club
  draw(length(hv - vec2(BS * 0.02, BS * 0.14)) - BS * 0.17, vec3(0.97, 0.95, 0.88));           // eye
  draw(length(hv - vec2(-BS * 0.04, BS * 0.10)) - BS * 0.085, vec3(0.03));
  legs(q, C0, tl, bc, R, BS, gph + 0.5, amp, 0.0, shell * 1.5 + vec3(0.06, 0.04, 0.02));     // near side
  }

  // ---- ink, then whatever the hand does to the finished drawing
  float inkA = clamp(gInk, 0.0, 1.0);
  vec3 c = gCol;
  float grain = crayon + pencil > 0.5 ? vnoise(p * 360.0) : 0.5;     // paper tooth
  if (crayon > 0.5) {
    // Wax on paper: the colours laid on in strokes, the paper showing through, a kid's sky
    // that's a band of blue across the top and white paper below it.
    vec3 paper = vec3(0.97, 0.95, 0.90);
    float lum = dot(c, vec3(0.30, 0.55, 0.15));
    vec3 wax = clamp(mix(vec3(lum), c, 1.4), 0.0, 1.0);
    wax = mix(wax, pow(wax, vec3(0.75)), smoothstep(0.2, 0.6, lum));   // light crayons go on bright
    // sky scribbled across, the ground on the slant, the cast steeper still
    vec2 rp = rot(0.12 + 0.75 * gObj + 0.45 * gFig + 0.12 * sin(p.x * 5.0 + p.y * 3.0)) * p;
    float strokes = vnoise(vec2(rp.x * 11.0, rp.y * 160.0));
    float tooth = grain;
    float press = 0.55 + 0.45 * smoothstep(0.7, 0.1, lum);           // dark crayons pressed harder
    float cov = smoothstep(0.42, 0.62, press * 0.55 + 0.40 * strokes + 0.30 * (tooth - 0.5));
    float skyCov = mix(1.0, smoothstep(0.02, 0.30, p.y), Lf);
    cov *= mix(skyCov * 0.9, 1.0, max(gObj, gSun));
    c = mix(paper, wax, cov);
    inkA *= step(0.28, vnoise(p * 75.0));                            // a line with gaps in it
    c = mix(c, vec3(0.13, 0.09, 0.08), inkA * 0.95);
    c *= 0.94 + 0.06 * tooth;
  } else if (inkS > 0.5) {
    // 1930s: muted, yellowed colour under a heavy brush line, on a flickering, dusty print.
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(l), c, 0.95) * vec3(1.04, 0.96, 0.80) + vec3(0.035, 0.025, 0.0);
    c = mix(c, vec3(0.08, 0.05, 0.05), inkA);
    c *= (0.95 + 0.05 * hash(vec2(fr, 5.0))) * (0.93 + 0.10 * hash(floor(p * 420.0) + fr * 7.1));
    // Now and then a scratch on the print: pale, wavering, and only part of the way down the
    // frame, so it reads as damage to the film rather than a seam in the picture.
    float scx = (hash(vec2(fr, 2.0)) * 1.6 - 0.8) * WX + 0.004 * sin(p.y * 23.0 + fr);
    float scy = hash(vec2(fr, 4.0)) - 0.5, scl = 0.12 + 0.25 * hash(vec2(fr, 5.0));
    float scr = step(0.9, hash(vec2(fr, 8.0))) * (1.0 - smoothstep(scl * 0.6, scl, abs(p.y - scy)))
              * (1.0 - smoothstep(0.0, 0.0015 + gPx, abs(p.x - scx)));
    c = mix(c, vec3(0.96, 0.93, 0.84), scr * 0.45);
    c *= 1.0 - 0.7 * step(0.9992, hash(floor(p * 200.0) + fr));      // dust
    vec2 vp = p / vec2(WX, 0.5);
    c *= 1.0 - 0.30 * pow(clamp(length(vp) * 0.72, 0.0, 1.0), 2.5);
  } else if (acid > 0.5) {
    // Gradient-mapped through a hue wheel that turns with the bar, posterised, neon line.
    float l = dot(c, vec3(0.3, 0.5, 0.2));
    vec3 g = hsv(fract(H + l * 0.9 + bb * 0.03125 + B * 0.25), 0.90, 0.35 + 0.75 * l);
    c = mix(c, g, 0.6 * (1.0 - 0.75 * gFig));
    c = floor(pow(clamp(c, 0.0, 1.0), vec3(0.8)) * 5.0 + 0.5) / 5.0;
    c = mix(c, hsv(fract(H + 0.5 + bb * 0.0625), 0.9, 1.0), inkA);
  } else {
    // Pencil flipbook: graphite on cream, tone by hatching redrawn every frame, and the sun
    // done in the one coloured pencil in the box.
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    vec3 paper = vec3(0.95, 0.93, 0.87) * (0.96 + 0.04 * grain);
    float tone = clamp(1.0 - l * 1.35, 0.0, 1.0);
    vec2 hp = rot((hash(vec2(fr, 3.3)) - 0.5) * 0.12) * p * 68.0;   // re-hatched every frame
    float nH = vnoise(p * 18.0 + fr) * 0.9;
    float h1 = abs(fract(hp.x + hp.y + nH) - 0.5) * 2.0;
    float h2 = abs(fract(hp.x - hp.y - nH) - 0.5) * 2.0;
    float brk = vnoise(vec2(hp.x - hp.y, floor(hp.x + hp.y) * 3.1) * 0.35);   // strokes lift off
    float hatch = (1.0 - smoothstep(0.0, 0.40, h1)) * smoothstep(0.22, 0.48, tone) * step(0.3, brk)
                + (1.0 - smoothstep(0.0, 0.35, h2)) * smoothstep(0.55, 0.80, tone) * step(0.7, 1.0 - brk * 0.8);
    vec3 graph = vec3(0.30, 0.30, 0.34);
    c = mix(paper * (1.0 - 0.22 * tone), graph, clamp(hatch, 0.0, 1.0) * 0.6);
    c = mix(c, hsv(H, 0.70, 0.97) * (0.85 + 0.15 * h1), gSun * 0.85);
    c = mix(c, graph * 0.6, inkA * 0.92);
    // the thumb's corner of the page, a different size every drawing
    float cs = 0.045 + 0.025 * hash(vec2(fr, 6.1)), cd = (WX - p.x) + (p.y + 0.5) - cs;
    c = mix(c, paper * 0.86 * (0.9 + 0.1 * smoothstep(0.0, cs, -cd)), step(cd, 0.0));
    c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.006, abs(cd)));
  }
  // Fade: the colour drains out to an old sepia print.
  c = mix(c, dot(c, vec3(0.299, 0.587, 0.114)) * vec3(1.10, 0.97, 0.78), p_fade);
  return mix(c, vec3(1.0), dropAmt * 0.4 * kick());
}
