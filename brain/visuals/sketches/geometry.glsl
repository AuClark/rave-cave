// Geometry: unified parametric golden geometry, morphing from a tiled hex lattice of
// star rosettes to a single central mandala (after "Radiant Geometry" / "Sacred Strange"
// in Paul Bakaus's Radiant collection, MIT). Ported nearly line for line; changes:
// reversed smoothsteps (undefined in GLSL) written as 1 - smoothstep, time in beats, the
// pulses on the kick, and the Pattern morph can swing over a cycle of beats or build
// through the song section (lattice in the groove, mandala by the drop).
// Params are p_* uniforms; ranges and defaults are in geometry.json.
uniform float p_pattern, p_swing, p_cycle, p_morph, p_complexity, p_size, p_speed, p_rot,
              p_spin, p_punch, p_glow, p_tint, p_hue, p_sat, p_bright, p_follow;

#define PI 3.14159265359
#define TAU 6.28318530718
#define PHI 1.6180339887
#define SQRT3 1.7320508

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

vec3 tintc(vec3 c) {
  float lum = dot(max(c, 0.0), vec3(0.299, 0.587, 0.114));
  return mix(c, hsv(mix(p_hue, u_hue, p_follow), p_sat * (1.0 - 0.4 * smoothstep(0.6, 1.0, lum)), lum * 1.2), p_tint);
}
vec3 gold(float t) {
  return tintc(vec3(0.45, 0.32, 0.14) + vec3(0.45, 0.35, 0.2) * cos(TAU * (vec3(1.0, 0.8, 0.5) * t + vec3(0.0, 0.1, 0.25))));
}

vec2 polarFold(vec2 p, float n) {
  float sector = TAU / n;
  float angle = abs(mod(atan(p.y, p.x) + sector * 0.5, sector) - sector * 0.5);
  return vec2(cos(angle), sin(angle)) * length(p);
}
float sdSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
float sdRing(vec2 p, float r) { return abs(length(p) - r); }
float sdPolygon(vec2 p, float r, float n) {
  float sector = TAU / n;
  float a = mod(atan(p.y, p.x) + sector * 0.5, sector) - sector * 0.5;
  vec2 q = vec2(cos(a), abs(sin(a))) * length(p);
  vec2 edge = vec2(cos(sector * 0.5), sin(sector * 0.5)) * r;
  vec2 d = q - edge * clamp(dot(q, edge) / dot(edge, edge), 0.0, 1.0);
  return length(d) * sign(q.x * edge.y - q.y * edge.x);
}
vec3 glowLine(float d, vec3 coreColor, vec3 bloomColor, float lineWidth, float bloomWidth) {
  float core = pow(lineWidth / (abs(d) + lineWidth), 2.0);
  float bloom = pow(bloomWidth / (abs(d) + bloomWidth), 1.5);
  return coreColor * core + bloomColor * bloom * 0.4;
}

// The core star / rosette, drawn by polar folding and segments.
float starMotif(vec2 p, float symmetry, float breathe, float innerRatio, float petalInfluence) {
  float d = 1e9;
  vec2 fp = polarFold(p, symmetry * 2.0);
  vec2 a1 = vec2(0.5 * breathe, 0.0);
  vec2 b1 = vec2(mix(0.35, 0.32, innerRatio) * breathe, mix(0.15, 0.13, innerRatio) * breathe);
  d = min(d, sdSegment(fp, a1, b1));
  float innerR = mix(0.22, 0.18, innerRatio);
  vec2 b2 = vec2(innerR * breathe, 0.0);
  d = min(d, sdSegment(fp, b1, b2));
  vec2 b3 = vec2(mix(0.12, 0.10, innerRatio) * breathe, mix(0.07, 0.06, innerRatio) * breathe);
  d = min(d, sdSegment(fp, b2, b3));
  d = min(d, sdSegment(fp, b3, vec2(0.0)));
  d = min(d, sdRing(p, 0.5 * breathe));
  d = min(d, sdRing(p, innerR * breathe));
  if (petalInfluence > 0.01) {
    float petal = abs(length(fp - vec2(0.5 * breathe, 0.0)) - 0.5 * breathe * 0.35 / PHI) - 0.002;
    d = min(d, mix(1e9, petal, petalInfluence));
    float innerPetal = abs(length(fp - vec2(0.5 * breathe * 0.65, 0.0)) - 0.5 * breathe * 0.25) - 0.0015;
    d = min(d, mix(1e9, innerPetal, petalInfluence));
  }
  return d;
}
float hexTileMotif(vec2 p, float scale, float symmetry, float breathe, float innerRatio, float petalInfl) {
  p *= scale;
  vec2 s = vec2(1.0, SQRT3), h = s * 0.5;
  vec2 a = mod(p, s) - h, b = mod(p - h, s) - h;
  vec2 gUV = dot(a, a) < dot(b, b) ? a : b;
  return starMotif(gUV, symmetry, breathe, innerRatio, petalInfl) / scale;
}
float centralMotif(vec2 p, float scale, float symmetry, float breathe, float innerRatio, float petalInfl) {
  return starMotif(p * scale, symmetry, breathe, innerRatio, petalInfl) / scale;
}
// Tiled at tilingMix 0, one central motif at 1, cross-faded between.
float geometryLayer(vec2 p, float scale, float symmetry, float breathe, float innerRatio, float petalInfl, float tilingMix) {
  float centralScale = scale * 0.35;
  if (tilingMix < 0.01) return hexTileMotif(p, scale, symmetry, breathe, innerRatio, petalInfl);
  if (tilingMix > 0.99) return centralMotif(p, centralScale, symmetry, breathe, innerRatio, petalInfl);
  float dTiled = hexTileMotif(p, mix(scale, scale * 0.6, tilingMix), symmetry, breathe, innerRatio, petalInfl);
  float dCentral = centralMotif(p, mix(centralScale * 1.5, centralScale, tilingMix), symmetry, breathe, innerRatio, petalInfl);
  return mix(dTiled, dCentral, tilingMix);
}
float goldenSpiral(vec2 uv, float t, float rotSpd) {
  float r = length(uv);
  float a = atan(uv.y, uv.x);
  float spiralPhase = log(max(r, 0.001)) / log(PHI) * PI * 0.5;
  float spiralD = abs(mod(a - spiralPhase + t * rotSpd * 0.2 + PI, TAU) - PI);
  spiralD = min(spiralD, abs(mod(a - spiralPhase + t * rotSpd * 0.2 + PI + PI, TAU) - PI));
  float fade = smoothstep(0.0, 0.05, r) * (1.0 - smoothstep(0.35, 0.5, r));
  return spiralD * fade + (1.0 - fade);
}

