// Artpop: iridescent soap-film bubbles — thin-film interference over a flowing,
// domain-warped surface, with fresnel edge glow and chrome highlights (after "Artpop
// Iridescence" in Paul Bakaus's Radiant collection, MIT). Ported nearly line for line;
// changes: the bubble masks' reversed smoothsteps (undefined in GLSL) written as
// 1 - smoothstep; the two small bubbles are only computed where they are, and fbm
// octaves are a control (4 is the original; each bubble costs about 60 simplex lookups
// at 4); time in beats; the film's bands shimmer and the bubbles swell on the kick; a
// band shift that can follow the show's colour, and size.
// Params are p_* uniforms; ranges and defaults are in artpop.json.
uniform float p_warp, p_thick, p_speed, p_size, p_octaves, p_small, p_punch, p_swell, p_shift,
              p_follow, p_spec, p_bright;

#define PI 3.141592653589793
#define TAU 6.283185307179586

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289v2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }
float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz; x12.xy -= i1;
  i = mod289v2(i);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m; m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}
float fbm(vec2 p) {
  float f = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) {
    if (float(i) >= p_octaves) break;
    f += a * snoise(p);
    p *= 2.02;
    a *= 0.5;
  }
  return f;
}
float warpedNoise(vec2 p, float t) {
  vec2 q = vec2(fbm(p + t * 0.12), fbm(p + vec2(5.2, 1.3) + t * 0.09));
  // Warp scales the original's 4.0 and 3.5: strong warping folds the noise into fine grain.
  vec2 r = vec2(fbm(p + 4.0 * p_warp * q + vec2(1.7, 9.2) + t * 0.07), fbm(p + 4.0 * p_warp * q + vec2(8.3, 2.8) + t * 0.1));
  return fbm(p + 3.5 * p_warp * r);
}

// Thin-film interference: each channel peaks at a different thickness.
vec3 thinFilm(float thickness, float cosTheta) {
  vec3 film = 0.5 + 0.5 * cos(thickness * cosTheta + vec3(0.0, 2.094, 4.189) + TAU * (p_shift + p_follow * u_hue));
  return film * film;
}
float bubbleSurface(vec2 p, float t) {
  float s = sin(p.x * 2.0 + t * 0.5) * cos(p.y * 1.7 + t * 0.35) * 0.35;
  s += sin(p.x * 1.3 - t * 0.3 + p.y * 2.2) * 0.25;
  s += cos(p.y * 2.8 + t * 0.4 - p.x * 0.9) * 0.2;
  s += warpedNoise(p * 1.2, t) * 0.4;
  s += snoise(p * 3.5 + t * 0.2) * 0.08;
  return s;
}
vec3 getNormal(vec2 p, float t, float h0) {
  float e = 0.004;
  return normalize(vec3(h0 - bubbleSurface(p + vec2(e, 0.0), t), h0 - bubbleSurface(p + vec2(0.0, e), t), e));
}

// One bubble's film colour at sp: thickness base and slope, highlights, fresnel tint.
vec3 bubble(vec2 sp, vec2 rel, float t, float base, float amp, float grav, float breath,
            vec3 l1, float e1, float s1, float s2, vec3 fres, float k) {
  float surface = bubbleSurface(sp, t);
  vec3 n = getNormal(sp, t, surface);
  float thick = base + surface * amp * p_thick + rel.y * grav + breath + p_punch * 2.5 * k;
  float cosTheta = max(abs(n.z), 0.15);
  vec3 film = thinFilm(thick, cosTheta);
  float fresnel = pow(1.0 - cosTheta, 4.0);
  film = mix(film, film * 2.0 + fres, fresnel * 0.5);
  vec3 v = vec3(0.0, 0.0, 1.0);
  film += vec3(1.0, 0.97, 0.92) * pow(max(dot(n, normalize(l1 + v)), 0.0), e1) * s1 * p_spec;
  if (s2 > 0.0) film += vec3(0.9, 0.93, 1.0) * pow(max(dot(n, normalize(normalize(vec3(-0.5, -0.3, 0.9)) + v)), 0.0), 60.0) * s2 * p_spec;
  return film;
}

