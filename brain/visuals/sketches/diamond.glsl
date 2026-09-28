// Diamond: prismatic fire through a brilliant-cut diamond — caustic folds from faceted
// refraction, chromatic dispersion into rainbow fire, scintillating sparkles and star
// bursts (after "Diamond Caustics" in Paul Bakaus's Radiant collection, MIT). Ported
// nearly line for line; changes: its 17 reversed smoothsteps (undefined in GLSL) go
// through rsmooth(), which is 1 - smoothstep with the edges the right way round; its own
// hash renamed (it clashed with the renderer's) and a local named refract renamed (it hid
// the built-in); float loop counters made int; the dispersion seam fixed; time in beats; sparkles and star bursts
// flash on the kick; zoom and hue controls.
// Params are p_* uniforms; ranges and defaults are in diamond.json.
uniform float p_speed, p_rot, p_brilliance, p_fire, p_sparkle, p_stars, p_punch, p_zoom,
              p_hue, p_follow, p_bright;

#define PI 3.14159265359
#define TAU 6.28318530718

// smoothstep(a, b, x) with a > b, written so every GPU agrees.
float rsmooth(float a, float b, float x) { return 1.0 - smoothstep(b, a, x); }

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
float dhash(vec2 p) {
  p = fract(p * vec2(443.897, 441.423));
  p += dot(p, p.yx + 19.19);
  return fract((p.x + p.y) * p.x);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(dhash(i), dhash(i + vec2(1.0, 0.0)), f.x), mix(dhash(i + vec2(0.0, 1.0)), dhash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Hex cells: xy = offset from the cell centre, z = hex distance, w = a random per cell.
vec4 hexGrid(vec2 p) {
  vec2 s = vec2(1.0, 1.7320508), h = s * 0.5;
  vec2 a = mod(p, s) - h, b = mod(p - h, s) - h;
  vec2 ga = dot(a, a) < dot(b, b) ? a : b;
  vec2 ab = abs(ga);
  return vec4(ga, max(dot(ab, normalize(vec2(1.0, 1.7320508))), ab.x), dhash(p - ga));
}
float triGrid(vec2 p) {
  vec2 f = fract(vec2(p.x + p.y * 0.57735, p.y * 1.1547));
  return min(min(f.x, f.y), abs(1.0 - f.x - f.y));
}

// Brilliant-cut facet edges, seen from above.
float brilliantFacets(vec2 uv) {
  float r = length(uv), a = atan(uv.y, uv.x);
  float starAngle = mod(a + PI / 8.0, PI / 4.0) - PI / 8.0;
  float starEdge = rsmooth(0.01, 0.0, abs(r - 0.18) - abs(starAngle) * 8.0 / PI * 0.08);
  float kiteEdge = rsmooth(0.01, 0.0, abs(mod(a, PI / 4.0) - PI / 8.0) * r * 6.0 - 0.02);
  float kiteRing = rsmooth(0.01, 0.0, abs(r - 0.28) - 0.005);
  float ugEdge = rsmooth(0.01, 0.0, abs(mod(a, PI / 8.0) - PI / 16.0) * r * 10.0 - 0.02);
  float ugRing = rsmooth(0.01, 0.0, abs(r - 0.38) - 0.005);
  float girdle = rsmooth(0.01, 0.0, abs(r - 0.45) - 0.008);
  float edges = max(max(max(starEdge, kiteEdge), max(ugEdge, girdle)), max(kiteRing, ugRing));
  float inRing = step(0.12, r) * step(r, 0.46);
  float radLine16 = rsmooth(0.008, 0.0, abs(mod(a, PI / 8.0) - PI / 16.0) * r * 4.0 - 0.004) * inRing;
  float radLine8 = rsmooth(0.006, 0.0, abs(mod(a + PI / 8.0, PI / 4.0) - PI / 8.0) * r * 5.0 - 0.003) * inRing;
  return max(edges, max(radLine16 * 0.5, radLine8));
}

vec3 spectral(float t) {
  t = fract(t);
  vec3 c;
  c.r = smoothstep(0.0, 0.15, t) - smoothstep(0.35, 0.5, t) + smoothstep(0.8, 0.95, t);
  c.g = smoothstep(0.15, 0.35, t) - smoothstep(0.55, 0.75, t);
  c.b = smoothstep(0.4, 0.6, t) - smoothstep(0.75, 0.95, t);
  return pow(max(c, 0.0), vec3(0.6)) * 3.0;
}

// Light concentrated by faceted refraction: each hex facet bends light its own way.
float diamondCaustic(vec2 uv, float time, float scale, float rotation) {
  vec2 p = rot(rotation) * uv * scale;
  vec4 hex = hexGrid(p);
  float cellRand = hex.w;
  float facetAngle = cellRand * TAU + time * 0.3;
  vec2 bend = vec2(cos(facetAngle), sin(facetAngle)) * 0.3;
  vec2 displaced = p + bend * (1.0 + 0.5 * sin(time * 0.7 + cellRand * 10.0));
  vec4 hex2 = hexGrid(displaced * 1.5);
  float caustic = 1.0 - smoothstep(0.0, 0.4, hex.z);
  float fold = pow(1.0 - smoothstep(0.0, 0.25, hex2.z), 2.0);
  float interference = pow(abs(sin(displaced.x * 8.0 + time * 0.5) * sin(displaced.y * 8.0 - time * 0.4)), 1.5) * 0.5;
  return caustic * 0.3 + fold * 0.5 + interference * 0.2;
}

float scintillation(vec2 uv, float time) {
  float sparkle = 0.0;
  for (int ii = 0; ii < 3; ii++) {
    float i = float(ii);
    float sc = 5.0 + i * 4.0;
    vec2 grid = floor(uv * sc);
    vec2 f = fract(uv * sc) - 0.5;
    float h = dhash(grid + i * 100.0);
    float flash = pow(max(sin(h * TAU + time * (1.5 + h * 2.0)), 0.0), 48.0);
    sparkle += flash * rsmooth(0.15, 0.0, length(f)) * (1.0 - i * 0.25);
  }
  return sparkle;
}
float starBurst(vec2 uv) {
  float r = length(uv), a = atan(uv.y, uv.x);
  float star4 = pow(abs(cos(a * 2.0)), 64.0) / (r * 20.0 + 1.0);
  float star6 = pow(abs(cos(a * 3.0)), 64.0) / (r * 25.0 + 1.0);
  return (star4 + star6 * 0.5) * rsmooth(0.5, 0.0, r);
}
vec3 hueShift(vec3 c, float turns) {
  float a = turns * TAU;
  vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec3 content(vec2 uv0) {
  vec2 uv = (uv0 - 0.5) * vec2(u_aspect, 1.0) / min(u_aspect, 1.0) / max(p_zoom, 0.05);
  uv.y = -uv.y;
  float t = u_beat * p_speed;
  float k = kick();
  float rotSpeed = p_rot;
  float brilliance = p_brilliance;
  float kb = 1.0 + p_punch * k;

  vec2 uvRot = rot(t * rotSpeed * 0.1) * uv;

  // Crystal structure: brilliant-cut facets, triangular and hex facet grids.
  float facetPattern = brilliantFacets(uvRot * 2.2);
  float tri1 = triGrid(rot(t * 0.05) * uv * 8.0);
  float tri2 = triGrid(rot(-t * 0.07 + 1.0) * uv * 12.0);
  float triEdges = rsmooth(0.04, 0.0, tri1) * 0.3 + rsmooth(0.03, 0.0, tri2) * 0.15;
  vec4 mainHex = hexGrid(rot(t * 0.06) * uv * 6.0);
  float hexEdges = rsmooth(0.44, 0.40, mainHex.z) - rsmooth(0.40, 0.36, mainHex.z);
  float hexOutline = rsmooth(0.45, 0.43, mainHex.z) - rsmooth(0.43, 0.41, mainHex.z);

  // Caustic fire at three scales.
  float c1 = diamondCaustic(uv, t, 3.0, t * rotSpeed * 0.15);
  float c2 = diamondCaustic(uv, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + PI * 0.3);
  float c3 = diamondCaustic(uv, t * 0.9 + 20.0, 8.0, t * rotSpeed * 0.08 + PI * 0.7);
  float caustics = pow(c1 * 0.5 + c2 * 0.3 + c3 * 0.2, 1.3) * 3.5;

  // Dispersion: each colour samples the caustics from a slightly different place.
  float dispersion = 0.018 * (1.0 + caustics * 0.3) * p_fire;
  // The original used atan * 0.5, which jumps at the negative x axis and drew a seam;
  // a whole turn per turn keeps it continuous.
  float dispAngle = t * rotSpeed * 0.3 + atan(uv.y, uv.x);
  vec2 rOff = vec2(cos(dispAngle), sin(dispAngle)) * dispersion;
  vec2 gOff = vec2(cos(dispAngle + TAU / 3.0), sin(dispAngle + TAU / 3.0)) * dispersion;
  vec2 bOff = vec2(cos(dispAngle + TAU * 2.0 / 3.0), sin(dispAngle + TAU * 2.0 / 3.0)) * dispersion;
  float cR = diamondCaustic(uv + rOff, t, 3.0, t * rotSpeed * 0.15) + diamondCaustic(uv + rOff, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + PI * 0.3) * 0.6;
  float cG = diamondCaustic(uv + gOff, t, 3.0, t * rotSpeed * 0.15) + diamondCaustic(uv + gOff, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + PI * 0.3) * 0.6;
  float cB = diamondCaustic(uv + bOff, t, 3.0, t * rotSpeed * 0.15) + diamondCaustic(uv + bOff, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + PI * 0.3) * 0.6;
  vec3 chromatic = vec3(cR, cG, cB);
  float chrDiff = abs(cR - cG) + abs(cG - cB) + abs(cB - cR);

  float specPhase = atan(cR - cG, cG - cB) / TAU + 0.5 + t * 0.03 + length(uv) * 0.5;
  vec3 fireColor = spectral(specPhase);
  vec3 fireColor2 = spectral(vnoise(uvRot * 3.0 + t * 0.2) + t * 0.05);

  float sparkle = scintillation(uvRot, t * rotSpeed);
  float starTotal = 0.0;
  for (int ii = 0; ii < 4; ii++) {
    float i = float(ii);
    float sc = 4.0 + i * 3.0;
    vec2 grid = floor(rot(i * 0.7 + t * 0.03) * uv * sc);
    vec2 center = rot(-i * 0.7 - t * 0.03) * ((grid + 0.5) / sc);
    float h = dhash(grid + i * 77.0);
    float flash = pow(max(sin(h * TAU + t * (1.0 + h)), 0.0), 24.0);
    starTotal += starBurst((uv - center) * sc * 0.8) * flash * 0.35;
  }

  vec3 col = vec3(0.92, 0.95, 1.0) * caustics * 1.2;
  col += chromatic * 0.5 * brilliance;
  col += fireColor * smoothstep(0.03, 0.25, chrDiff) * caustics * 2.5 * brilliance * p_fire;
  col += fireColor2 * caustics * 0.6 * brilliance;

  vec3 facetColor = vec3(0.7, 0.75, 0.85);
  float structureMask = smoothstep(0.1, 0.5, caustics);
  col += facetColor * facetPattern * 0.04 * structureMask;
  col += facetColor * triEdges * hexEdges * 0.03 * (0.3 + structureMask * 0.7);
  col += vec3(0.8, 0.85, 0.95) * hexOutline * 0.025 * (0.2 + structureMask * 0.8);

  // Sparkles and star bursts: brighter on the kick.
  col += vec3(1.0, 0.98, 0.95) * sparkle * 3.5 * brilliance * p_sparkle * kb;
  col += mix(vec3(1.0, 0.97, 0.92), spectral(fract(t * 0.15 + starTotal * 2.0)), 0.5) * starTotal * 2.5 * brilliance * p_stars * kb;

  col += vec3(0.78, 0.58, 0.42) * caustics * 0.08;
  float centerGlow = rsmooth(0.6, 0.0, length(uv));
  col *= 0.8 + centerGlow * 0.8;

  // Hearts-and-arrows flashes and a prismatic sweep.
  float flashPhase = sin(t * rotSpeed * 1.7 + uvRot.x * 4.0) * cos(t * rotSpeed * 2.3 + uvRot.y * 3.0);
  col += spectral(fract(t * 0.2 + atan(uvRot.y, uvRot.x) / TAU)) * pow(max(flashPhase, 0.0), 10.0) * 3.5 * centerGlow * brilliance;
  float sweep = pow(max(sin(uv.x * 3.0 + uv.y * 2.0 + t * rotSpeed * 0.5), 0.0), 4.0) * 0.35;
  col += spectral(t * 0.1 + uv.x * 0.3) * sweep * brilliance;

  col *= max(1.0 - dot(uv, uv) * 0.35, 0.0);
  col = hueShift(max(col, 0.0), p_hue + p_follow * u_hue);
  col = max(col, 0.0) * 2.2 * p_bright;
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
  col = pow(max(col, 0.0), vec3(0.97, 0.98, 1.03)) + vec3(0.008, 0.008, 0.012);
  return clamp(col, 0.0, 1.0);
}
