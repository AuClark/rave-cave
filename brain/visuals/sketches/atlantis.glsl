// Atlantis: Moses parts the sea and finds Atlantis, overrun by dolphins with thumbs.
// A cartoon drawn from 2D distance fields with ink outlines. The walls of water part
// over a cycle of beats (or through the song section, fully open by its end), hold,
// then crash shut; Moses raises his staff on the beat; the crystal spire of Atlantis
// pulses on the kick and throws rays up between the walls; dolphins leap across the gap
// giving thumbs up that pump on the kick. Params are p_* uniforms; ranges and defaults
// are in atlantis.json.
// Its cycle runs on u_cbeat, so its climax ("climax" in the JSON) can land on the drop.
uniform float p_cycle, p_open, p_section, p_dolphins, p_thumbs, p_glow, p_rays, p_punch,
              p_size, p_line, p_hue, p_follow, p_bright;

#define PI 3.1415927
#define TAU 6.2831853

mat2 R(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
float sdE(vec2 p, vec2 r) { return (length(p / r) - 1.0) * min(r.x, r.y); }
float sdC(vec2 p, vec2 a, vec2 b, float r) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - r;
}
float sdB(vec2 p, vec2 c, vec2 h) { vec2 d = abs(p - c) - h; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }

float g_lw;
float cov(float d) { return clamp(0.5 - d / u_px, 0.0, 1.0); }
void ink(inout vec3 col, float d, vec3 c) {
  col = mix(col, vec3(0.02, 0.025, 0.05), cov(d - g_lw));
  col = mix(col, c, cov(d));
}
void paint(inout vec3 col, float d, vec3 c) { col = mix(col, c, cov(d)); }

// ── Atlantis: steps, a columned temple with a dome, side towers, the crystal spire ──
void drawCity(inout vec3 col, vec2 p, float k, vec3 glowCol) {
  vec3 stone = vec3(0.78, 0.8, 0.72), shade = vec3(0.55, 0.6, 0.6), gold = vec3(0.95, 0.78, 0.35);
  float floorY = -0.3;
  for (int s = 0; s < 3; s++) {
    float fs = float(s);
    ink(col, sdB(p, vec2(0.0, floorY + 0.012 + fs * 0.022), vec2(0.2 - fs * 0.03, 0.011)), mix(stone, shade, fs * 0.2));
  }
  // Side towers with pointed roofs.
  for (int t = 0; t < 2; t++) {
    float sx = t == 0 ? -0.22 : 0.22;
    ink(col, sdB(p, vec2(sx, -0.19), vec2(0.028, 0.1)), shade);
    ink(col, max(abs(p.x - sx) * 1.6 + (p.y - 0.0) , -(p.y + 0.09 - 0.0)) , gold * 0.85);
    for (int w = 0; w < 3; w++) paint(col, sdB(p, vec2(sx, -0.25 + float(w) * 0.05), vec2(0.007, 0.012)), glowCol * (0.6 + 0.4 * k));
  }
  // The temple: columns, pediment, dome.
  float ty = floorY + 0.066;
  ink(col, sdB(p, vec2(0.0, ty + 0.005), vec2(0.13, 0.006)), stone);
  for (int c = 0; c < 6; c++) {
    float cx = -0.105 + float(c) * 0.042;
    ink(col, sdB(p, vec2(cx, ty + 0.055), vec2(0.009, 0.05)), stone);
  }
  ink(col, sdB(p, vec2(0.0, ty + 0.11), vec2(0.135, 0.008)), stone);
  ink(col, max(abs(p.x) * 0.45 + (p.y - (ty + 0.16)), -(p.y - (ty + 0.118))), stone * 0.95);
  ink(col, max(length(p - vec2(0.0, ty + 0.16)) - 0.06, -(p.y - (ty + 0.16))), gold);
  // Crystal spire, pulsing on the kick.
  vec2 cp = p - vec2(0.0, ty + 0.27);
  float cr = abs(cp.x) * 2.2 + abs(cp.y) - 0.06 * (1.0 + 0.15 * p_punch * k);
  ink(col, sdC(p, vec2(0.0, ty + 0.2), vec2(0.0, ty + 0.23), 0.004), gold);
  ink(col, cr * 0.45, mix(glowCol, vec3(1.0), 0.45 + 0.3 * k));
  col += glowCol * exp(-length(cp) * 14.0) * p_glow * (0.6 + 0.8 * p_punch * k);
}

