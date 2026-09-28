// Gilt: a Byzantine gold mosaic wall catching candlelight, its tesserae flipping over in
// a wave (after "Gilt Mosaic" in Paul Bakaus's Radiant collection, MIT). Ported nearly
// line for line; changes: reversed smoothsteps (undefined in GLSL) written as
// 1 - smoothstep, the shared hash() from the renderer (the same function), noise renamed
// vnoise, time in beats (the flip wave sweeps over a cycle of beats, the lights drift per
// beat), the click ripple is a radial flip from the centre every few bars, and the kick
// makes the gold flare. Params are p_* uniforms; ranges and defaults are in gilt.json.
uniform float p_tiles, p_lspeed, p_mode, p_sweep, p_delay, p_dir, p_radial, p_punch,
              p_shimmer, p_tint, p_hue, p_sat, p_bright, p_vignette, p_follow;

#define PI 3.14159265359
#define TAU 6.28318530718

vec2 hash2(vec2 p) {
  return vec2(fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453),
              fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453));
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Tile grid with slightly jittered boundaries: xy = local coord, zw = tile id.
vec4 tileGrid(vec2 p, float scale) {
  vec2 sp = p * scale;
  vec2 id = floor(sp);
  vec2 f = fract(sp) - (hash2(id) * 0.12 - 0.06);
  return vec4(f, id);
}
vec3 tileNormal(vec2 id) {
  float h1 = hash(id * 1.731 + 17.3), h2 = hash(id * 2.419 + 31.7);
  return normalize(vec3((h1 - 0.5) * 0.35, (h2 - 0.5) * 0.35, 1.0));
}
float groutMask(vec2 f, float gw) {
  vec2 e = smoothstep(vec2(0.0), vec2(gw), f) * smoothstep(vec2(0.0), vec2(gw), vec2(1.0) - f);
  return e.x * e.y;
}
float tileRoughness(vec2 f, vec2 id) {
  return vnoise(f * 8.0 + id * 3.7) * 0.6 + vnoise(f * 16.0 + id * 7.1 + 50.0) * 0.4;
}

// The flip wave: sweeps across in p_sweep beats, rests p_delay beats, and each sweep
// turns the tiles over again. dir: 0 left to right, 1 right to left, 2 top down, 3 bottom up.
vec2 waveFlip(vec2 tc, float beat, float ax) {
  float cycleDur = p_sweep + p_delay;
  float cycleT = mod(beat, cycleDur);
  float isOddWave = mod(floor(beat / cycleDur), 2.0);
  float s = clamp(cycleT / p_sweep, 0.0, 1.0);
  float sweep = s * s * (3.0 - 2.0 * s);
  float dir = floor(p_dir + 0.5);
  float axisLen = ax, tilePos = tc.x;
  if (dir == 1.0) tilePos = ax - tc.x;
  else if (dir == 2.0) { tilePos = 1.0 - tc.y; axisLen = 1.0; }
  else if (dir == 3.0) { tilePos = tc.y; axisLen = 1.0; }
  float waveX = sweep * (axisLen + 0.6) - 0.3;
  float dist = tilePos - waveX + hash(tc * 31.7 + vec2(17.3, 59.1)) * 0.06;
  float flipProgress = 1.0 - smoothstep(-0.3, 0.5, dist);
  float inTransition = 1.0 - smoothstep(0.0, 0.6, abs(dist + 0.1));
  return vec2((isOddWave + flipProgress) * PI, inTransition);
}

vec3 tintc(vec3 c) {
  float lum = dot(c, vec3(0.299, 0.587, 0.114));
  vec3 t = hsv(mix(p_hue, u_hue, p_follow), p_sat * (1.0 - 0.5 * smoothstep(0.6, 1.0, lum)), lum * 1.2);
  return mix(c, t, p_tint);
}

