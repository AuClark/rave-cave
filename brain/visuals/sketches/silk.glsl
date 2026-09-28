// Silk: three layers of translucent silk — gold, rose and lavender — with domain-warped
// folds, Kajiya-Kay anisotropic sheen, backlit peaks and rare sparkles, drifting at
// different depths (after "Silk Cascade" in Paul Bakaus's Radiant collection, MIT).
// Ported nearly line for line; changes: time in beats; the sheen flashes on the kick;
// the key light orbits in beats (the original followed the mouse); fold scale, layer
// count, contrast, hue controls; the sheen's pinch points (where a fold's tangent is
// undefined) faded out; grain sized in output pixels.
// Params are p_* uniforms; ranges and defaults are in silk.json.
uniform float p_contrast, p_flow, p_sheen, p_scale, p_layers, p_light, p_punch, p_sparkle, p_hue,
              p_follow, p_bright;

#define PI 3.14159265359

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm3(vec2 p) {
  float v = 0.0, a = 0.5;
  mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
  for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = rot * p * 2.0; a *= 0.5; }
  return v;
}
float fbm2(vec2 p) {
  float v = 0.5 * vnoise(p);
  p = mat2(0.8, -0.6, 0.6, 0.8) * p * 2.0;
  return v + 0.25 * vnoise(p);
}
vec2 domainWarp(vec2 p, float t, float scale, float seed) {
  return vec2(fbm3(p * scale + vec2(1.7 + seed, 9.2) + t * 0.15), fbm3(p * scale + vec2(8.3, 2.8 + seed) - t * 0.12));
}
vec2 domainWarpLite(vec2 p, float t, float scale, float seed) {
  return vec2(fbm2(p * scale + vec2(1.7 + seed, 9.2) + t * 0.15), fbm2(p * scale + vec2(8.3, 2.8 + seed) - t * 0.12));
}

// Folds: vec3(height, gradient). Lite (back layer): cheaper warp, no noise detail.
vec3 fabricFold(vec2 p, float t, float seed, float freq, float flow, bool lite) {
  float ts = t * flow;
  vec2 warp = lite ? domainWarpLite(p + seed * 3.7, ts, 1.2, seed) : domainWarp(p + seed * 3.7, ts, 1.2, seed);
  vec2 wp = p + warp * 0.55;
  float h = 0.0; vec2 g = vec2(0.0);
  float f1x = freq * 0.7, f1y = freq * 0.4;
  float ph1 = wp.x * f1x + wp.y * f1y + ts * 0.3 + seed * 2.1;
  h += sin(ph1) * 0.35; g += cos(ph1) * 0.35 * vec2(f1x, f1y);
  float f2x = -freq * 0.3, f2y = freq * 0.9;
  float ph2 = wp.x * f2x + wp.y * f2y + ts * 0.25 + seed * 1.3;
  h += sin(ph2) * 0.25; g += cos(ph2) * 0.25 * vec2(f2x, f2y);
  float f3 = freq * 0.6;
  float ph3 = (wp.x + wp.y) * f3 + ts * 0.2 + seed * 4.5;
  h += sin(ph3) * 0.18; g += cos(ph3) * 0.18 * vec2(f3, f3);
  float f4x = freq * 1.8, f4y = freq * 1.2;
  float ph4 = wp.x * f4x + wp.y * f4y - ts * 0.35 + seed * 0.7;
  h += sin(ph4) * 0.08; g += cos(ph4) * 0.08 * vec2(f4x, f4y);
  if (!lite) h += vnoise(wp * freq * 0.9 + seed * 10.0 + ts * 0.04) * 0.12 - 0.06;
  return vec3(h, g);
}

// Kajiya-Kay anisotropic highlight along the fold's tangent.
float kajiyaSpec(vec2 grad, vec3 L, vec3 V, float shine) {
  float g2 = dot(grad, grad);
  if (g2 < 0.0001) return 0.0;
  vec3 T = normalize(vec3(vec2(-grad.y, grad.x) / sqrt(g2), 0.0));
  float TdH = dot(T, normalize(L + V));
  // Where a fold flattens its tangent is undefined and the highlight pinches to a
  // point (in the original too); fade the sheen out there.
  return pow(sqrt(max(1.0 - TdH * TdH, 0.0)), shine) * smoothstep(0.05, 0.9, sqrt(g2));
}

