// Tropical: heat distortion with chromatic aberration over domain-warped noise in hot
// magenta, orange, amber and teal, with blooms of vivid colour (after "Tropical Heat" in
// Paul Bakaus's Radiant collection, MIT). Ported nearly line for line; changes: reversed
// smoothsteps (undefined in GLSL) written as 1 - smoothstep, time in beats, the blooms
// flare on the kick, heat can follow the track's energy, a hue shift, and two quality
// controls for the projector's GPU: noise octaves (the original uses 6) and a cheap
// chromatic mode that warps once and shifts the red and blue lookups (about 3x cheaper).
// Params are p_* uniforms; ranges and defaults are in tropical.json.
uniform float p_heat, p_vibrancy, p_speed, p_scale, p_octaves, p_chroma, p_punch, p_energy,
              p_hue, p_follow, p_bright, p_vignette;

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289v2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

// 2D simplex noise (Ian McEwan, Ashima Arts; MIT).
float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod289v2(i);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
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

float fbm(vec2 p, float t) {
  float val = 0.0, amp = 0.5, freq = 1.0;
  for (int i = 0; i < 6; i++) {
    if (float(i) >= p_octaves) break;
    val += amp * snoise(p * freq + t * 0.25);
    freq *= 2.05;
    amp *= 0.5;
    p += vec2(1.7, 9.2);
  }
  return val;
}
float warpedFbm(vec2 p, float t) {
  vec2 q = vec2(fbm(p, t), fbm(p + vec2(5.2, 1.3), t));
  vec2 r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2), t * 1.15), fbm(p + 3.0 * q + vec2(8.3, 2.8), t * 1.15));
  return fbm(p + 2.5 * r, t * 0.9);
}

vec2 heatDistortion(vec2 uv, float t, float intensity) {
  float n1 = snoise(vec2(uv.x * 3.0, uv.y * 6.0 - t * 1.8)) * 0.5;
  float n2 = snoise(vec2(uv.x * 5.0 + 1.3, uv.y * 10.0 - t * 2.5 + 3.7)) * 0.3;
  float n3 = snoise(vec2(uv.x * 8.0 - 2.1, uv.y * 4.0 - t * 1.2 + 7.1)) * 0.2;
  float h1 = snoise(vec2(uv.x * 4.0 + t * 0.8, uv.y * 7.0 - t * 1.5)) * 0.4;
  float h2 = snoise(vec2(uv.x * 7.0 - t * 0.5, uv.y * 3.0 + 2.3)) * 0.25;
  return vec2((h1 + h2) * intensity * 0.025, (n1 + n2 + n3) * intensity * 0.018);
}

vec3 tropicalColor(float t, float vibrancy) {
  vec3 col = vec3(0.55, 0.3, 0.25) + vec3(0.45, 0.35, 0.3) * cos(6.28318 * (vec3(1.0, 0.8, 0.7) * t + vec3(0.0, 0.15, 0.35)));
  float l = dot(col, vec3(0.299, 0.587, 0.114));
  return mix(vec3(l), col, 1.0 + vibrancy * 0.6);
}
vec3 magentaOrange(float t, float vibrancy) {
  vec3 col = vec3(0.6, 0.2, 0.35) + vec3(0.4, 0.3, 0.25) * cos(6.28318 * (vec3(1.2, 1.0, 0.6) * t + vec3(0.1, 0.25, 0.45)));
  float l = dot(col, vec3(0.299, 0.587, 0.114));
  return mix(vec3(l), col, 1.0 + vibrancy * 0.5);
}

