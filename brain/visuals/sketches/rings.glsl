// Rings: a stack of thin, wobbling rings, beat-locked. Circle-to-polygon morph,
// per-ring twist and phase give the stacked spirographic look.
// Params are p_* uniforms; ranges and defaults are in rings.json.
uniform float p_rings, p_spacing, p_inner, p_sides, p_round, p_waves, p_amp, p_phase,
              p_twist, p_spin, p_speed, p_width, p_glow, p_hue, p_spread, p_sat, p_follow, p_beat, p_zoom;

#define TAU 6.2831853

// Radius of a regular n-gon (circumradius 1) at angle a.
float polyR(float a, float n) {
  float s = TAU / n;
  return cos(3.1415927 / n) / cos(mod(a, s) - 3.1415927 / n);
}

vec3 content(vec2 uv) {
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) / p_zoom;
  float r = length(p), a = atan(p.y, p.x);
  float k = kick() * p_beat;
  float t = u_beat;
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  float sides = max(3.0, floor(p_sides + 0.5));
  vec3 col = vec3(0.0);
  for (int i = 0; i < 64; i++) {
    float fi = float(i);
    if (fi >= p_rings) break;
    float f = p_rings > 1.0 ? fi / (p_rings - 1.0) : 0.0;
    float ang = a - fi * p_twist - t * p_spin * TAU / 16.0;
    float shape = mix(polyR(ang, sides), 1.0, p_round);
    float rr = p_inner + fi * p_spacing * (1.0 + 0.25 * k);
    float wave = p_amp * (1.0 + k) * sin(p_waves * ang + fi * p_phase + t * p_speed * TAU);
    float d = abs(r - (rr * shape + wave));
    float line = smoothstep(p_width, p_width * 0.3, d);
    float glow = p_glow * p_width * p_width / (d * d + p_width * p_width) * 0.6;
    col += hsv(hue0 + p_spread * f, p_sat, 1.0) * (line + glow);
  }
  return (1.0 - exp(-col * 1.4)) * (0.75 + 0.25 * k);
}