vec4 shadeLayer(vec2 p, float t, float seed, float freq, float flow,
                vec3 darkCol, vec3 midCol, vec3 brightCol, vec3 specCol,
                float opacity, float shine, vec3 L1, vec3 L2, vec3 V, float sheenMul) {
  vec3 fold = fabricFold(p, t, seed, freq, flow, opacity < 0.35);
  float h = fold.x;
  vec2 grad = fold.yz;
  vec3 N = normalize(vec3(-grad * 1.8, 1.0));
  float lit = max(dot(N, L1), 0.0) * 0.75 + max(dot(N, L2), 0.0) * 0.12;
  float depth = smoothstep(-0.8, 0.4, h);
  float shade = lit * depth;
  vec3 fabric = mix(darkCol, midCol, smoothstep(0.0, 0.35, shade));
  fabric = mix(fabric, brightCol, smoothstep(0.25, 0.7, shade) * 0.5);
  float sp = (kajiyaSpec(grad, L1, V, shine) * 0.9 + kajiyaSpec(grad, L2, V, shine * 0.6) * 0.15) * sheenMul;
  float specPow = sp * sp * sp;
  fabric += specCol * specPow * 0.9;
  fabric += vec3(0.45, 0.28, 0.15) * smoothstep(0.3, 0.9, depth) * lit * 0.08;
  float sparkle = step(0.9992, hash12(floor(p * 500.0 + t * 0.7))) * specPow * 20.0 * sheenMul * p_sparkle;
  fabric += specCol * min(sparkle, 2.0);
  return vec4(fabric, opacity * (0.65 + depth * 0.35));
}

vec3 hueShift(vec3 c, float turns) {
  float a = turns * 6.2831853;
  vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec3 content(vec2 uv0) {
  vec2 p = (uv0 - 0.5) * vec2(u_aspect, 1.0) / max(p_scale, 0.05);
  p.y = -p.y;
  float t = u_beat * p_flow;
  float k = kick();
  float sheen = p_sheen * (1.0 + p_punch * k);

  // Key light drifts as in the original, and can orbit (turns per 64 beats).
  float la = u_beat * p_light * 6.2831853 / 64.0;
  vec3 L1 = normalize(vec3(0.4 + sin(t * 0.07) * 0.3 + 0.6 * sin(la), 0.9 + cos(t * 0.09) * 0.15 + 0.6 * (cos(la) - 1.0), 0.8));
  vec3 L2 = normalize(vec3(-0.7 + cos(t * 0.06) * 0.2, -0.3 + sin(t * 0.08) * 0.15, 0.6));
  vec3 V = vec3(0.0, 0.0, 1.0);

  float bgD = length(p);
  vec3 bg = mix(vec3(0.055, 0.03, 0.075), vec3(0.012, 0.006, 0.02), smoothstep(0.0, 1.0, bgD));
  bg += vec3(0.025, 0.012, 0.035) * exp(-bgD * bgD * 2.0);

  vec3 col = bg;
  vec4 ly1 = vec4(0.0), ly2 = vec4(0.0), ly3 = vec4(0.0);
  if (p_layers > 2.5)
    ly1 = shadeLayer(p * 0.8 + vec2(0.15, t * 0.015), t, 0.0, 2.0, 0.5,
      vec3(0.10, 0.06, 0.02), vec3(0.50, 0.38, 0.15), vec3(0.80, 0.65, 0.32), vec3(1.0, 0.92, 0.65),
      0.30, 26.0, L1, L2, V, sheen * 0.7);
  if (p_layers > 1.5)
    ly2 = shadeLayer(p + vec2(t * 0.012, -0.1), t, 1.0, 3.2, 0.75,
      vec3(0.08, 0.03, 0.04), vec3(0.42, 0.18, 0.22), vec3(0.72, 0.38, 0.42), vec3(1.0, 0.82, 0.86),
      0.38, 40.0, L1, L2, V, sheen * 0.9);
  ly3 = shadeLayer(p * 1.2 + vec2(-t * 0.008, t * 0.02), t, 2.0, 4.5, 1.0,
      vec3(0.06, 0.04, 0.10), vec3(0.30, 0.22, 0.45), vec3(0.58, 0.48, 0.72), vec3(1.0, 0.90, 0.97),
      0.50, 55.0, L1, L2, V, sheen);

  col = mix(col, ly1.rgb, ly1.a);
  col += vec3(0.35, 0.18, 0.08) * ly1.a * ly2.a * 0.08;
  col = mix(col, ly2.rgb, ly2.a);
  col += vec3(0.30, 0.15, 0.25) * ly2.a * ly3.a * 0.06;
  col += vec3(0.40, 0.25, 0.12) * ly1.a * ly2.a * ly3.a * 0.04;
  col = mix(col, ly3.rgb, ly3.a);
  col += vec3(0.35, 0.20, 0.12) * (ly1.a + ly2.a + ly3.a) * 0.333 * 0.04;

  col *= 0.6 + 0.4 * (1.0 - smoothstep(0.25, 1.15, length(p * vec2(0.85, 1.0))));
  float lum = dot(col, vec3(0.299, 0.587, 0.114));
  col = mix(vec3(lum), col, 1.35);
  col = max(col, 0.0);
  col = col * pow(col / max(lum, 1e-3) * lum / 0.18, vec3(p_contrast - 1.0)) ;   // contrast about mid-grey
  col = hueShift(max(col, 0.0), p_hue + p_follow * u_hue) * p_bright;
  col = max(col, 0.0);
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
  col = pow(max(col, 0.0), vec3(0.4545));
  vec2 pix = uv0 * vec2(u_aspect, 1.0) / u_px;
  col += (hash12(pix + fract(u_beat * 3.4) * 100.0) - 0.5) * 0.015;
  return clamp(col, 0.0, 1.0);
}
