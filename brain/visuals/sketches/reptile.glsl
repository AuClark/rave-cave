// Reptile: shimmering hex scales with an iridescent sheen that ripples out on the beat,
// and a slit-pupil eye that opens wide on the DROP. Params are p_* uniforms; ranges and
// defaults are in reptile.json.
uniform float p_scale, p_gap, p_shine, p_irid, p_wave, p_wspeed, p_eye, p_esize, p_slit, p_drop,
              p_blink, p_hue, p_sat, p_follow, p_beat;

#define TAU 6.2831853
#define PI 3.1415927

// Nearest hex centre (pointy rows): xy = offset from the centre, zw = cell id.
vec4 hexCell(vec2 p) {
  vec2 s = vec2(1.0, 1.7320508);
  vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
  vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
  return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
}
float hexDist(vec2 p) { p = abs(p); return max(dot(p, vec2(0.5, 0.8660254)), p.x); }

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float A = u_aspect;
  vec2 p = (uv - 0.5) * vec2(A, 1.0);
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  bool drop = abs(u_scene - 7.0) < 0.5;

  // Scales.
  vec2 sp = p * p_scale;
  vec4 h = hexCell(sp);
  float hd = hexDist(h.xy);                                  // 0.5 at the edge
  float spx = u_px * p_scale;
  float scaleM = 1.0 - smoothstep(0.5 - p_gap - spx, 0.5 - p_gap + spx, hd);
  vec2 cc = h.zw * vec2(1.0, 1.7320508) / p_scale;           // cell centre, surface units
  float wave = sin(length(cc) * 14.0 - t * TAU * p_wspeed) * p_wave * (0.6 + 0.8 * k);
  float dome = 1.0 - pow(hd / 0.5, 2.0);
  vec2 nrm = h.xy * 1.6 + vec2(0.35 * wave, 0.25 * wave);    // a fake normal, tilted by the wave
  float light = clamp(0.55 + dot(nrm, vec2(-0.5, -0.6)), 0.0, 1.0);
  float spec = pow(clamp(1.0 - length(h.xy - vec2(-0.15, -0.2) + 0.1 * wave), 0.0, 1.0), 6.0) * p_shine;
  float ih = hue0 + p_irid * (0.25 * dot(nrm, vec2(0.7, 0.4)) + 0.15 * hash(h.zw) + 0.1 * wave + t * 0.01);
  vec3 col = hsv(ih, p_sat, 0.25 + 0.6 * light * dome) * scaleM + vec3(spec) * scaleM;

  // Eye: iris with striations, a vertical slit that opens on the drop, occasional blink.
  if (p_eye > 0.5) {
    float R = 0.28 * p_esize;
    vec2 e = p / R;
    float epx = u_px / R;
    float lid = 1.0;
    float bb = mod(t, 8.0);
    if (hash(vec2(floor(t / 8.0), 1.3)) < p_blink && bb > 7.0) lid = 1.0 - sin(PI * clamp((bb - 7.0) / 0.6, 0.0, 1.0));
    float hh = 0.62 * lid * max(0.0, 1.0 - e.x * e.x);
    float dl = abs(e.x) > 1.0 ? length(vec2(abs(e.x) - 1.0, e.y)) : abs(e.y) - hh;
    float inside = 1.0 - smoothstep(-epx, epx, dl);
    float r = length(e), a = atan(e.y, e.x);
    float stri = 0.6 + 0.4 * sin(a * 60.0 + sin(r * 20.0) * 2.0);
    vec3 iris = hsv(hue0 + 0.08 + 0.05 * sin(r * 8.0), 0.9, 0.9) * stri * (1.0 - 0.6 * smoothstep(0.6, 1.0, r));
    float slit = p_slit * (1.0 + 0.3 * k);
    if (drop) slit = mix(slit, 0.55, p_drop * smoothstep(0.0, 1.0, u_since));
    float ps = length(e * vec2(1.0 / max(slit, 0.02), 1.0 / 0.85)) - 1.0;
    float pupil = 1.0 - smoothstep(-epx * 8.0, epx * 8.0, ps);
    vec3 eyec = mix(iris, vec3(0.0), pupil);
    eyec += vec3(0.9) * (1.0 - smoothstep(0.06 - epx, 0.06 + epx, length(e - vec2(-0.3, -0.3)))) * inside;
    float rim = 1.0 - smoothstep(0.03 - epx, 0.03 + epx, abs(dl));
    col = mix(col * (1.0 - 0.7 * exp(-max(dl, 0.0) * 6.0)), eyec, inside);
    col = mix(col, vec3(0.02), rim);
  }
  return col * (0.9 + 0.1 * k);
}
