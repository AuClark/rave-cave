// Sacred geometry, in thin gold lines. Five modes:
//   0 Sierpinski triangle zooming forever into its apex (one level per 1/zoom beats)
//   1 Flower of Life     2 Metatron's Cube     3 golden spiral     4 pyramid tunnel
// Params are p_* uniforms; ranges and defaults are in sacred.json.
uniform float p_mode, p_scale, p_spin, p_zoom, p_detail, p_width, p_glow, p_fill, p_pulse,
              p_hue, p_spread, p_sat, p_follow, p_beat;

#define TAU 6.2831853
#define PI 3.1415927

float sdTri(vec2 p, float r) {                    // equilateral, apex up, half side r (Inigo Quilez)
  const float k = 1.7320508;
  p.x = abs(p.x) - r;
  p.y = p.y + r / k;
  if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
  p.x -= clamp(p.x, -2.0 * r, 0.0);
  return -length(p) * sign(p.y);
}
float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) / p_scale;
  p.y = -p.y;
  float sa = t * p_spin * TAU / 32.0;
  p = mat2(cos(sa), sin(sa), -sin(sa), cos(sa)) * p;
  float px = u_px / p_scale;
  float w = max(p_width / p_scale, px) * (1.0 + 0.4 * k);
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  float N = floor(p_detail + 0.5);

  float d = 1e3;          // distance to the nearest line
  float lvl = 0.0;        // which ring / level that line belongs to (for colour and pulse)
  float fill = 0.0;       // solid areas

  if (p_mode < 0.5) {
    // Sierpinski: skewed coordinates on the triangle A(-.5,-.2887) B(.5,-.2887) C(0,.5774).
    // Zooming by 2 into the apex is self-similar, so it loops; visual level = i - f.
    float f = fract(t * p_zoom);
    float z = exp2(f);
    vec2 C = vec2(0.0, 0.57735);
    vec2 pp = C + (p - C) / z;
    float v = (pp.y + 0.288675) / 0.866025, u = pp.x + 0.5 - 0.5 * v;
    float outer = sdTri(pp, 0.5) * z;
    d = abs(outer); lvl = -f;
    float inTri = 1.0 - smoothstep(-px, px, outer);
    float s = 1.0, hole = -1.0;
    for (int i = 0; i < 10; i++) {
      float fi = float(i);
      if (fi >= N) break;
      u *= 2.0; v *= 2.0; s *= 0.5;
      float sdh = max(max(u - 1.0, v - 1.0), 1.0 - u - v) * s * 0.866 * z;
      if (abs(sdh) < d) { d = abs(sdh); lvl = fi + 1.0 - f; }
      if (u >= 1.0) u -= 1.0;
      else if (v >= 1.0) v -= 1.0;
      else if (u + v >= 1.0) { hole = fi; break; }
    }
    fill = hole < 0.0 ? inTri * p_fill : 0.0;
  } else if (p_mode < 1.5) {
    // Flower of Life: circles of radius R centred on a hex lattice of spacing R.
    float R = 0.1 * (1.0 + 0.04 * k);
    float jj = p.y / (R * 0.866025), ii = p.x / R - 0.5 * jj;
    vec2 base = floor(vec2(ii, jj));
    for (int a = -2; a <= 2; a++) for (int b = -2; b <= 2; b++) {
      vec2 ij = base + vec2(float(a), float(b));
      vec2 c = vec2((ij.x + 0.5 * ij.y) * R, ij.y * 0.866025 * R);
      float rc = length(c) / R;
      if (rc > N - 0.5) continue;
      float dc = abs(length(p - c) - R);
      if (dc < d) { d = dc; lvl = rc; }
    }
    float edge = abs(length(p) - (N + 0.5) * R);
    if (edge < d) { d = edge; lvl = N; }
    fill = p_fill * 0.25 * (1.0 - smoothstep((N + 0.5) * R - px, (N + 0.5) * R + px, length(p)));
  } else if (p_mode < 2.5) {
    // Metatron's Cube: 13 circles (centre, 6 at 2r, 6 at 4r) and every line between centres.
    float r = 0.07 * (1.0 + 0.04 * k);
    for (int i = 0; i < 13; i++) {
      float fi = float(i);
      float ai = (mod(fi - 1.0, 6.0)) * PI / 3.0 + PI / 6.0;
      vec2 ci = fi < 0.5 ? vec2(0.0) : vec2(cos(ai), sin(ai)) * r * (fi < 6.5 ? 2.0 : 4.0);
      float dc = abs(length(p - ci) - r);
      if (dc < d) { d = dc; lvl = fi < 0.5 ? 0.0 : fi < 6.5 ? 1.0 : 2.0; }
      if (p_fill < 0.05) continue;                 // Fill = 0: circles only (cheap)
      for (int j = 0; j < 13; j++) {
        if (j <= i) continue;
        float fj = float(j);
        float aj = (mod(fj - 1.0, 6.0)) * PI / 3.0 + PI / 6.0;
        vec2 cj = vec2(cos(aj), sin(aj)) * r * (fj < 6.5 ? 2.0 : 4.0);
        float ds = sdSeg(p, ci, cj);
        if (ds < d) { d = ds; lvl = 3.0; }
      }
    }
  } else if (p_mode < 3.5) {
    // Golden spiral r = e^(b theta), b = ln(phi) / (pi/2): a quarter turn scales by phi, so it
    // zooms forever. Detail = arms; Fill adds the counter-spiral (sunflower).
    float r = length(p), a = atan(p.y, p.x);
    float b = 0.3063489, arms = max(1.0, N);
    float lr = log(max(r, 1e-4));
    float s1 = (lr / b - a) * arms / TAU - t * p_zoom;
    float d1 = abs(fract(s1) - 0.5) * TAU / arms * b * r;
    d = d1; lvl = floor(s1);
    if (p_fill > 0.05) {
      float s2 = (lr / b + a) * arms / TAU - t * p_zoom;
      float d2 = abs(fract(s2) - 0.5) * TAU / arms * b * r / max(p_fill, 0.05);
      if (d2 < d) { d = d2; lvl = floor(s2) + 0.5; }
    }
    d = max(d, 0.0);
    fill = 0.0;
  } else {
    // Pyramid tunnel: nested triangles flying outwards; Fill twists them with depth (a spiral).
    float nt0 = max(-p.y, max(dot(p, vec2(0.866025, 0.5)), dot(p, vec2(-0.866025, 0.5))));
    float dens = max(1.0, N) * 0.6;
    float tw = log(max(nt0, 1e-4)) * p_fill * 1.2;
    vec2 q = mat2(cos(tw), sin(tw), -sin(tw), cos(tw)) * p;
    float nt = max(-q.y, max(dot(q, vec2(0.866025, 0.5)), dot(q, vec2(-0.866025, 0.5))));
    float v = log(max(nt, 1e-4)) * dens - t * p_zoom * 4.0;
    d = abs(fract(v + 0.5) - 0.5) / dens * nt;
    lvl = floor(v + 0.5) + floor(t * p_zoom * 4.0);
  }

  float line = 1.0 - smoothstep(w - px, w + px, d);
  float glow = p_glow * w * w / (d * d + w * w) * 0.6;
  float pulse = 1.0 + p_pulse * k * 1.5 * (0.5 + 0.5 * cos(TAU * (lvl * 0.25 - floor(t) * 0.25)));
  vec3 col = hsv(hue0 + p_spread * lvl * 0.1, p_sat, 1.0);
  vec3 c = col * (line + glow) * pulse + col * fill * 0.35;
  return (1.0 - exp(-c * 1.5)) * (0.85 + 0.15 * k);
}