vec3 content(vec2 uv0) {
  vec2 uv = vec2(uv0.x, 1.0 - uv0.y);          // the original's y is up
  vec2 aspect = vec2(u_aspect, 1.0);
  vec2 p = uv * aspect;
  float t = u_beat * p_lspeed;
  float k = kick();

  float scale = p_tiles;
  vec4 tile = tileGrid(p, scale);
  vec2 f = tile.xy, id = tile.zw;
  float tMask = groutMask(f, 0.06);

  float tileHash = hash(id), tileHash2 = hash(id + 200.0), tileHash3 = hash(id + 400.0);
  vec3 N = tileNormal(id);
  float roughness = tileRoughness(f, id);
  N = normalize(N + vec3((roughness - 0.5) * 0.12, (vnoise(f * 12.0 + id * 5.3) - 0.5) * 0.12, 0.0));

  // Flip wave, with 3D perspective.
  vec2 tileCenter = (id + 0.5) / scale;
  vec2 flipData = waveFlip(tileCenter, u_beat, aspect.x);
  float flipAngle = flipData.x * p_mode;
  float inTransition = flipData.y * p_mode;

  // Radial flip from the centre every p_radial beats (the original's click).
  if (p_radial > 0.0) {
    float age = mod(u_beat, p_radial);         // beats since it started
    float radDist = length(p - vec2(0.5 * aspect.x, 0.5));
    float front = age * 0.57;                  // the original's 1.2 per second, at 126 BPM
    float inWave = 1.0 - smoothstep(front - 0.1, front + 0.15, radDist);
    inWave *= smoothstep(0.0, 0.2, age) * (1.0 - smoothstep(3.0, 6.0, age));
    flipAngle += inWave * PI;
    inTransition = max(inTransition, inWave);
  }

  float cosFlip = cos(flipAngle), abscos = abs(cosFlip);
  float dir = floor(p_dir + 0.5);
  bool flipVertical = (dir == 2.0 || dir == 3.0);
  if (flipVertical) f.y = (f.y - 0.5) / max(abscos, 0.04) + 0.5;
  else f.x = (f.x - 0.5) / max(abscos, 0.04) + 0.5;
  tMask *= step(0.0, f.x) * step(f.x, 1.0) * step(0.0, f.y) * step(f.y, 1.0);

  float isBack = step(cosFlip, 0.0);
  float sinFlip = sin(flipAngle);
  vec3 flippedN = flipVertical
    ? vec3(N.x, N.y * cosFlip + N.z * sinFlip, -N.y * sinFlip + N.z * cosFlip)
    : vec3(N.x * cosFlip + N.z * sinFlip, N.y, -N.x * sinFlip + N.z * cosFlip);
  N = normalize(mix(N, flippedN, clamp(p_mode, 0.0, 1.0)));
  if (isBack > 0.5) {
    vec3 backN = tileNormal(id + 500.0);
    float backRough = tileRoughness(f, id + 500.0);
    N = normalize(backN + vec3((backRough - 0.5) * 0.15, (vnoise(f * 14.0 + id * 3.7) - 0.5) * 0.15, 0.0));
    roughness = backRough;
  }

  // Three candle-like lights drifting over the wall.
  vec3 light1Pos = vec3(aspect.x * 0.5 + sin(t * 0.7) * aspect.x * 0.4, 0.5 + cos(t * 0.53) * 0.4, 0.8 + sin(t * 0.31) * 0.15);
  vec3 light2Pos = vec3(aspect.x * 0.5 + cos(t * 0.43 + 2.0) * aspect.x * 0.35, 0.5 + sin(t * 0.37 + 1.5) * 0.35, 0.7 + cos(t * 0.29) * 0.1);
  vec3 light3Pos = vec3(aspect.x * 0.5 + sin(t * 0.19 + 4.0) * aspect.x * 0.25, 0.5 + cos(t * 0.23 + 3.0) * 0.25, 1.2);

  vec3 wp = vec3(p, 0.0);
  vec3 viewDir = normalize(vec3(aspect.x * 0.5, 0.5, 1.5) - wp);
  vec3 L1 = normalize(light1Pos - wp), L2 = normalize(light2Pos - wp), L3 = normalize(light3Pos - wp);
  float spec1 = pow(max(dot(N, normalize(L1 + viewDir)), 0.0), 80.0 + tileHash * 60.0);
  float spec2 = pow(max(dot(N, normalize(L2 + viewDir)), 0.0), 60.0 + tileHash2 * 80.0);
  float spec3 = pow(max(dot(N, normalize(L3 + viewDir)), 0.0), 30.0 + tileHash3 * 20.0);
  float specTotal = spec1 * 1.2 + spec2 * 0.9 + spec3 * 0.4;
  float diffTotal = max(dot(N, L1), 0.0) * 0.5 + max(dot(N, L2), 0.0) * 0.35 + max(dot(N, L3), 0.0) * 0.25;

  float breathe = (1.0 + sin(t * 0.6) * 0.08 + sin(t * 0.37 + 1.0) * 0.05) * (1.0 + p_punch * k);
  specTotal *= breathe;
  diffTotal *= breathe;

  // Individual tiles catching the light at random moments (strongest with the flip off).
  float shimmer = pow(max(sin(tileHash * TAU + t * (0.8 + tileHash2 * 1.5)), 0.0), 16.0);
  float shimmer2 = pow(max(sin(tileHash3 * TAU + t * (0.5 + tileHash * 0.7) + 2.0), 0.0), 24.0);
  float shimmerTotal = (shimmer * 0.6 + shimmer2 * 0.4) * clamp(1.0 - p_mode + p_shimmer, 0.0, 2.0);

  vec3 groutColor = tintc(vec3(0.03, 0.02, 0.01));
  vec3 darkGold   = tintc(vec3(0.12, 0.09, 0.05));
  vec3 medGold    = tintc(vec3(0.45, 0.32, 0.14));
  vec3 brightGold = tintc(vec3(0.78, 0.58, 0.24));
  vec3 flashGold  = tintc(vec3(1.0, 0.85, 0.55));
  vec3 hotGold    = tintc(vec3(1.0, 0.95, 0.80));

  vec3 tileBase = mix(darkGold, medGold, smoothstep(0.0, 0.5, tileHash));
  tileBase = mix(tileBase, brightGold, smoothstep(0.5, 0.85, tileHash));
  tileBase *= 0.9 + tileHash2 * 0.2;

  vec3 tileColor = tileBase + tileBase * diffTotal * 0.6;
  vec3 specColor = mix(brightGold, flashGold, smoothstep(0.0, 0.5, specTotal));
  specColor = mix(specColor, hotGold, smoothstep(0.5, 1.0, specTotal));
  tileColor += specColor * specTotal * 1.4;
  tileColor += mix(flashGold, hotGold, clamp(shimmerTotal, 0.0, 1.0)) * shimmerTotal * 0.7;

  tileColor *= mix(1.0, abscos * 0.7 + 0.3, inTransition);
  tileColor = mix(tileColor, tileColor * mix(vec3(1.0), vec3(1.2, 1.05, 0.85), 1.0 - p_tint), isBack * 0.6);
  tileColor += medGold * pow(1.0 - abscos, 4.0) * inTransition * 0.25 * p_mode;
  tileColor += flashGold * pow(roughness, 4.0) * specTotal * 3.0 * 0.3;

  float edgeDist = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
  float edgeHighlight = 1.0 - smoothstep(0.05, 0.15, edgeDist);
  tileColor += brightGold * edgeHighlight * (diffTotal + specTotal * 0.5) * 0.15;

  vec3 col = mix(groutColor, tileColor, tMask);
  col -= vec3(0.01, 0.008, 0.005) * (1.0 - tMask) * (1.0 - smoothstep(0.0, 0.03, edgeDist));

  col += medGold * (1.0 - smoothstep(0.0, 0.7, length(p - light1Pos.xy))) * 0.06;
  col += medGold * (1.0 - smoothstep(0.0, 0.6, length(p - light2Pos.xy))) * 0.04;

  vec2 vigUv = uv * 2.0 - 1.0;
  float vig = smoothstep(0.0, 1.0, max(1.0 - dot(vigUv, vigUv) * 0.35, 0.0));
  col *= mix(1.0, 0.5 + vig * 0.5, p_vignette);

  col = max(col * p_bright, vec3(0.0));
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);   // ACES-like
  col = pow(max(col, vec3(0.0)), vec3(0.95, 1.0, 1.1));
  return clamp(col, 0.0, 1.0);
}