// Rotate hue about the grey axis.
vec3 hueShift(vec3 c, float turns) {
  float a = turns * 6.2831853;
  vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec2 centred(vec2 uv) { return (uv - 0.5) * vec2(u_aspect, 1.0) / min(u_aspect, 1.0) / max(p_scale, 0.05); }

vec3 content(vec2 uv0) {
  vec2 uv = vec2(uv0.x, 1.0 - uv0.y);          // the original's y is up
  vec2 p = centred(uv);
  float t = u_beat * p_speed;
  float k = kick();
  float heat = p_heat * (1.0 + p_energy * (u_energy - 0.5));
  float vib = p_vibrancy;

  vec2 distort = heatDistortion(uv, t, heat);
  float aberration = heat * 0.012;
  vec2 uvR = uv + distort * 1.3 + vec2(aberration, aberration * 0.5);
  vec2 uvG = uv + distort;
  vec2 uvB = uv + distort * 0.7 - vec2(aberration * 0.8, aberration * 0.3);

  // Full: three warped lookups, one per channel, as in the original. Cheap: one lookup,
  // with the red and blue offsets turned into small shifts of the colour ramp.
  float warpR, warpG, warpB;
  warpG = warpedFbm(centred(uvG) * 1.5, t * 0.3 + 0.7);
  if (p_chroma > 0.5) {
    warpR = warpedFbm(centred(uvR) * 1.5, t * 0.3);
    warpB = warpedFbm(centred(uvB) * 1.5, t * 0.3 + 1.4);
  } else {
    float s = dot(distort, vec2(1.0)) * 4.0;
    warpR = warpG + aberration * 3.0 + s;
    warpB = warpG - aberration * 2.5 - s * 0.7;
  }

  vec3 baseColor;
  baseColor.r = tropicalColor(warpR * 0.8 + t * 0.05, vib).r;
  baseColor.g = tropicalColor(warpG * 0.8 + t * 0.05 + 0.33, vib).g;
  baseColor.b = magentaOrange(warpB * 0.8 + t * 0.05 + 0.66, vib).b;

  float flow1 = snoise(p * 2.5 + vec2(t * 0.4, -t * 0.3));
  float flow2 = snoise(p * 3.8 + vec2(-t * 0.35, t * 0.25));
  float flowMask = smoothstep(-0.2, 0.6, flow1 * flow2);
  vec3 hotLayer = magentaOrange(flow1 * 0.5 + t * 0.08, vib) * vec3(1.1, 0.7, 0.9);
  baseColor = mix(baseColor, hotLayer, flowMask * 0.4 * vib);

  float tealNoise = snoise(p * 4.0 + vec2(t * 0.2, t * 0.15 + 5.0));
  baseColor = mix(baseColor, vec3(0.1, 0.45, 0.4), smoothstep(0.3, 0.8, tealNoise) * 0.15 * vib);

  // Blooms of vivid colour, peaking on their own clocks, flaring on the kick.
  float kb = 1.0 + p_punch * k;
  float bt1 = pow(sin(t * 0.4) * 0.5 + 0.5, 6.0);
  vec2 bc1 = vec2(snoise(vec2(t * 0.13, 0.0)), snoise(vec2(0.0, t * 0.11 + 3.0))) * 0.4;
  float bloom1 = bt1 * (1.0 - smoothstep(0.0, 0.5, length(p - bc1)));
  float bt2 = pow(sin(t * 0.7 + 2.1) * 0.5 + 0.5, 8.0);
  vec2 bc2 = vec2(snoise(vec2(t * 0.17 + 7.0, 2.0)), snoise(vec2(3.0, t * 0.14 + 5.0))) * 0.35;
  float bloom2 = bt2 * (1.0 - smoothstep(0.0, 0.35, length(p - bc2)));
  float bt3 = pow(sin(t * 0.55 + 4.3) * 0.5 + 0.5, 7.0);
  vec2 bc3 = vec2(snoise(vec2(t * 0.1 + 12.0, 8.0)), snoise(vec2(6.0, t * 0.09 + 10.0))) * 0.3;
  float bloom3 = bt3 * (1.0 - smoothstep(0.0, 0.45, length(p - bc3)));
  baseColor += vec3(0.95, 0.4, 0.2) * bloom1 * 0.7 * vib * kb;
  baseColor += vec3(0.85, 0.15, 0.5) * bloom2 * 0.6 * vib * kb;
  baseColor += vec3(1.0, 0.65, 0.1) * bloom3 * 0.5 * vib * kb;

  float spike = pow(sin(t * 0.25) * 0.5 + 0.5, 12.0);
  baseColor += vec3(0.2, 0.08, 0.03) * spike * (snoise(p * 1.5 - vec2(0.0, t * 0.8)) * 0.5 + 0.5) * heat;

  float haze = snoise(vec2(p.x * 6.0, p.y * 12.0 - t * 2.0));
  baseColor += vec3(0.15, 0.08, 0.04) * pow(smoothstep(0.4, 0.9, haze), 3.0) * heat * 0.5 * (1.0 + p_punch * k);

  float luminance = dot(baseColor, vec3(0.299, 0.587, 0.114));
  baseColor = mix(baseColor, vec3(0.78, 0.58, 0.42) * luminance, 0.12);

  float vig = pow(clamp(1.0 - dot(p, p) * 0.5, 0.0, 1.0), 0.7);
  baseColor *= mix(1.0, vig, p_vignette);

  baseColor = hueShift(max(baseColor, 0.0), p_hue + p_follow * u_hue);
  baseColor = max(baseColor * p_bright, 0.0);
  baseColor = baseColor / (1.0 + baseColor * 0.25);
  baseColor = pow(baseColor, vec3(0.95)) * vec3(1.05, 0.97, 0.88);
  return clamp(baseColor, 0.0, 1.0);
}
