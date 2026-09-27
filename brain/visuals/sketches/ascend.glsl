// Ascend: energy climbing a pyramid face to the capstone. Put it on a surface covering one
// face: with Triangle on it clips itself to the face (apex at the top middle), so no masks
// are needed. Bands rise up the face, rows of glyphs light up as the charge passes, the edges
// run with light, and the charge level climbs through a BUILD and hits the apex on the DROP.
// Params are p_* uniforms; ranges and defaults are in ascend.json.
uniform float p_tri, p_edges, p_level, p_build, p_drop, p_bands, p_speed, p_bwidth, p_glyphs,
              p_rows, p_gspeed, p_gwidth, p_apex, p_hue, p_spread, p_sat, p_follow, p_beat;

#define TAU 6.2831853

float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// A made-up hieroglyph in a unit cell: strokes on a 3x3 grid chosen by hash, maybe an eye.
float glyph(vec2 q, vec2 id, float w, float px) {
  float d = 1e3;
  for (int i = 0; i < 12; i++) {
    float fi = float(i);
    if (hash(id + vec2(fi * 7.13, 1.9)) < 0.58) continue;
    float row = mod(fi, 3.0), col = floor(mod(fi, 6.0) / 3.0);
    vec2 a = fi < 5.5 ? vec2(0.2 + 0.3 * col, 0.2 + 0.3 * row) : vec2(0.2 + 0.3 * row, 0.2 + 0.3 * col);
    vec2 b = fi < 5.5 ? a + vec2(0.3, 0.0) : a + vec2(0.0, 0.3);
    d = min(d, sdSeg(q, a, b));
  }
  if (hash(id + 3.3) > 0.8) d = min(d, abs(length((q - 0.5) * vec2(1.0, 1.6)) - 0.2));
  return 1.0 - smoothstep(w - px, w + px, d);
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float h = 1.0 - uv.y;                                  // 0 at the base, 1 at the apex
  float X = (uv.x - 0.5) * u_aspect;
  float hw = 0.5 * u_aspect;
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  vec3 gold = hsv(hue0, p_sat, 1.0), cyan = hsv(hue0 + p_spread, p_sat, 1.0);

  // The face: a triangle, apex top middle. dtri < 0 inside (surface units).
  float dtri = (abs(X) - (1.0 - h) * hw) / sqrt(1.0 + hw * hw);
  float face = p_tri > 0.5 ? 1.0 - smoothstep(-u_px, u_px, dtri) : 1.0;

  // Charge level: base, climbing through BUILD / PREDROP, full on DROP.
  float L = p_level;
  bool drop = abs(u_scene - 7.0) < 0.5;
  if (abs(u_scene - 4.0) < 0.5 || abs(u_scene - 6.0) < 0.5) L = mix(L, 1.0, p_build * u_sp);
  float flash = 0.0;
  if (drop) { L = mix(L, 1.05, p_drop); flash = p_drop * exp(-u_since * 0.8); }
  L += 0.03 * k;
  float soft = 0.015 + u_px;
  float charged = 1.0 - smoothstep(L - soft, L + soft, h);
  float front = exp(-abs(h - L) * 40.0) * step(L, 1.0);

  // Rising bands.
  float bv = fract(h * p_bands - t * p_speed);
  float e = u_px * p_bands + 0.002;
  float band = p_bands > 0.5 ? smoothstep(0.0, e, bv) * (1.0 - smoothstep(p_bwidth, p_bwidth + e, bv)) : 0.0;

  // Glyph rows scrolling up.
  float rows = max(2.0, p_rows);
  vec2 g = vec2(X * rows, h * rows - t * p_gspeed);
  vec2 id = floor(g), q = fract(g);
  q.y = 1.0 - q.y;
  float gl = p_glyphs > 0.0 && hash(id + 9.1) < p_glyphs ? glyph(q, id, p_gwidth * 0.5, u_px * rows) : 0.0;
  float glit = 0.25 + 0.75 * charged + 1.5 * exp(-abs(h - L) * 12.0);

  // Edges of the face, with light running up them.
  float edge = 0.0;
  if (p_tri > 0.5) {
    float ew = 0.004 + 0.004 * k;
    float el = 1.0 - smoothstep(ew - u_px, ew + u_px, abs(dtri));
    float run = 0.35 + 0.65 * pow(0.5 + 0.5 * cos(TAU * (h * 3.0 - t * 0.5)), 6.0);
    edge = p_edges * el * run * (0.6 + 0.8 * charged);
  }

  // Capstone glow.
  vec2 ap = vec2(X, h - 1.0);
  float apex = p_apex * exp(-length(ap) * (6.0 - 3.0 * flash)) * (0.3 + 0.9 * smoothstep(0.6, 1.0, L)) * (1.0 + k);

  vec3 col = gold * band * (0.12 + 0.6 * charged)
           + cyan * gl * glit * 0.8
           + gold * front * 0.9
           + gold * charged * 0.06
           + vec3(1.0, 0.95, 0.8) * (edge + apex)
           + gold * flash * 0.5;
  return (1.0 - exp(-col * 1.4)) * face;
}