// ── A dolphin, flying along its arc, thumb up ──
void drawDolphin(inout vec3 col, vec2 p, vec2 pos, float ang, float k, float flip) {
  vec2 q = R(-ang) * (p - pos) / 1.35;           // drawn 1.35x the shapes below
  q.y *= flip;
  q.y -= 2.5 * q.x * q.x;                                    // a curve along the body
  vec3 skin = vec3(0.45, 0.58, 0.72), belly = vec3(0.82, 0.88, 0.92);
  ink(col, sdC(q, vec2(0.01, 0.02), vec2(-0.02, 0.045), 0.007), skin * 0.85);                // dorsal fin
  ink(col, min(sdC(q, vec2(-0.065, 0.0), vec2(-0.092, 0.02), 0.007), sdC(q, vec2(-0.065, 0.0), vec2(-0.092, -0.02), 0.007)), skin * 0.85);  // flukes
  ink(col, sdC(q, vec2(0.06, -0.003), vec2(0.092, -0.008), 0.007), skin);                     // snout
  float body = sdE(q, vec2(0.075, 0.024));
  ink(col, body, mix(belly, skin, smoothstep(-0.012, 0.004, q.y)));
  paint(col, length(q - vec2(0.05, 0.006)) - 0.0045, vec3(0.02));
  paint(col, sdC(q, vec2(0.068, -0.012), vec2(0.082, -0.01), 0.0015), vec3(0.1));            // smile
  // A flipper-arm ending in a big thumbs up (the thumb points up in the world).
  float pump = 1.0 + 0.35 * p_punch * k;
  vec2 fist = vec2(0.022, -0.04);
  ink(col, sdC(q, vec2(0.005, -0.015), fist, 0.008), skin);
  vec2 up = R(-ang) * vec2(0.0, 1.0);
  up.y *= flip;
  float fr = 0.013 * p_thumbs;
  float thumb = sdC(q, fist + up * fr * 0.4, fist + up * (fr + 0.02 * p_thumbs * pump), 0.0055 * p_thumbs);
  ink(col, min(sdE(q - fist, vec2(fr, fr * 0.85)), thumb), vec3(0.62, 0.74, 0.86));
  paint(col, sdC(q, fist - vec2(fr * 0.6, 0.0), fist + vec2(fr * 0.4, 0.0), 0.0007), vec3(0.2, 0.3, 0.4));   // finger crease
}

