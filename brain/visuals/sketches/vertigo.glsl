// Vertigo: an endless crimson tunnel of neon rings and segments, lit by waves that run
// along it (after "Vertigo" in Paul Bakaus's Radiant collection, MIT). Ported nearly
// line for line; changes: reversed smoothsteps (undefined in GLSL) go through rsmooth(),
// 1 - smoothstep with the edges the right way round; its hash is the renderer's (the same
// function) and an unused noise dropped; the original's Spiral Intensity was never used,
// here it twists the tunnel; time in beats (it scrolls a set number of rings per beat);
// the rings flash on the kick; roll, segment count, hue controls; grain sized in pixels.
// Params are p_* uniforms; ranges and defaults are in vertigo.json.
uniform float p_speed, p_spiral, p_spin, p_rings, p_segs, p_waves, p_punch, p_flash,
              p_edge, p_hue, p_follow, p_bright;

#define PI 3.14159265359
#define TAU 6.28318530718

float rsmooth(float a, float b, float x) { return 1.0 - smoothstep(b, a, x); }
vec3 hueShift(vec3 c, float turns) {
  float a = turns * TAU;
  vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec3 content(vec2 uv0) {
  vec2 p = (uv0 - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;
  float t = u_beat * 0.476;                    // the original's seconds, at 126 BPM
  float k = kick();

  float r = length(p);
  float theta = atan(p.y, p.x);
  float depth = 1.0 / (r + 0.04);

  float rotAngle = t * 0.02 + sin(t * 0.07) * 0.15 + u_beat * p_spin * TAU / 64.0;
  float tu = (theta + rotAngle) / TAU + p_spiral * depth * 0.05;    // Spiral twists with depth

  // Scroll: Speed is primary rings per beat.
  float ringFreq = p_rings;
  float ringCoord = depth * ringFreq / TAU - u_beat * p_speed;
  float ringPhase = fract(ringCoord);
  float ringId = floor(ringCoord);

  float ring = smoothstep(0.0, 0.06, ringPhase) * rsmooth(0.5, 0.44, ringPhase);
  float ringPhase2 = fract(ringCoord * 2.0);
  float ring2 = smoothstep(0.0, 0.03, ringPhase2) * rsmooth(0.5, 0.47, ringPhase2);
  float angPhase = fract(tu * p_segs);
  float angLine = smoothstep(0.0, 0.025, angPhase) * rsmooth(1.0, 0.975, angPhase);
  float structure = max(ring * angLine, ring2 * 0.25 * angLine);

  // Waves of light running along the rings.
  float wt = t * p_waves;
  float wave1 = pow(sin(ringId * 0.5 - wt * 0.8) * 0.5 + 0.5, 3.0);
  float wave2 = pow(sin(ringId * 0.3 + wt * 0.5) * 0.5 + 0.5, 4.0);
  float wave3 = pow(sin(ringId * 0.15 - wt * 0.35) * 0.5 + 0.5, 2.0);
  float ringBrightness = clamp(0.15 + wave1 * 0.5 + wave2 * 0.35 + wave3 * 0.25, 0.0, 1.5);
  float flash = pow(max(0.0, sin(ringId * 7.3 - wt * 1.2)), 12.0) * p_flash;
  ringBrightness += flash * 0.8 + p_punch * k;
  structure *= ringBrightness;

  float depthFade = exp(-r * 3.0);
  float voidFade = smoothstep(0.0, 0.12, r);
  structure *= depthFade * voidFade;
  float edgeHighlight = rsmooth(0.06, 0.02, abs(ringPhase - 0.01)) + rsmooth(0.06, 0.02, abs(ringPhase - 0.48));
  edgeHighlight *= angLine * depthFade * voidFade * p_edge * (1.0 + 0.5 * p_punch * k);

  vec3 crimson = vec3(0.80, 0.067, 0.20), darkPurple = vec3(0.133, 0.0, 0.20);
  vec3 neonRed = vec3(1.0, 0.133, 0.267), amber = vec3(0.784, 0.584, 0.424);
  vec3 magenta = vec3(0.6, 0.05, 0.35), burntOrange = vec3(0.85, 0.35, 0.1);

  float colorSel = fract(ringId * 0.618033);
  float colorShift = sin(ringId * 1.7 + t * 0.2) * 0.5 + 0.5;
  vec3 tunnelColor = mix(darkPurple, crimson, smoothstep(0.0, 0.5, r));
  tunnelColor = mix(tunnelColor, magenta, colorSel * 0.3);
  tunnelColor = mix(tunnelColor, crimson * 1.3, colorShift * 0.25);
  tunnelColor = mix(tunnelColor, amber * 0.8, wave1 * wave3 * 0.3);
  tunnelColor = mix(tunnelColor, burntOrange, clamp(flash, 0.0, 1.0) * 0.5);
  vec3 edgeColor = mix(neonRed, amber, wave2 * 0.4);
  edgeColor = mix(edgeColor, magenta * 1.5, clamp(flash, 0.0, 1.0) * 0.3);

  vec3 col = tunnelColor * structure;
  col += edgeColor * edgeHighlight * 0.5;
  col += amber * wave1 * structure * 0.3;
  col += mix(amber, vec3(1.0, 0.9, 0.7), 0.5) * flash * structure * 0.5;
  col += darkPurple * exp(-r * 5.0) * (1.0 - smoothstep(0.0, 0.08, r)) * 0.08;
  col += mix(darkPurple, crimson * 0.5, 0.3) * exp(-r * 6.0) * 0.02;
  col *= 0.55 + 0.45 * (1.0 - smoothstep(0.3, 1.1, r));

  vec2 pix = uv0 * vec2(u_aspect, 1.0) / u_px;
  col += (hash(pix + fract(t * 0.1) * 100.0) - 0.5) * 0.02;
  col = hueShift(max(col, 0.0), p_hue + p_follow * u_hue) * p_bright;
  return clamp(col, 0.0, 1.0);
}
