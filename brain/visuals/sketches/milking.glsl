// Milking: two greys milking a dancing cow under their saucer. A cartoon drawn from 2D
// distance fields with ink outlines. Everything is on the beat: the cow bobs, sways,
// stamps its legs in pairs, head-bops and swishes its tail; the greys take turns, one
// squirt per beat, into a bucket that fills over a cycle of beats; the saucer's rim
// lights chase and its tractor beam flickers on the kick. Params are p_* uniforms;
// ranges and defaults are in milking.json.
uniform float p_dance, p_size, p_fill, p_beam, p_lights, p_line, p_stars, p_moon,
              p_punch, p_follow, p_hue, p_bright;

#define PI 3.1415927
#define TAU 6.2831853

mat2 R(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
float sdE(vec2 p, vec2 r) { return (length(p / r) - 1.0) * min(r.x, r.y); }   // ellipse (approx.)
float sdC(vec2 p, vec2 a, vec2 b, float r) {                                    // capsule
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - r;
}
float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

float g_lw;                                    // ink line width
float cov(float d) { return clamp(0.5 - d / u_px, 0.0, 1.0); }
// A filled shape with an ink outline.
void ink(inout vec3 col, float d, vec3 c) {
  col = mix(col, vec3(0.03, 0.025, 0.04), cov(d - g_lw));
  col = mix(col, c, cov(d));
}
void paint(inout vec3 col, float d, vec3 c) { col = mix(col, c, cov(d)); }

// The cow's frame: position, bob and sway. Local coordinates face right, y up.
vec2 g_cow; float g_bob, g_sway;
vec2 toCow(vec2 p) { return R(-g_sway) * (p - g_cow - vec2(0.0, g_bob)); }
vec2 fromCow(vec2 q) { return g_cow + vec2(0.0, g_bob) + R(g_sway) * q; }

void drawGrey(inout vec3 col, vec2 p, vec2 base, float facing, float bob, vec2 hand) {
  vec3 skin = vec3(0.62, 0.69, 0.66);
  vec2 q = p - base - vec2(0.0, bob);
  q.x *= facing;
  // Kneeling body, arm reaching to the teat, big head, black almond eyes.
  ink(col, sdC(q, vec2(0.0, 0.0), vec2(0.004, 0.055), 0.018), skin * 0.92);
  vec2 sh = base + vec2(0.0, bob) + vec2(0.012 * facing, 0.05);
  ink(col, sdC(p, sh, hand, 0.0055), skin * 0.95);
  ink(col, length(p - hand) - 0.009, skin);
  float head = smin(sdE(q - vec2(0.0, 0.115), vec2(0.048, 0.05)), sdE(q - vec2(0.006, 0.075), vec2(0.02, 0.018)), 0.02);
  ink(col, head, skin);
  for (int e = 0; e < 2; e++) {
    float s = e == 0 ? 1.0 : -1.0;
    vec2 eq = R(s * -0.55) * (q - vec2(0.012 + s * 0.02, 0.108));
    float eye = sdE(eq, vec2(0.02, 0.0085));
    paint(col, eye, vec3(0.02));
    paint(col, length(eq - vec2(0.006, 0.003)) - 0.0028, vec3(0.9));     // glint
  }
  paint(col, sdC(q, vec2(0.008, 0.078), vec2(0.018, 0.078), 0.0012), vec3(0.2));   // mouth
}

vec3 content(vec2 uv) {
  float S = max(p_size, 0.05);
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) / S;
  p.y = -p.y;
  float b = u_beat, k = kick(), f = u_frac;
  float D = p_dance;
  g_lw = 0.0035 * p_line / S + 0.5 * u_px;
  vec3 beamCol = hsv(mix(0.36, u_hue, p_follow) + p_hue, 0.75, 1.0);

  // ── Sky, stars, moon ──
  vec3 col = mix(vec3(0.05, 0.05, 0.14), vec3(0.01, 0.01, 0.04), clamp(p.y + 0.3, 0.0, 1.0));
  vec2 sg = floor(uv * vec2(u_aspect, 1.0) / u_px / 3.0);
  col += vec3(0.9) * step(0.996, hash(sg)) * (0.6 + 0.4 * sin(b * 2.0 + hash(sg + 3.0) * 30.0)) * p_stars * step(-0.2, p.y);
  float moon = length(p - vec2(-0.5, 0.33)) - 0.06;
  col += vec3(0.9, 0.9, 0.75) * exp(-max(moon, 0.0) * 25.0) * 0.12 * p_moon;
  paint(col, moon, vec3(0.93, 0.92, 0.8) * p_moon + col * (1.0 - p_moon));
  paint(col, length(p - vec2(-0.515, 0.345)) - 0.012, vec3(0.8, 0.79, 0.68) * p_moon + col * (1.0 - p_moon));
  paint(col, length(p - vec2(-0.48, 0.31)) - 0.008, vec3(0.82, 0.8, 0.7) * p_moon + col * (1.0 - p_moon));

  // ── Saucer and beam ──
  vec2 sc = vec2(0.02 * sin(TAU * b / 16.0), 0.315 + 0.008 * sin(TAU * b / 4.0));
  float beamW = mix(0.09, 0.3, clamp((sc.y - p.y) / 0.6, 0.0, 1.0));
  float inBeam = step(p.y, sc.y) * step(-0.23, p.y) * (1.0 - smoothstep(beamW - 0.01, beamW + 0.01, abs(p.x - sc.x)));
  float flick = 0.75 + 0.25 * sin(p.y * 60.0 - b * TAU) ;
  col += beamCol * inBeam * 0.16 * p_beam * flick * (1.0 + p_punch * k);

  // ── Ground ──
  float gy = -0.235 + 0.015 * sin(p.x * 3.0 + 0.5);
  paint(col, p.y - gy, vec3(0.05, 0.12, 0.06));
  col += beamCol * 0.12 * p_beam * exp(-pow((p.x - sc.x) / 0.3, 2.0)) * smoothstep(gy - 0.03, gy, p.y) * step(p.y, gy);

  // ── Cow ──
  g_cow = vec2(0.0, 0.0);
  float bounce = abs(sin(PI * b));                        // up on every beat
  g_bob = 0.022 * D * (1.0 - bounce);
  g_sway = 0.07 * D * sin(PI * b);
  vec3 white = vec3(0.96, 0.94, 0.89), blk = vec3(0.09, 0.07, 0.07), pink = vec3(0.96, 0.64, 0.68);
  vec2 cq = toCow(p);
  // Legs stamp in pairs: back pair on one beat, front pair on the next.
  float even = mod(floor(b), 2.0);
  float lift = 0.022 * D * (1.0 - f) * (1.0 - f);
  float liftB = even < 0.5 ? lift : 0.0, liftF = even > 0.5 ? lift : 0.0;
  vec2 lb1 = vec2(-0.13, -0.2 + liftB), lb2 = vec2(-0.085, -0.2);
  vec2 lf1 = vec2(0.105, -0.2 + liftF), lf2 = vec2(0.15, -0.2);
  vec3 cfar = white * 0.82;
  // Tail swish.
  float sw = sin(TAU * b * 0.5) * D;
  vec2 t0 = vec2(-0.19, 0.04), t1 = vec2(-0.25 + 0.02 * sw, -0.02), t2 = vec2(-0.25 + 0.05 * sw, -0.09);
  ink(col, min(sdC(cq, t0, t1, 0.006), sdC(cq, t1, t2, 0.006)), white);
  ink(col, sdE(cq - t2 - vec2(0.0, -0.012), vec2(0.014, 0.02)), blk);
  // Far legs.
  ink(col, sdC(cq, vec2(-0.085, -0.05), lb2, 0.021), cfar);
  ink(col, sdC(cq, vec2(0.15, -0.05), lf2, 0.021), cfar);
  ink(col, sdE(cq - lb2 - vec2(0.0, -0.008), vec2(0.022, 0.012)), blk);
  ink(col, sdE(cq - lf2 - vec2(0.0, -0.008), vec2(0.022, 0.012)), blk);
  // Body and spots.
  float body = sdE(cq, vec2(0.21, 0.105));
  ink(col, body, white);
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    vec2 sp = vec2(-0.16 + 0.065 * fi + 0.02 * (hash(vec2(fi, 1.0)) - 0.5), 0.04 * (hash(vec2(fi, 2.0)) - 0.3));
    float spot = sdE(R(hash(vec2(fi, 3.0)) * 3.0) * (cq - sp), vec2(0.035 + 0.02 * hash(vec2(fi, 4.0)), 0.028 + 0.015 * hash(vec2(fi, 5.0))));
    paint(col, max(body + g_lw * 0.5, spot), blk);
  }
  // Udder and teats; the teat being milked is pulled down on its beat.
  vec2 ud = vec2(-0.03, -0.1);
  ink(col, sdE(cq - ud, vec2(0.055, 0.035)), pink);
  float pull = 0.012 * smoothstep(0.0, 0.15, f) * (1.0 - smoothstep(0.3, 0.6, f));
  vec2 teatL = ud + vec2(-0.025, -0.05 - (even < 0.5 ? pull : 0.0));
  vec2 teatR = ud + vec2(0.025, -0.05 - (even > 0.5 ? pull : 0.0));
  ink(col, sdC(cq, ud + vec2(-0.025, -0.02), teatL, 0.009), pink * 0.95);
  ink(col, sdC(cq, ud + vec2(0.025, -0.02), teatR, 0.009), pink * 0.95);
  // Near legs.
  ink(col, sdC(cq, vec2(-0.13, -0.05), lb1, 0.022), white);
  ink(col, sdC(cq, vec2(0.105, -0.05), lf1, 0.022), white);
  ink(col, sdE(cq - lb1 - vec2(0.0, -0.008), vec2(0.023, 0.012)), blk);
  ink(col, sdE(cq - lf1 - vec2(0.0, -0.008), vec2(0.023, 0.012)), blk);
  // Head, head-bopping on the beat.
  float bop = 0.25 * D * (bounce - 0.5);
  vec2 hq = R(-bop) * (cq - vec2(0.19, 0.06));
  ink(col, sdC(hq, vec2(-0.005, 0.07), vec2(-0.03, 0.115), 0.008), vec3(0.9, 0.86, 0.72));      // horns
  ink(col, sdC(hq, vec2(0.055, 0.07), vec2(0.08, 0.115), 0.008), vec3(0.9, 0.86, 0.72));
  ink(col, sdE(R(0.5) * (hq - vec2(-0.02, 0.05)), vec2(0.03, 0.013)), white);                   // ears
  ink(col, sdE(R(-0.5) * (hq - vec2(0.085, 0.05)), vec2(0.03, 0.013)), white);
  ink(col, sdE(hq - vec2(0.03, 0.02), vec2(0.06, 0.065)), white);
  paint(col, max(sdE(hq - vec2(0.03, 0.02), vec2(0.06, 0.065)) + g_lw * 0.5, sdE(hq - vec2(0.0, 0.05), vec2(0.03, 0.025))), blk);
  ink(col, sdE(hq - vec2(0.03, -0.03), vec2(0.05, 0.034)), pink);                               // muzzle
  paint(col, sdE(hq - vec2(0.012, -0.028), vec2(0.007, 0.01)), pink * 0.55);
  paint(col, sdE(hq - vec2(0.048, -0.028), vec2(0.007, 0.01)), pink * 0.55);
  float blink = step(0.97, fract(b / 8.0));
  for (int e = 0; e < 2; e++) {
    vec2 ec = vec2(e == 0 ? 0.008 : 0.052, 0.035);
    ink(col, sdE(hq - ec, vec2(0.013, 0.015 * (1.0 - blink) + 0.002)), vec3(0.98));
    paint(col, length(hq - ec - vec2(0.002, -0.002)) - 0.007 * (1.0 - blink), vec3(0.02));
  }
  // Collar bell, jingling.
  vec2 bell = vec2(0.17, -0.035) + vec2(0.006 * sin(TAU * b), 0.0);
  ink(col, sdC(cq, vec2(0.14, 0.0), vec2(0.2, -0.02), 0.004), vec3(0.7, 0.15, 0.12));
  ink(col, length(cq - bell) - 0.017, vec3(0.95, 0.75, 0.2));

  // ── Bucket, filling over the cycle ──
  vec2 bk = vec2(-0.03, -0.2);
  vec2 bq = p - bk;
  float hw = mix(0.038, 0.05, clamp((bq.y + 0.03) / 0.06, 0.0, 1.0));
  float bucket = max(abs(bq.x) - hw, abs(bq.y) - 0.03);
  ink(col, bucket, vec3(0.72, 0.74, 0.78));
  paint(col, sdC(bq, vec2(-0.044, 0.03), vec2(0.044, 0.03), 0.004), vec3(0.45, 0.47, 0.5));
  float lvl = fract(b / max(p_fill, 1.0));
  paint(col, max(bucket + g_lw, bq.y - (-0.028 + 0.052 * lvl)), vec3(0.97, 0.97, 0.94));
  paint(col, sdC(bq, vec2(-0.03, 0.01), vec2(-0.03, -0.02), 0.003), vec3(0.85));

  // ── The greys, taking turns, and the squirt ──
  vec2 tipL = fromCow(teatL), tipR = fromCow(teatR);
  vec2 top = bk + vec2(0.0, 0.03);
  float gbL = 0.008 * (even < 0.5 ? 1.0 - f : 0.3);
  float gbR = 0.008 * (even > 0.5 ? 1.0 - f : 0.3);
  drawGrey(col, p, vec2(-0.19, -0.235), 1.0, gbL, tipL + vec2(-0.004, 0.0));
  drawGrey(col, p, vec2(0.14, -0.235), -1.0, gbR, tipR + vec2(0.004, 0.0));
  vec2 tip = even < 0.5 ? tipL : tipR;
  vec2 a0 = mix(tip, top, smoothstep(0.2, 0.45, f)), a1 = mix(tip, top, smoothstep(0.0, 0.2, f));
  float squirt = sdC(p, a0, a1, 0.0065);
  paint(col, squirt + (f > 0.45 ? 1.0 : 0.0), vec3(1.0, 1.0, 0.97));
  float splash = (1.0 - smoothstep(0.18, 0.5, f)) * step(0.15, f);
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    vec2 dp = top + vec2((fi - 1.0) * 0.014, 0.01 + 0.025 * f * (1.0 + fi * 0.3));
    paint(col, length(p - dp) - 0.006 * splash - 0.0001 + (splash > 0.0 ? 0.0 : 1.0), vec3(1.0));
  }

  // ── Saucer on top ──
  vec2 sq = p - sc;
  ink(col, sdE(sq - vec2(0.0, 0.025), vec2(0.075, 0.055)), mix(vec3(0.35, 0.8, 0.85), vec3(0.6, 0.95, 1.0), 0.5 + 0.5 * sq.y / 0.06) * 0.8);
  // A little grey pilot in the dome.
  paint(col, sdE(sq - vec2(0.0, 0.04), vec2(0.022, 0.024)), vec3(0.45, 0.55, 0.55));
  paint(col, sdE(R(-0.5) * (sq - vec2(-0.009, 0.04)), vec2(0.009, 0.004)), vec3(0.02));
  paint(col, sdE(R(0.5) * (sq - vec2(0.009, 0.04)), vec2(0.009, 0.004)), vec3(0.02));
  ink(col, sdE(sq, vec2(0.2, 0.034)), mix(vec3(0.42, 0.44, 0.5), vec3(0.8, 0.82, 0.88), smoothstep(-0.03, 0.03, sq.y)));
  for (int i = 0; i < 8; i++) {
    float fi = float(i);
    vec2 lp = vec2(-0.16 + fi * 0.32 / 7.0, -0.006);
    float on = step(fract((fi - floor(b * 2.0)) / 4.0), 0.3);      // chase, two steps a beat
    vec3 lc = hsv(fi / 8.0 + b * 0.05, 0.8, 1.0);
    col += lc * exp(-length(p - sc - lp) * 90.0) * 0.8 * on * p_lights;
    paint(col, length(p - sc - lp) - 0.009, mix(lc * 0.3, lc, on));
  }

  col = max(col, 0.0) * p_bright;
  return clamp(col, 0.0, 1.0);
}