// A direction round a circle, for edge noise without the seam atan() * n leaves at +-pi.
vec2 ringDir(vec2 q) { return q / max(length(q), 1e-4); }

vec3 content(vec2 uv) {
  float k = kick();
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) / max(p_size * (1.0 + 0.03 * p_swell * k), 0.05);
  p.y = -p.y;                                  // the original's y is up
  float t = u_beat * p_speed;

  vec3 totalColor = vec3(0.0);
  float totalWeight = 0.0;

  // The big bubble.
  float dist1 = length(p * vec2(1.0, 1.1));
  float edge1 = snoise(ringDir(p) * 1.5 + vec2(t * 0.15, t * 0.2)) * 0.06;
  float mask1 = 1.0 - smoothstep(0.45 + edge1, 0.82 + edge1, dist1);
  if (mask1 > 0.0) {
    vec3 f1 = bubble(p * 1.6, p, t, 8.0, 12.0, 4.0, sin(t * 0.25) * 2.0, vec3(0.4, 0.6, 1.0) / length(vec3(0.4, 0.6, 1.0)), 80.0, 0.5, 0.3, vec3(0.15, 0.1, 0.2), k);
    totalColor += f1 * mask1;
    totalWeight += mask1;
  }

  if (p_small > 0.5) {
    // A smaller bubble, lower right.
    vec2 c2 = vec2(0.25, -0.15);
    float dist2 = length((p - c2) * vec2(1.2, 1.0));
    float edge2 = snoise(ringDir(p - c2) * 2.0 + vec2(0.0, t * 0.18)) * 0.04;
    float mask2 = 1.0 - smoothstep(0.18 + edge2, 0.38 + edge2, dist2);
    if (mask2 > 0.0) {
      vec3 f2 = bubble((p - c2) * 2.5 + vec2(3.7, 1.2), p - c2, t * 1.1, 6.0, 10.0, 3.5, sin(t * 0.3 + 1.5) * 1.8, normalize(vec3(0.3, 0.5, 1.0)), 90.0, 0.45, 0.0, vec3(0.12, 0.15, 0.18), k);
      totalColor = mix(totalColor, totalColor * 0.5 + f2, mask2);
      totalWeight = max(totalWeight, mask2);
    }
    // And one upper left.
    vec2 c3 = vec2(-0.3, 0.2);
    float dist3 = length((p - c3) * vec2(1.0, 1.3));
    float edge3 = snoise(ringDir(p - c3) * 2.5 + vec2(0.0, t * 0.2)) * 0.035;
    float mask3 = 1.0 - smoothstep(0.14 + edge3, 0.32 + edge3, dist3);
    if (mask3 > 0.0) {
      vec3 f3 = bubble((p - c3) * 2.8 + vec2(7.1, 4.3), p - c3, t * 0.9, 5.0, 11.0, 3.0, cos(t * 0.35 + 3.0) * 2.0, normalize(vec3(-0.3, 0.4, 1.0)), 70.0, 0.4, 0.0, vec3(0.18, 0.1, 0.14), k);
      totalColor = mix(totalColor, totalColor * 0.5 + f3, mask3);
      totalWeight = max(totalWeight, mask3);
    }
  }

  float distCenter = length(p * vec2(0.9, 1.0));
  vec3 bgColor = vec3(0.015, 0.015, 0.03) + vec3(0.04, 0.02, 0.06) * exp(-distCenter * distCenter * 4.0) * 0.06;
  vec3 col = mix(bgColor, totalColor, clamp(totalWeight, 0.0, 1.0));
  col *= 0.6 + 0.4 * (1.0 - smoothstep(0.35, 1.3, length(p * vec2(0.85, 1.0))));
  col = clamp(col * p_bright, 0.0, 1.0);
  col = pow(col, vec3(0.95));
  return col * col * (3.0 - 2.0 * col);
}