vec3 content(vec2 uv0) {
  vec2 uv = (uv0 - 0.5) * vec2(u_aspect, 1.0) / min(u_aspect, 1.0) / max(p_size, 0.05);
  uv.y = -uv.y;
  uv = rot(u_beat * p_spin * TAU / 64.0) * uv;
  float t = u_beat * p_speed;
  float k = kick();
  float rotSpeed = p_rot;
  float complexity = p_complexity;
  float r = length(uv);

  // Pattern: the slider, swung over a cycle of beats, and built up through the section.
  float swing = 0.5 - 0.5 * cos(TAU * u_beat / max(p_cycle, 1.0));
  float pat = clamp(p_pattern + p_swing * swing + p_morph * u_sp, 0.0, 1.0);
  float tilingMix = pat;
  float baseSym = mix(6.0, 10.0, pat);
  float spiralInfluence = smoothstep(0.2, 0.8, pat);
  float centralGlowStr = mix(0.03, 0.12, pat);
  float petalInfluence = smoothstep(0.3, 0.9, pat);
  float objectRadius = mix(1.0, 0.48, pat * pat);
  float objectFade = mix(1.0, 1.0 - smoothstep(objectRadius * 0.7, objectRadius, r), pat);
  float breathe = 1.0 + 0.03 * sin(t * 0.6) + 0.02 * p_punch * k;
  float glowk = p_glow * (1.0 + p_punch * k);

  vec3 dimGold    = tintc(vec3(0.35, 0.25, 0.12));
  vec3 medGold    = tintc(vec3(0.7, 0.50, 0.22));
  vec3 brightGold = tintc(vec3(0.95, 0.72, 0.32));
  vec3 coreGlow   = tintc(vec3(1.0, 0.82, 0.55));
  vec3 hotGold    = tintc(vec3(1.0, 0.92, 0.72));

  vec3 col = tintc(vec3(0.02, 0.015, 0.01));
  float numLayers = clamp(2.0 + (complexity - 0.3) * (4.0 / 1.7), 2.0, 6.0);

  // Layer 1: the large structure, slowest.
  float d1 = geometryLayer(rot(t * rotSpeed * 0.04) * uv, mix(2.5, 1.8, pat) * complexity, floor(baseSym), breathe, 0.0, petalInfluence * 0.3, tilingMix);
  col += glowLine(d1, medGold, dimGold * 1.5, 0.002, 0.016) * glowk;
  // Layer 2: counter-rotating, higher symmetry.
  if (numLayers > 2.0) {
    float d2 = geometryLayer(rot(-t * rotSpeed * 0.06) * uv, mix(3.5, 2.2, pat) * complexity, floor(baseSym + 2.0), breathe, mix(0.3, 0.6, pat), petalInfluence * 0.5, tilingMix);
    col += glowLine(d2, brightGold * 0.8, dimGold * 1.2, 0.0015, 0.014) * min(numLayers - 2.0, 1.0) * glowk;
  }
  // Layer 3: fine girih detail, faster.
  if (numLayers > 3.0) {
    float d3 = geometryLayer(rot(t * rotSpeed * 0.09) * uv, mix(4.0, 2.5, pat) * complexity, floor(mix(5.0, 8.0, pat)), breathe * (1.0 + 0.01 * sin(t * 0.5 + 2.0)), 0.5, petalInfluence * 0.7, tilingMix);
    col += glowLine(d3, coreGlow * 0.6, medGold * 0.7, 0.0012, 0.012) * min(numLayers - 3.0, 1.0) * glowk;
  }
  // Layer 4: the central rosette.
  if (numLayers > 4.0) {
    float d4 = centralMotif(rot(t * rotSpeed * mix(0.03, 0.05, pat)) * uv, mix(2.2, 1.8, pat), floor(mix(8.0, 12.0, pat)), breathe, 0.7, petalInfluence);
    float centralFade = 1.0 - smoothstep(0.12, mix(0.5, 0.48, pat), r);
    col += glowLine(d4, hotGold * 0.7, coreGlow * 0.5, 0.0025, 0.022) * centralFade * min(numLayers - 4.0, 1.0) * glowk;
  }
  // Layer 5: concentric polygon rings.
  if (numLayers > 5.0) {
    float rScale = mix(0.12, 0.10, pat) * (1.0 + 0.04 * sin(t * 0.4));
    float s1 = mix(6.0, 8.0, pat), s2 = mix(8.0, 10.0, pat);
    float ringD = abs(sdPolygon(rot(t * rotSpeed * 0.02) * uv, rScale, s1));
    ringD = min(ringD, abs(sdPolygon(rot(-t * rotSpeed * 0.025) * uv, rScale * 2.0, s2)));
    ringD = min(ringD, abs(sdPolygon(rot(t * rotSpeed * 0.015) * uv, rScale * 3.0, 12.0)));
    ringD = min(ringD, abs(sdPolygon(rot(-t * rotSpeed * 0.018) * uv, rScale * 4.0, s1)));
    col += glowLine(ringD, brightGold * 0.5, dimGold * 0.5, 0.0012, 0.01) * min(numLayers - 5.0, 1.0) * glowk;
  }
  if (spiralInfluence > 0.01) {
    col += gold(0.7 + t * 0.01) * (0.015 / (goldenSpiral(uv, t, rotSpeed) + 0.015)) * 0.25 * spiralInfluence;
  }
  // Decorative edge, fading in toward the mandala end.
  if (pat > 0.3) {
    float decoFade = smoothstep(0.3, 0.7, pat);
    float outerRing = abs(r - objectRadius + 0.01) - 0.003;
    col += gold(0.5 + t * 0.015) * (0.004 / (abs(outerRing) + 0.004)) * 0.35 * decoFade * glowk;
    float outerRing2 = abs(r - objectRadius + 0.035) - 0.002;
    col += gold(0.6) * (0.003 / (abs(outerRing2) + 0.003)) * 0.2 * decoFade * glowk;
    float dotSym = mix(6.0, 12.0, pat);
    float dotA = mod(atan(uv.y, uv.x) + PI / dotSym, TAU / dotSym) - PI / dotSym;
    float dotD = length(vec2(cos(dotA), sin(dotA)) * r - vec2(objectRadius - 0.01, 0.0)) - 0.008;
    col += tintc(vec3(1.0, 0.9, 0.65)) * (0.004 / (abs(dotD) + 0.004)) * 0.3 * decoFade * glowk;
  }
  // Centre: glow and inner ring, pulsing on the kick.
  float centerPulse = 0.8 + 0.2 * sin(t * 1.5) + p_punch * 0.8 * k;
  col += hotGold * exp(-r * r * mix(3.0, 6.0, pat)) * centralGlowStr * 2.0 * centerPulse;
  if (pat > 0.2) {
    float ringPulse = 0.9 + 0.1 * sin(t * 2.3 + 1.0) + 0.4 * p_punch * k;
    float innerRing = abs(r - 0.03 * ringPulse) - 0.002;
    col += tintc(vec3(1.0, 0.88, 0.6)) * (0.003 / (abs(innerRing) + 0.003)) * 0.3 * smoothstep(0.2, 0.6, pat);
  }
  col += tintc(vec3(0.5, 0.35, 0.16)) * exp(-r * r * mix(2.5, 4.0, pat)) * mix(0.1, 0.14, pat);

  col *= objectFade;
  col *= 0.92 + 0.08 * sin(t * 0.3);
  col *= 0.65 + max(1.0 - r * r * mix(0.35, 0.25, pat), 0.0) * 0.35;
  col = max(col * p_bright, vec3(0.0));
  col = col / (1.0 + col * 0.3);
  col = pow(col, vec3(0.95, 0.98, 1.06));
  return clamp(col, 0.0, 1.0);
}
