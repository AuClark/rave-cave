// Burn: celluloid catching fire in a projector — amber burn holes spread across dark
// film stock, a white-hot frontier, embers glowing through the holes, sparks drifting up,
// sprocket holes and grain (after "Burning Film" in Paul Bakaus's Radiant collection,
// MIT). Ported nearly line for line; changes: its many reversed smoothsteps (undefined
// in GLSL) go through rsmooth(), 1 - smoothstep with the edges the right way round; its
// noise renamed and the float loop made int; grain and scanlines sized from u_px;
// sprocket holes redrawn as holes (the original's were flat dashes); the
// burn cycle is in beats, or the burn can spread through the song section (the film
// burns away over a BUILD); the frontier flares on the kick; fbm octaves are a control.
// Params are p_* uniforms; ranges and defaults are in burn.json.
uniform float p_run, p_grow, p_cycle, p_section, p_speed, p_ember, p_edge, p_sparks, p_sprockets, p_grain,
              p_punch, p_scale, p_octaves, p_hue, p_follow, p_bright;

float rsmooth(float a, float b, float x) { return 1.0 - smoothstep(b, a, x); }

float hash21(vec2 p) {
  p = fract(p * vec2(443.897, 441.423));
  p += dot(p, p + 19.19);
  return fract(p.x * p.y);
}
vec2 hash22(vec2 p) {
  vec3 a = fract(p.xyx * vec3(443.897, 441.423, 437.195));
  a += dot(a, a.yzx + 19.19);
  return fract((a.xx + a.yz) * a.zy);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  mat2 rot = mat2(0.866, 0.5, -0.5, 0.866);
  for (int i = 0; i < 6; i++) {
    if (float(i) >= p_octaves) break;
    v += a * vnoise(p);
    p = rot * p * 2.0 + vec2(100.0);
    a *= 0.5;
  }
  return v;
}
float warpedNoise(vec2 p, float t) {
  vec2 q = vec2(fbm(p), fbm(p + vec2(5.2, 1.3)));
  vec2 r = vec2(fbm(p + 4.0 * q + vec2(1.7, 9.2) + 0.05 * t), fbm(p + 4.0 * q + vec2(8.3, 2.8) + 0.06 * t));
  return fbm(p + 4.0 * r);
}
float emberNoise(vec2 p, float t) {
  return vnoise(p * 3.0 + vec2(t * 0.3, t * 0.2)) * 0.5 + vnoise(p * 7.0 - vec2(t * 0.5, t * 0.15)) * 0.35
       + vnoise(p * 15.0 + vec2(t * 0.8, -t * 0.4)) * 0.15;
}
// Sprocket holes: rounded rectangles in a strip down each edge, in real proportions
// (the original measured x in screen widths and y in eighths of the height, which drew
// wide flat dashes instead of holes). Run scrolls them through the gate, in holes per beat.
float sprocketHoles(vec2 uv) {
  vec2 q = vec2(uv.x * u_aspect, uv.y);                 // surface heights
  float W = u_aspect;
  float x = min(q.x, W - q.x);                          // distance in from the nearer edge
  float strip = 1.0 - smoothstep(0.075, 0.075 + u_px, x);
  float pitch = 0.125;
  float y = mod(q.y + u_beat * p_run * pitch, pitch) - 0.5 * pitch;
  vec2 d = abs(vec2(x - 0.04, y)) - vec2(0.013, 0.02) + 0.006;
  float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.006;   // rounded box
  float hole = 1.0 - smoothstep(-u_px, u_px, sd);
  return hole * 0.12 - strip * (1.0 - hole) * 0.012;   // lit holes in a slightly darker strip
}
vec3 hueShift(vec3 c, float turns) {
  float a = turns * 6.2831853;
  vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec3 content(vec2 uv0) {
  vec2 uv = vec2(uv0.x, 1.0 - uv0.y);          // the original's y is up
  vec2 pix = uv0 * vec2(u_aspect, 1.0) / u_px; // output pixels
  float t = u_beat * 0.476;                    // the original's seconds, at 126 BPM
  float k = kick();

  // Burn cycle: in beats, or following the song section.
  float cycleDuration = max(p_cycle, 1.0);
  float cycleT = mod(u_beat, cycleDuration);
  float cyclePhase = cycleT / cycleDuration;
  float cycleIndex = floor(u_beat / cycleDuration);
  if (p_section > 0.5) { cyclePhase = clamp(u_sp, 0.0, 1.0) * 0.85; cycleT = cyclePhase * cycleDuration; }
  // The original's threshold falls over the cycle, and film burns where the noise is
  // below it, so its fire actually shrinks (its comments meant the opposite). Spread
  // runs it the other way: holes open in dark film and grow until it's all fire.
  float bp = p_grow > 0.5 ? 0.85 - min(cyclePhase, 0.85) : cyclePhase;
  float burnThreshold = mix(0.88, 0.08, smoothstep(0.0, 0.85, bp));
  float resetFade = smoothstep(0.88, 1.0, cyclePhase);
  float startFade = p_section > 0.5 ? 1.0 : smoothstep(0.0, 0.05, cyclePhase);

  float aspect = u_aspect;
  vec2 noiseUV = uv * vec2(aspect, 1.0) * 2.5 / max(p_scale, 0.05);
  vec2 cycleOffset = vec2(cycleIndex * 7.31, cycleIndex * 3.17);
  float burnNoise = warpedNoise(noiseUV + cycleOffset, cycleT * p_speed * 0.3);

  // Burned regions, the glowing frontier, and the white-hot edge right at it.
  float burnAmount = rsmooth(burnThreshold, burnThreshold - 0.12, burnNoise);
  float edgeWidth = 0.06;
  float edgeInner = rsmooth(burnThreshold, burnThreshold - edgeWidth, burnNoise);
  float edgeMask = edgeInner * (1.0 - burnAmount * 0.7);
  float hotEdge = max(rsmooth(burnThreshold + 0.01, burnThreshold - 0.01, burnNoise)
                    - rsmooth(burnThreshold - 0.01, burnThreshold - 0.04, burnNoise), 0.0);

  // Film base: very dark, grain, faint scanlines, sprocket holes.
  vec3 filmBase = vec3(0.035, 0.03, 0.028) + (hash21(pix * 0.5 + fract(t * 137.0)) - 0.5) * 0.035 * p_grain;
  filmBase *= 0.95 + (sin(uv.y / u_px * 0.5) * 0.5 + 0.5) * 0.05;
  filmBase += sprocketHoles(uv0) * p_sprockets;

  vec3 whiteHot = vec3(1.0, 0.88, 0.67), orangeGlow = vec3(1.0, 0.533, 0.2);
  vec3 amberEdge = vec3(0.784, 0.584, 0.424), deepAmber = vec3(0.5, 0.25, 0.08);
  vec3 edgeColor = mix(amberEdge, orangeGlow, smoothstep(0.0, 0.5, edgeMask));
  edgeColor = mix(edgeColor, whiteHot, hotEdge);
  edgeColor *= 0.8 + vnoise(noiseUV * 8.0 + cycleOffset + t * 0.5) * 0.4;
  edgeColor *= (0.85 + 0.15 * sin(t * 3.0 + burnNoise * 10.0)) * (1.0 + p_punch * k);

  // Embers through the holes.
  float ember = emberNoise(noiseUV, t);
  vec3 emberColor = mix(vec3(0.1, 0.02, 0.0), vec3(0.4, 0.04, 0.0), smoothstep(0.2, 0.5, ember));
  emberColor = mix(emberColor, vec3(0.85, 0.35, 0.05), smoothstep(0.55, 0.75, ember));
  emberColor = mix(emberColor, vec3(1.0, 0.7, 0.3), smoothstep(0.8, 0.95, ember) * 0.5);
  emberColor *= (0.7 + 0.3 * sin(t * 2.0 + ember * 8.0 + burnNoise * 5.0)) * p_ember;
  emberColor += orangeGlow * rsmooth(0.3, 0.0, abs(burnNoise - burnThreshold + 0.15)) * 0.4 * p_ember;

  vec3 col = filmBase;
  col += deepAmber * rsmooth(burnThreshold + 0.15, burnThreshold + 0.02, burnNoise) * (1.0 - burnAmount) * 0.4;
  col = mix(col, emberColor, burnAmount);
  col += edgeColor * edgeMask * 1.8 * p_edge;
  col += whiteHot * hotEdge * 1.2 * p_edge * (1.0 + p_punch * k);

  // Crispy curling at the edge.
  float curlEdge = rsmooth(burnThreshold + 0.03, burnThreshold - 0.02, burnNoise) * (1.0 - burnAmount * 0.8);
  col += vec3(0.6, 0.3, 0.1) * vnoise(noiseUV * 20.0 + cycleOffset) * curlEdge * 0.3;

  // Sparks drifting up near the burn.
  float nearBurn = rsmooth(0.6, 0.3, abs(burnNoise - burnThreshold));
  for (int ii = 0; ii < 4; ii++) {
    float i = float(ii);
    vec2 sparkPos = uv * vec2(aspect, 1.0) * (30.0 + i * 15.0);
    sparkPos.y -= t * (1.5 + i * 0.8);
    sparkPos.x += sin(t * (1.0 + i * 0.3) + i * 3.0) * 0.5;
    vec2 sparkId = floor(sparkPos);
    float sparkHash = hash21(sparkId + i * 100.0);
    float sparkDist = length(fract(sparkPos) - 0.5 - (hash22(sparkId + i * 50.0) - 0.5) * 0.3);
    float sparkSize = 0.03 + sparkHash * 0.02;
    float spark = rsmooth(sparkSize, sparkSize * 0.2, sparkDist) * (sin(t * 15.0 + sparkHash * 50.0) * 0.5 + 0.5) * step(0.85, sparkHash) * nearBurn;
    col += mix(orangeGlow, whiteHot, sparkHash) * spark * 0.6 * p_ember * p_sparks;
  }

  vec2 vc = uv - 0.5;
  col *= pow(clamp(1.0 - dot(vc, vc) * 1.6, 0.0, 1.0), 0.6);
  col *= startFade * (1.0 - resetFade);
  col = mix(col, col * vec3(1.05, 0.95, 0.85), 0.15);
  col = hueShift(max(col, 0.0), p_hue + p_follow * u_hue) * p_bright;
  col = max(col, 0.0);
  col = col / (1.0 + col * 0.2);
  return clamp(pow(col, vec3(0.95)), 0.0, 1.0);
}
