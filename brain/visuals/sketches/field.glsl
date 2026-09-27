// Field: a lattice of independent dots that wander, drift across the surface, swell
// with a travelling wave and can link to their neighbours into a moving net.
// Each pixel only looks at the 3x3 nearest cells, so thousands of dots stay cheap.
// Params are p_* uniforms; ranges and defaults are in field.json.
uniform float p_density, p_wander, p_wspeed, p_flow, p_angle, p_size, p_svar, p_square, p_ring,
              p_wave, p_wfreq, p_wspd, p_wangle, p_links, p_lwidth, p_glow,
              p_hue, p_spread, p_huemode, p_sat, p_follow, p_beat;

#define TAU 6.2831853

vec2 hash2(vec2 p) {
  return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Dot centre for a cell, in cell units (cell origin = its corner).
vec2 dotPos(vec2 cell, float t) {
  vec2 h = hash2(cell);
  vec2 w = vec2(sin(t * p_wspeed * TAU * (0.7 + 0.6 * h.x) + h.y * TAU),
                cos(t * p_wspeed * TAU * (0.7 + 0.6 * h.y) + h.x * TAU));
  return cell + 0.5 + 0.5 * p_wander * w;
}

// Wave value (0..1) at a dot, travelling across the surface.
float waveAt(vec2 pos) {
  vec2 dir = vec2(cos(p_wangle * TAU), sin(p_wangle * TAU));
  return 0.5 + 0.5 * sin(dot(pos / p_density, dir) * p_wfreq * TAU - u_beat * p_wspd * TAU);
}

float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0));
}

vec3 content(vec2 uv) {
  float t = u_beat, k = kick() * p_beat;
  vec2 flowDir = vec2(cos(p_angle * TAU), sin(p_angle * TAU));
  // Surface in cell units (square cells), scrolled by the flow.
  vec2 p = uv * vec2(u_aspect, 1.0) * p_density - flowDir * t * p_flow;
  vec2 base = floor(p);
  float px = u_px * p_density;                       // one pixel in cell units
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  vec3 col = vec3(0.0);

  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = base + vec2(float(i), float(j));
      vec2 c = dotPos(cell, t);
      vec2 h = hash2(cell + 17.0);
      float wv = waveAt(c);
      float r = 0.5 * p_size * mix(1.0, 0.3 + 1.4 * h.x, p_svar) * mix(1.0, wv, p_wave) * (1.0 + 0.6 * k);
      vec2 q = p - c;
      float d = mix(length(q), max(abs(q.x), abs(q.y)), p_square) - r;     // < 0 inside the dot
      float ringW = max(0.06 * r + px, px);
      d = mix(d, abs(d + ringW) - ringW, p_ring);                            // filled -> outline
      float fill = 1.0 - smoothstep(-px, px, d);
      float glow = p_glow * 0.02 / (max(d, 0.0) * max(d, 0.0) * 40.0 + 0.02);
      float hueOff = mix(h.y, wv * 0.5, p_huemode) * p_spread;
      vec3 dc = hsv(hue0 + hueOff, p_sat, 1.0);
      col += dc * (fill + glow * 0.5) * (0.35 + 0.65 * mix(1.0, wv, p_wave * 0.6));

      if (p_links > 0.0) {                                                   // links to right and lower neighbours
        float lw = max(p_lwidth, px);
        for (int n = 0; n < 2; n++) {
          vec2 nb = cell + (n == 0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
          vec2 c2 = dotPos(nb, t);
          float ld = segDist(p, c, c2);
          float len = length(c2 - c);
          float fade = clamp(1.6 - len, 0.0, 1.0);                           // longer links fade out
          float line = (1.0 - smoothstep(lw - px, lw + px, ld)) * min(1.0, p_lwidth / px);
          col += dc * line * fade * p_links * 0.8;
        }
      }
    }
  }
  return 1.0 - exp(-col * 1.3);
}
