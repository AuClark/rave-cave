// Sisyphus: a dung beetle pushing the sun up a hill that never ends. Drawn clean by
// default; Hand switches to crayon scribble, 1930s rubber-hose cartoon or acid, or
// cycles all four. The sky runs day to night on its own loop, and at night it gets
// visitors: an aurora, a planet with no business being there, saucers, and a tractor
// beam that lifts the sun away while the beetle carries on pushing nothing.
// The sun has a face, and it knows exactly how far it still has to go.
//
// Drivers (docs/reactive.md): A Hit -> the legs and the sun's heat; B Move -> the
// twinkle and the acid drift; C Change -> the abduction.
// Params are p_* uniforms; ranges and defaults are in sisyphus.json.
uniform float p_hill, p_climb, p_size, p_legs,
              p_day, p_aliens,
              p_style, p_swap, p_boil, p_ink,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_follow;

#define TAU 6.2831853

// The picture is painted shape by shape into these: a fill colour and the ink over it.
// WX is half the surface width, so the hill and the walk fit whatever shape the surface is.
vec3 gCol;
float gInk, gPx, gLw, gBleed, WX;

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

// Paint a shape: fill it, hide what was behind it, lay its outline on top.
// gBleed pushes the fill past its own line (or leaves it short), which is what makes
// the crayon style look like someone who hasn't yet met the concept of an edge.
void draw(float d, vec3 c) {
  float f = 1.0 - smoothstep(-gPx, gPx, d - gBleed);
  float e = 1.0 - smoothstep(gLw - gPx, gLw + gPx, abs(d));
  gCol = mix(gCol, c, f);
  gInk = max(gInk * (1.0 - f), e);
}

// Three legs of one side. i = 0 is the front pair, up on the ball; the other two walk.
void legs(vec2 b, float BS, float amp, float ph0, vec3 c) {
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float ph = ph0 + fi * 0.3333;
    float s = sin(TAU * ph), lift = max(0.0, -cos(TAU * ph));
    vec2 hip = vec2(BS * (0.75 - fi * 0.75), -BS * 0.42), foot, knee;
    if (i == 0) {
      foot = hip + vec2(BS * 1.45, BS * (0.55 + 0.40 * s * amp));
      knee = (hip + foot) * 0.5 + vec2(BS * 0.15, -BS * 0.45);
    } else {
      foot = hip + vec2(s * BS * 0.95 * amp, -BS * (0.95 - lift * 0.45 * amp));
      knee = (hip + foot) * 0.5 + vec2(BS * (0.50 - 0.28 * lift), BS * 0.26);
    }
    draw(min(sdSeg(b, hip, knee), sdSeg(b, knee, foot)) - BS * 0.12, c);
    draw(length(b - foot) - BS * 0.16, c);
  }
}

void saucer(vec2 q, float blink, vec3 tint) {
  float hull = sdEll(q, vec2(0.062, 0.015));
  float dome = max(sdEll(q - vec2(0.0, 0.011), vec2(0.028, 0.026)), 0.011 - q.y);
  draw(min(hull, dome), vec3(0.70, 0.75, 0.80));
  draw(dome, mix(vec3(0.45, 0.92, 0.80), tint, 0.5));
  for (int i = 0; i < 3; i++) {
    float on = step(0.5, fract(blink + float(i) * 0.333));
    draw(length(q - vec2((float(i) - 1.0) * 0.030, -0.009)) - 0.006, mix(vec3(0.22), tint, on));
  }
}

// The hill: rises to the right, slightly convex, so it reads as a hill and not a ramp.
// t runs 0 at the left edge to 1 at the right, whatever the surface's aspect.
float gy(float x) {
  float t = (x + WX) / max(2.0 * WX, 0.01);
  return -0.36 + p_hill * (0.72 * t + 0.24 * t * t);   // base clears the bottom edge, legs and all
}
float gslope(float x) {
  float t = (x + WX) / max(2.0 * WX, 0.01);
  return p_hill * (0.72 + 0.48 * t) / max(2.0 * WX, 0.01);
}

vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);
  float bb = barBeat();
  float H = fract(p_hue + (p_follow > 0.5 ? u_hue : 0.0));

  // Which hand is drawing this frame.
  float st = p_style < 3.5 ? p_style : mod(floor(bb / max(p_swap * 4.0, 0.5)), 4.0);
  float crayon = step(abs(st), 0.5), cup = step(abs(st - 1.0), 0.5), acid = step(abs(st - 2.0), 0.5);
  float clean = 1.0 - crayon - cup - acid;

  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;
  WX = max(u_aspect, 0.6) * 0.5;

  // Boil: the same picture redrawn slightly differently several times a second.
  float bt = floor(u_time * (5.0 + 10.0 * p_boil));
  p += (vec2(hash(vec2(bt, 1.7)), hash(vec2(bt, 9.1))) - 0.5)
     * p_boil * (0.016 * crayon + 0.004 * cup + 0.006 * acid);
  if (crayon > 0.5)
    p += (vec2(vnoise(p * 5.0 + bt), vnoise(p * 5.0 + bt + 31.0)) - 0.5) * 0.030 * p_boil;
  if (acid > 0.5)
    p += vec2(sin(p.y * 9.0 + bb * 0.7), cos(p.x * 7.0 - bb * 0.5)) * 0.045 * p_boil * (0.25 + B);

  gPx = u_px * (1.0 + 2.5 * crayon + 0.6 * cup);
  gLw = p_ink * (0.0085 * crayon * (0.5 + 1.5 * vnoise(p * 45.0)) + 0.0080 * cup
               + 0.0042 * acid + 0.0055 * clean);       // clean gets a confident even line
  gBleed = (vnoise(p * 6.5 + 11.0) - 0.5) * (0.024 * crayon + 0.010 * acid);
  gInk = 0.0;

  // ---- sky: one full day over p_day bars
  float dph = fract(bb / max(p_day * 4.0, 4.0));
  float night = 0.5 - 0.5 * cos(TAU * dph);
  float dusk = pow(1.0 - abs(2.0 * night - 1.0), 3.0);
  float sy = clamp(p.y + 0.5, 0.0, 1.0);
  gCol = mix(mix(vec3(1.00, 0.95, 0.72), vec3(0.30, 0.68, 0.95), sy),
             mix(vec3(0.10, 0.07, 0.26), vec3(0.01, 0.01, 0.07), sy), night);
  gCol = mix(gCol, mix(vec3(1.00, 0.42, 0.18), vec3(0.38, 0.10, 0.44), sy), dusk * 0.8);

  // ---- the night sky and its visitors
  float nv = smoothstep(0.25, 0.70, night);
  if (night > 0.02) {
    vec2 sg = p * 20.0, sid = floor(sg);
    float sh = hash(sid);
    vec2 sc = fract(sg) - 0.5 - (vec2(hash(sid + 1.3), hash(sid + 2.7)) - 0.5) * 0.7;
    float star = (1.0 - smoothstep(0.0, 0.10, length(sc))) * step(0.86, sh);
    gCol += vec3(1.0, 0.97, 0.86) * star * night * (0.35 + 1.1 * B)
          * (0.5 + 0.5 * sin(bb * 2.0 + sh * 40.0));

    float au = 0.0;
    for (int i = 0; i < 2; i++) {
      float fi = float(i);
      float o = sin(p.x * (3.0 + fi * 2.5) + bb * (0.18 + 0.09 * fi)) * 0.055;
      float t = (p.y - (0.30 - fi * 0.08) - o) / (0.024 + 0.026 * fi);
      au += exp(-t * t) * (0.5 + 0.5 * sin(p.x * 8.0 - bb * 0.35));
    }
    gCol += hsv(fract(H + 0.35), 0.85, 1.0) * au * night * p_aliens * 0.55;

    vec2 mp = p - vec2(-WX * 0.62, 0.30);
    draw(length(mp) - 0.075 * smoothstep(0.15, 0.6, night),
         mix(hsv(fract(H + 0.12), 0.40, 0.95), vec3(0.92), 0.25));
    draw(abs(sdEll(rot(0.35) * mp, vec2(0.15, 0.035))) - 0.005 * smoothstep(0.2, 0.7, night),
         hsv(fract(H + 0.08), 0.55, 0.85));
  }
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    if (nv * p_aliens > 0.25 && fi + 0.5 < p_aliens * 3.0) {
      float sd = hash(vec2(fi, 3.0));
      float sx = mod(bb * (0.035 + 0.05 * sd) + sd * 4.0, 2.4 * WX) - 1.2 * WX;
      float syy = 0.16 + 0.20 * hash(vec2(fi, 8.0)) + 0.025 * sin(bb * 0.8 + fi * 2.0);
      saucer(p - vec2(sx, syy), bb * 0.5 + sd, hsv(fract(H + 0.4 + 0.1 * fi), 0.9, 1.0));
    }
  }

  // ---- ground: a far ridge for depth, then the hill itself. The ridge is hazed towards
  // the sky it sits in, or it reads as a grey road rather than as distance.
  float m2 = gslope(p.x) * 0.55, lw0 = gLw;
  gLw *= 0.4 * (1.0 - clean);              // a distant ridge is barely inked, and not at all
  if (crayon < 0.5)                        // when clean; a toddler doesn't draw one at all
    draw((p.y - (gy(p.x) * 0.55 + 0.04)) / sqrt(1.0 + m2 * m2),
         mix(mix(vec3(0.30, 0.42, 0.30), vec3(0.05, 0.06, 0.14), night) * 0.8,
             gCol, mix(0.75, 0.55, clean)));
  gLw = lw0;
  float m = gslope(p.x), dg = (p.y - gy(p.x)) / sqrt(1.0 + m * m);
  vec3 hillC = mix(vec3(0.38, 0.52, 0.19), vec3(0.05, 0.07, 0.15), night);
  hillC = mix(hillC, vec3(0.50, 0.24, 0.11), dusk * 0.55);
  hillC *= mix(0.82 + 0.34 * vnoise(p * vec2(26.0, 70.0)), 1.0, clean);   // flat fill when clean
  hillC *= 1.0 - 0.45 * smoothstep(0.0, 0.55, -dg);                // darker deeper in
  hillC += hillC * 0.5 * (1.0 - smoothstep(0.0, 0.020, -dg));      // a lit lip along the ridge
  draw(dg, hillC);

  // ---- where everyone is: up the hill over p_climb bars, then the sun rolls back
  float cph = fract(bb / max(p_climb * 4.0, 4.0));
  float up = cph < 0.85 ? cph / 0.85 : (1.0 - cph) / 0.15;
  float falling = step(0.85, cph);
  float bx = mix(-WX * 0.86, WX * 0.60, up), by = gy(bx), sl = atan(gslope(bx));
  vec2 dir = vec2(cos(sl), sin(sl)), nrm = vec2(-sin(sl), cos(sl));
  float R = 0.095 * p_size, BS = 0.072 * p_size;
  vec2 contact = vec2(bx, by) + dir * (BS * 1.25 + R);
  vec2 sunP = contact + nrm * R;
  vec2 bodyP = vec2(bx, by) + nrm * BS * 1.30;         // stands on the slope, feet on the line

  // C Change, at night, takes the sun away for a while. Nobody tells the beetle.
  float abd = smoothstep(0.5, 0.9, C) * smoothstep(0.35, 0.75, night) * p_aliens;
  vec2 sunA = sunP + vec2(0.10 * sin(bb * 0.6), 0.52) * abd;

  // ---- the sun
  vec2 s = p - sunA;
  float rs = length(s), roll = -up * 1.35 / max(R, 0.02);
  float dropAmt = step(6.5, u_scene) * step(u_scene, 7.5) * (1.0 - smoothstep(0.0, 8.0, u_since));
  float heat = 0.35 + 1.1 * A + 1.5 * dropAmt;
  gCol += hsv(H, 0.72, 1.0) * exp(-max(0.0, rs - R) * (30.0 - 11.0 * A)) * heat * (0.30 + 0.55 * night);
  gCol += hsv(fract(H + 0.05), 0.85, 1.0) * pow(max(0.0, sin((atan(s.y, s.x) + roll * 0.2) * 9.0)), 6.0)
        * (1.0 - smoothstep(R * 1.02, R * 2.1, rs)) * heat * 0.55;
  draw(rs - R, hsv(H, 0.70, 1.0));
  float sw = vnoise(rot(roll) * s / max(R, 0.02) * 3.2 + vec2(0.0, bb * 0.04));
  gCol = mix(gCol, hsv(fract(H + 0.04), 0.50, 1.0),                // flat blotches when clean,
             (1.0 - smoothstep(-gPx, gPx, rs - R))                 // soft granulation otherwise
             * smoothstep(mix(0.42, 0.53, clean), mix(0.78, 0.57, clean), sw) * 0.6);

  // Its face: squints and grimaces the higher it gets, goes wide when it's taken or dropped.
  vec2 f = s / max(R, 0.02);
  float shock = max(abd, falling), lidv = mix(0.55 * up, 0.0, shock);
  vec2 look = normalize(vec2(-0.6, mix(-0.55, 1.0, shock))) * 0.09;
  for (int i = 0; i < 2; i++) {
    vec2 e = f - vec2((float(i) * 2.0 - 1.0) * 0.33, 0.24);
    draw(sdEll(e, vec2(0.20, 0.27 - 0.13 * lidv)) * R, vec3(0.98, 0.96, 0.90));
    draw((length(e - look) - mix(0.085, 0.055, shock)) * R, vec3(0.05, 0.04, 0.06));
  }
  float curve = mix(0.55, -0.70, up), tx = clamp(f.x / 0.40, -1.0, 1.0);
  float dBar = max(abs(f.y - (-0.26 - curve * 0.26 * (1.0 - tx * tx))) - 0.075, abs(f.x) - 0.40);
  draw(mix(dBar, length((f - vec2(0.0, -0.28)) * vec2(1.0, 0.8)) - 0.17, shock) * R,
       vec3(0.13, 0.03, 0.05));
  float sweat = smoothstep(0.55, 0.9, up) * (0.35 + A);
  if (sweat > 0.08)
    draw((length((f - vec2(-0.66, 0.46 - fract(bb * 0.5) * 0.55)) * vec2(1.0, 0.72))
          - 0.09 * min(sweat, 1.0)) * R, vec3(0.62, 0.86, 1.0));

  // ---- the beetle. One full stride per A loop, kicking harder the louder A hits.
  vec2 b = rot(-sl) * (p - bodyP);
  float amp = clamp(p_legs * (0.25 + 1.6 * A), 0.0, 1.6);
  vec3 shell = mix(vec3(0.05, 0.06, 0.09),                         // near-black, with a sheen
                   hsv(fract(H + 0.45 + 0.09 * b.x / max(BS, 0.01)), 0.80, 0.42), 0.40);
  legs(b, BS, amp, bb / loopBeats(p_aloop) + 0.5, shell * 0.45);
  draw(sdEll(b, vec2(BS * 1.30, BS * 0.82)), shell);
  draw(max(abs(b.y) - BS * 0.05, sdEll(b, vec2(BS * 1.22, BS * 0.74))), shell * 0.45);
  draw(length(b - vec2(BS * 1.15, -BS * 0.10)) - BS * 0.46, shell * 1.1);
  draw(sdSeg(b, vec2(BS * 1.45, -BS * 0.05), vec2(BS * 1.95, BS * 0.30)) - BS * 0.07, shell * 0.8);
  draw(length(b - vec2(BS * 1.35, BS * 0.12)) - BS * 0.10, vec3(0.95, 0.93, 0.85));
  legs(b, BS, amp, bb / loopBeats(p_aloop), shell * 0.75);

  // ---- the beam, in front of everything
  if (abd > 0.02) {
    vec2 ab = vec2(sunA.x, sunA.y + 0.20 + 0.02 * sin(bb * 2.5));
    float t = clamp((ab.y - p.y) / max(ab.y - (contact.y - R), 1e-3), 0.0, 1.0);
    float halfw = mix(0.025, 0.11, t);
    float beam = (1.0 - smoothstep(halfw * 0.55, halfw, abs(p.x - mix(ab.x, contact.x, t))))
               * step(p.y, ab.y) * step(contact.y - R, p.y);
    gCol += hsv(fract(H + 0.30), 0.75, 1.0) * beam * abd * (0.55 + 0.45 * sin(p.y * 45.0 - bb * 7.0));
    saucer(p - ab, bb * 2.0, hsv(fract(H + 0.35), 0.9, 1.0));
  }

  // ---- ink, then whatever the hand does to the finished drawing
  float ink = clamp(gInk, 0.0, 1.0);
  if (crayon > 0.5) ink *= step(0.30, vnoise(p * 85.0));          // a line with gaps in it
  vec3 c = mix(gCol, crayon > 0.5 ? vec3(0.16, 0.11, 0.08)
                   : cup > 0.5    ? vec3(0.03, 0.03, 0.04)
                   : acid > 0.5   ? hsv(fract(H + 0.5), 0.95, 1.0)
                                  : vec3(0.05, 0.05, 0.06), ink);

  if (crayon > 0.5) {
    c = floor(clamp(c, 0.0, 1.0) * 4.0 + 0.5) / 4.0;              // eight crayons, at most
    float streak = vnoise(vec2((p.x + p.y) * 70.0, (p.x - p.y) * 25.0));
    c = mix(vec3(0.95, 0.93, 0.86), c, clamp(0.68 + 0.55 * streak, 0.0, 1.0));
    c *= 0.90 + 0.20 * vnoise(p * 170.0);                         // paper tooth
  } else if (cup > 0.5) {
    // An S-curve, or the sky and the hill land on the same tone and the whole thing is a desert.
    float l = smoothstep(0.10, 0.80, dot(c, vec3(0.299, 0.587, 0.114)));
    float dots = length(fract(rot(0.7) * p * 300.0) - 0.5);       // ben-day shading
    l *= 1.0 - 0.28 * smoothstep(l * 0.70, l * 0.70 + 0.10, dots);
    vec3 duo = mix(vec3(0.10, 0.08, 0.09), vec3(0.98, 0.93, 0.80), clamp(l, 0.0, 1.0));
    c = mix(duo, c * 0.5 + duo * 0.6, 0.22);
    c *= 0.92 + 0.15 * hash(p * 700.0 + u_time * 47.0);           // grain
    c = mix(c, vec3(0.95), step(0.9986, hash(vec2(floor(p.x * 260.0), floor(u_time * 22.0)))) * 0.45);
    c *= 1.0 - 0.32 * pow(clamp(length(p * vec2(0.9, 1.35)), 0.0, 1.0), 3.0);
  } else if (acid > 0.5) {
    float hs = H + p.x * 0.28 + p.y * 0.18 + bb * 0.02 + B * 0.6;
    float l = dot(c, vec3(0.33));
    c = mix(c, hsv(fract(hs), 0.85, 1.0) * (0.25 + 1.5 * l), 0.5);
    c = floor(pow(clamp(c, 0.0, 1.0), vec3(0.75)) * 6.0) / 6.0 + 0.05;
    c += hsv(fract(hs + 0.5), 0.95, 1.0) * ink * (0.3 + A) * 0.9;
  }
  return mix(c, vec3(1.0), dropAmt * 0.55 * kick());
}
