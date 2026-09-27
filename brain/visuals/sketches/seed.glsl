// Seed: neon branching growths over a field of glowing flower dots, after Vincent Houze's
// video for Max Cooper. Each tree is a folded fractal (mirror, step, rotate, shrink) so it
// costs one short loop per pixel; trees sway in time and grow a level at a time through
// the song section. Params are p_* uniforms; ranges and defaults are in seed.json.
uniform float p_trees, p_levels, p_angle, p_ratio, p_sway, p_grow, p_blossom, p_width, p_glow,
              p_ground, p_hue, p_spread, p_sat, p_follow, p_beat;

#define TAU 6.2831853

float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float A = u_aspect;
  vec2 P = vec2(uv.x * A, 1.0 - uv.y);                      // y up, 0 at the bottom
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  vec3 col = vec3(0.01, 0.01, 0.04);

  // Ground: scattered glowing dots near the bottom.
  if (p_ground > 0.0) {
    vec2 g = vec2(P.x * 40.0, P.y * 40.0);
    vec2 gi = floor(g);
    float h = hash(gi);
    float band = 1.0 - smoothstep(0.05, 0.3, P.y);
    if (h < p_ground * band) {
      vec2 o = vec2(hash(gi + 1.3), hash(gi + 2.1)) * 0.6 + 0.2;
      float d = length(fract(g) - o);
      float tw = 0.6 + 0.4 * sin(t * TAU * 0.5 + h * 40.0);
      col += hsv(hue0 + p_spread * hash(gi + 5.0), p_sat, 1.0) * (1.0 - smoothstep(0.08, 0.28, d)) * tw * (0.7 + 0.6 * k);
    }
  }

  // Trees: one per slot across the surface.
  float n = max(1.0, floor(p_trees));
  float slot = A / n;
  float si = floor(P.x / slot);
  float lv = max(1.0, p_levels) * mix(1.0, clamp(0.35 + u_sp, 0.0, 1.0), p_grow);
  float best = 1e3, bestLv = 0.0, tip = 1e3;
  for (int s = -1; s <= 1; s++) {                           // neighbours too: trees overlap slots
    float id = si + float(s);
    if (id < 0.0 || id >= n) continue;
    float hx = hash(vec2(id, 3.0));
    vec2 q = P - vec2((id + 0.5) * slot + (hx - 0.5) * slot * 0.4, 0.02);
    float H = (0.16 + 0.08 * hash(vec2(id, 4.0))) * (1.0 + 0.04 * k);
    q /= H;
    float sc = 1.0;
    float d = sdSeg(q, vec2(0.0), vec2(0.0, 1.0));
    float dl = 0.0;
    float ang = p_angle + 0.25 * (hash(vec2(id, 6.0)) - 0.5);
    for (int i = 0; i < 10; i++) {
      float fi = float(i);
      if (fi >= lv) break;
      float sway = p_sway * 0.12 * sin(t * TAU / 8.0 + fi * 0.7 + id);
      q.y -= 1.0;
      q.x = abs(q.x);
      float a = ang * (0.75 + 0.5 * hash(vec2(id, fi + 11.0))) + sway;   // uneven, like coral
      q = mat2(cos(a), sin(a), -sin(a), cos(a)) * q;     // rotate by -a, so branches lean outwards
      q /= p_ratio; sc /= p_ratio;
      float part = clamp(lv - fi, 0.0, 1.0);                  // the newest level grows in
      float di = sdSeg(q, vec2(0.0), vec2(0.0, part)) / sc;
      if (di < d) { d = di; dl = fi + 1.0; }
      if (fi + 1.0 >= lv - 0.001) {                          // blossoms sized to their branch
        float tw = (length(q - vec2(0.0, part)) - 0.5 * p_blossom) / sc * H;
        if (tw < tip) tip = tw;
      }
    }
    d *= H;
    if (d < best) { best = d; bestLv = dl; }
  }
  float w = max(p_width * (1.0 - bestLv / 12.0), u_px);
  float line = 1.0 - smoothstep(w - u_px, w + u_px, best);
  float glow = p_glow * w * w / (best * best + w * w) * 0.5;
  vec3 bc = hsv(hue0 + p_spread * bestLv / 8.0, p_sat, 1.0);
  col += bc * (line + glow);
  if (p_blossom > 0.0) col += hsv(hue0 + p_spread * 0.9 + 0.1, p_sat, 1.0) * (1.0 - smoothstep(-u_px, u_px, tip)) * (0.8 + 0.6 * k);
  return 1.0 - exp(-col * 1.4);
}