vec3 content(vec2 uv) {
  float S = max(p_size, 0.05);
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) / S;
  p.y = -p.y;
  float b = u_beat, k = kick(), f = u_frac;
  g_lw = 0.0035 * p_line / S + 0.5 * u_px;
  vec3 glowCol = hsv(mix(0.5, u_hue, p_follow) + p_hue, 0.6, 1.0);

  // How far the sea is parted: over a cycle (part, hold, crash), by hand, or by section.
  float open = p_open;
  if (p_cycle > 0.0) {
    float s = fract(u_cbeat / p_cycle);
    open = smoothstep(0.0, 0.35, s) * (1.0 - smoothstep(0.88, 0.98, s));
  }
  if (p_section > 0.5) open = smoothstep(0.0, 0.85, u_sp);

  // ── Sky ──
  vec3 col = mix(vec3(0.1, 0.12, 0.25), vec3(0.02, 0.02, 0.08), clamp((p.y - 0.1) * 1.5, 0.0, 1.0));
  vec2 sg = floor(uv * vec2(u_aspect, 1.0) / u_px / 3.0);
  col += vec3(0.85) * step(0.997, hash(sg)) * step(0.15, p.y);
  col += glowCol * 0.15 * open * exp(-pow(p.x / 0.4, 2.0)) * exp(-max(p.y - 0.1, 0.0) * 4.0) * p_glow;

  // ── Seabed and Atlantis (seen where the sea has parted) ──
  float floorY = -0.3 + 0.01 * sin(p.x * 14.0);
  paint(col, p.y - floorY, vec3(0.62, 0.52, 0.36));
  paint(col, p.y - floorY + 0.03, vec3(0.5, 0.42, 0.3));
  drawCity(col, p, k, glowCol);
  // Rays from the crystal, rising between the walls.
  vec2 rc = p - vec2(0.0, -0.234 + 0.27);
  float ra = atan(rc.x, rc.y);
  float rays = pow(max(cos(ra * 9.0 + b * 0.5), 0.0), 6.0) * step(0.0, rc.y) * exp(-length(rc) * 2.5);
  col += glowCol * rays * 0.35 * p_rays * open * (1.0 + p_punch * k);

  // ── The walls of water ──
  float seaY = 0.14;
  float w = mix(-0.02, 0.36, open) * (1.0 + 0.35 * clamp(-p.y, 0.0, 1.0));      // wider at the bottom
  float ax = abs(p.x);
  float edgeWob = 0.012 * sin(p.y * 26.0 + b * PI) + 0.006 * sin(p.y * 61.0 - b * TAU);
  float we = w + edgeWob;
  float crest = seaY + 0.12 * open * exp(-max(ax - we, 0.0) * 9.0) + 0.008 * sin(p.x * 22.0 + b * PI);
  float inWater = step(we, ax) * step(p.y, crest);
  if (open < 0.02) inWater = step(p.y, seaY + 0.008 * sin(p.x * 22.0 + b * PI));
  float dIn = max(ax - we, 0.0);
  vec3 water = mix(vec3(0.2, 0.55, 0.7), vec3(0.03, 0.12, 0.3), smoothstep(0.0, 0.25, dIn));
  water *= 0.85 + 0.15 * sin(p.y * 45.0 + dIn * 30.0 - b * PI);                  // currents
  water = mix(water, vec3(0.02, 0.06, 0.18), smoothstep(0.0, -0.4, p.y) * 0.5);
  float wallMask = (1.0 - smoothstep(-u_px, u_px, we - ax)) * (1.0 - smoothstep(-u_px, u_px, p.y - crest));
  if (open < 0.02) wallMask = 1.0 - smoothstep(-u_px, u_px, p.y - (seaY + 0.008 * sin(p.x * 22.0 + b * PI)));
  col = mix(col, water, wallMask);
  // Foam on the wall faces and the crests.
  float foamEdge = (1.0 - smoothstep(0.0, 0.012, abs(ax - we))) * step(p.y, crest) * step(0.02, open);
  float foamTop = 1.0 - smoothstep(0.0, 0.01, abs(p.y - crest));
  col = mix(col, vec3(0.92, 0.97, 1.0), clamp(max(foamEdge, foamTop * step(we, ax)) * 0.9, 0.0, 1.0));
  // Spray off the crests.
  vec2 sp = vec2(p.x * 60.0, (p.y - crest) * 60.0 - b * 2.0);
  vec2 sc = floor(sp);
  float sdrop = (length(fract(sp) - 0.5 - (vec2(hash(sc + 4.1), hash(sc + 7.3)) - 0.5) * 0.5) - 0.18) / 60.0;
  float spray = cov(sdrop) * step(0.9, hash(sc)) * step(0.0, p.y - crest) * exp(-(p.y - crest) * 25.0) * step(we, ax + 0.03);
  col = mix(col, vec3(0.95), spray);

  // ── Dolphins leaping across the gap ──
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    if (fi >= p_dolphins) break;
    float T = 8.0;
    float s = fract((b + fi * T / max(p_dolphins, 1.0) + 0.37 * fi) / T);
    float dir = mod(fi, 2.0) < 0.5 ? 1.0 : -1.0;
    float x0 = -dir * (0.3 + 0.1 * hash(vec2(fi, 1.0))), x1 = dir * (0.3 + 0.1 * hash(vec2(fi, 2.0)));
    float H = 0.12 + 0.14 * hash(vec2(fi, 3.0));
    float base = seaY + 0.02 - 0.05 * mod(fi, 3.0);
    float lane = (fi - 0.5 * (p_dolphins - 1.0)) * 0.13 * max(u_aspect, 1.0) / S;   // each its own lane
    vec2 pos = vec2(mix(x0, x1, s) * 0.8 + lane, base + 4.0 * H * s * (1.0 - s));
    float ang = atan(4.0 * H * (1.0 - 2.0 * s), x1 - x0);
    drawDolphin(col, p, pos, ang, k, 1.0);
  }

  // ── Moses on his rock, staff raised on the beat ──
  vec2 mo = vec2(0.0, -0.4);
  ink(col, sdE(p - mo - vec2(0.0, -0.035), vec2(0.13, 0.05)), vec3(0.25, 0.22, 0.24));
  vec2 m = p - mo;
  float gust = sin(b * PI) * 0.01;
  vec3 robe = vec3(0.55, 0.33, 0.2), skin = vec3(0.85, 0.65, 0.5), white = vec3(0.95);
  float lift = 0.03 * (1.0 - f) * (1.0 - f);                      // the staff strikes up each beat
  vec2 hand = vec2(0.05, 0.13 + lift);
  vec2 sdir = normalize(vec2(0.25, 1.0));
  ink(col, sdC(m, hand - sdir * 0.1, hand + sdir * 0.13, 0.0045), vec3(0.45, 0.3, 0.15));      // staff
  col += glowCol * exp(-length(m - hand - sdir * 0.13) * 40.0) * (0.5 + p_punch * k) * p_glow;
  float robeD = max(sdE(m - vec2(gust, 0.035), vec2(0.045 + 0.2 * max(0.07 - m.y, 0.0) * 0.5, 0.075)), -m.y + 0.0);
  ink(col, robeD, robe);
  ink(col, sdC(m, vec2(0.012, 0.08), hand, 0.009), robe * 0.9);                                // arm up
  ink(col, sdC(m, vec2(-0.012, 0.08), vec2(-0.055, 0.1 + 0.5 * lift), 0.009), robe * 0.9);     // other arm
  ink(col, length(m - hand) - 0.011, skin);
  ink(col, length(m - vec2(-0.055, 0.1 + 0.5 * lift)) - 0.01, skin);
  ink(col, length(m - vec2(0.0, 0.125)) - 0.023, skin);                                        // head
  ink(col, sdE(m - vec2(0.004 + gust * 0.5, 0.092), vec2(0.017, 0.026)), white);               // beard
  paint(col, max(length(m - vec2(0.0, 0.132)) - 0.027, -(m.y - 0.135)), white * 0.92);         // hair
  paint(col, length(m - vec2(0.008, 0.131)) - 0.003, vec3(0.05));                              // eyes
  paint(col, length(m - vec2(-0.006, 0.131)) - 0.003, vec3(0.05));
  paint(col, sdC(m, vec2(-0.013, 0.14), vec2(-0.002, 0.143), 0.0015), white * 0.9);          // bushy brows
  paint(col, sdC(m, vec2(0.003, 0.143), vec2(0.015, 0.14), 0.0015), white * 0.9);

  return clamp(max(col, 0.0) * p_bright, 0.0, 1.0);
}
