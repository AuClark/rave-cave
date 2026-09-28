// Horizon: a Schwarzschild black hole, ray traced — light bends along its geodesic
// (velocity-Verlet), crossing a Novikov-Thorne accretion disk with Doppler beaming and
// gravitational redshift, the lensed far side of the disk arcing over the shadow, a
// photon ring and a lensed star field (after "Event Horizon" in Paul Bakaus's Radiant
// collection, MIT). Ported nearly line for line; changes: its hash renamed (it clashed
// with the renderer's), time in beats, the disk flares and the photon ring pulses on the
// kick, zoom, and a step-size control: the original takes up to 200 steps per pixel,
// the heaviest sketch here, so Step 2 halves that for the projector.
// Params are p_* uniforms; ranges and defaults are in horizon.json.
uniform float p_orbit, p_disk, p_spin, p_tilt, p_roll, p_zoom, p_chromatic, p_stars,
              p_punch, p_ring, p_step, p_bright;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;
const float RS = 1.0;        // Schwarzschild radius
const float ISCO = 3.0;      // innermost stable circular orbit
const float DISK_IN = 2.2;   // inner glow edge (infalling material)
const float DISK_OUT = 14.0; // outer disk edge

float bhash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
float gNoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(mix(bhash(i), bhash(i + vec2(1.0, 0.0)), u.x), mix(bhash(i + vec2(0.0, 1.0)), bhash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  mat2 rot = mat2(0.866, 0.5, -0.5, 0.866);
  for (int i = 0; i < 4; i++) { v += a * gNoise(p); p = rot * p * 2.03 + vec2(47.0, 13.0); a *= 0.49; }
  return v;
}
float fbmLite(vec2 p) {
  float v = 0.5 * gNoise(p);
  p = mat2(0.866, 0.5, -0.5, 0.866) * p * 2.03 + vec2(47.0, 13.0);
  return v + 0.25 * gNoise(p);
}

vec3 starField(vec3 rd) {
  float u = atan(rd.z, rd.x) / TAU + 0.5;
  float v = asin(clamp(rd.y, -0.999, 0.999)) / PI + 0.5;
  vec3 col = vec3(0.0);
  {
    vec2 cell = floor(vec2(u, v) * 55.0), f = fract(vec2(u, v) * 55.0);
    vec2 r = vec2(bhash(cell), bhash(cell + 127.1));
    float d = length(f - r);
    col += mix(vec3(1.0, 0.65, 0.35), vec3(0.55, 0.75, 1.0), r.y) * pow(r.x, 10.0) * exp(-d * d * 500.0) * 4.0;
  }
  {
    vec2 cell = floor(vec2(u, v) * 170.0), f = fract(vec2(u, v) * 170.0);
    vec2 r = vec2(bhash(cell + 43.0), bhash(cell + 91.0));
    float d = length(f - r);
    col += vec3(0.85, 0.88, 1.0) * pow(r.x, 18.0) * exp(-d * d * 1000.0) * 2.0;
  }
  float n = fbmLite(vec2(u, v) * 3.0) * fbmLite(vec2(u, v) * 5.5 + 10.0);
  col += vec3(0.10, 0.04, 0.14) * pow(n, 3.0);
  return col * p_stars;
}

vec3 bbColor(float t) {
  t = clamp(t, 0.0, 2.5);
  vec3 c = mix(vec3(1.0, 0.18, 0.0), vec3(1.0, 0.55, 0.12), smoothstep(0.0, 0.3, t));
  c = mix(c, vec3(1.0, 0.93, 0.82), smoothstep(0.3, 0.8, t));
  return mix(c, vec3(0.65, 0.82, 1.0), smoothstep(0.8, 1.8, t));
}

// The accretion disk: Novikov-Thorne temperature, Keplerian turbulence and rings,
// Doppler beaming and gravitational redshift.
vec4 shadeDisk(vec3 hit, vec3 vel, float time) {
  float r = length(hit.xz);
  if (r < DISK_IN * 0.5 || r > DISK_OUT * 1.05) return vec4(0.0);
  float xr = ISCO / r;
  float tProfile = pow(ISCO / r, 0.75) * pow(max(0.001, 1.0 - sqrt(xr)), 0.25);
  tProfile *= sqrt(max(0.01, 1.0 - RS / r));
  float lr = log2(max(r, 0.1));
  float omega = max(sqrt(0.5 * RS / (r * r * r)), 0.04) * 10.0;
  float rotAngle = time * omega;
  float ca = cos(rotAngle), sa = sin(rotAngle);
  vec2 rotXZ = vec2(hit.x * ca - hit.z * sa, hit.x * sa + hit.z * ca);
  float turb = 0.25 + 0.75 * fbm(rotXZ * 1.2 + vec2(lr * 3.0));
  float timeShift = time * 0.15;
  turb *= 0.7 + 0.3 * gNoise(rotXZ * 3.5 + vec2(100.0 + timeShift, timeShift * 0.7));
  float ringPhase1 = sin(r * 10.0 + rotAngle * r * 0.3) * 0.5 + 0.5;
  float ringPhase2 = sin(r * 20.0 - rotAngle * r * 0.15) * 0.5 + 0.5;
  turb *= 0.5 + 0.5 * (ringPhase1 * 0.55 + ringPhase2 * 0.45);

  float orbSpeed = sqrt(0.5 * RS / max(r, DISK_IN));
  vec3 orbDir = normalize(vec3(-hit.z, 0.0, hit.x));
  float dopplerFactor = max(0.15, 1.0 + 2.0 * dot(normalize(vel), orbDir) * orbSpeed);
  float dopplerBoost = dopplerFactor * dopplerFactor * dopplerFactor;

  float I = tProfile * turb * 6.0;
  I *= smoothstep(DISK_IN * 0.7, DISK_IN * 1.2, r);
  I *= 0.35 + 0.65 * smoothstep(ISCO * 0.85, ISCO * 1.2, r);
  I *= 1.0 - smoothstep(DISK_OUT * 0.55, DISK_OUT, r);

  float colorTemp = tProfile * pow(dopplerFactor, 1.8) * 1.2;
  vec3 col = bbColor(colorTemp) * I * dopplerBoost;

  if (p_chromatic > 0.01) {
    float hue = (r - DISK_IN) / (DISK_OUT - DISK_IN) * 0.8 + ringPhase1 * 0.4;
    vec3 spectrum;
    spectrum.r = (1.0 - smoothstep(0.0, 0.35, hue)) + smoothstep(0.25, 0.45, hue) * (1.0 - smoothstep(0.55, 0.7, hue)) * 0.7 + smoothstep(0.85, 1.1, hue) * 0.4;
    spectrum.g = smoothstep(0.15, 0.4, hue) * (1.0 - smoothstep(0.7, 0.95, hue));
    spectrum.b = smoothstep(0.5, 0.8, hue) + smoothstep(0.85, 1.1, hue) * 0.3;
    spectrum = max(spectrum, 0.05);
    float luma = dot(col, vec3(0.3, 0.5, 0.2));
    col = mix(col, spectrum * luma * 2.0, p_chromatic * 0.75);
  }
  return vec4(col, clamp(I * 1.3, 0.0, 0.96));
}

vec3 content(vec2 uv0) {
  float k = kick();
  // The original's view: centred, width = 1, y up; Zoom closes in.
  vec2 uv = vec2(uv0.x - 0.5, (0.5 - uv0.y) / u_aspect) / max(p_zoom, 0.05);

  float camR = 28.0;
  float orbit = u_beat * p_orbit * TAU / 64.0;       // turns per 64 beats
  float tilt = 0.25 + p_tilt;
  vec3 eye = vec3(camR * cos(orbit) * cos(tilt), camR * sin(tilt), camR * sin(orbit) * cos(tilt));
  vec3 fwd = normalize(-eye);
  vec3 rt = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(rt, fwd);
  float cr = cos(p_roll), sr = sin(p_roll);
  vec3 rr = cr * rt + sr * up, ru = -sr * rt + cr * up;
  vec3 rd = normalize(fwd + uv.x * rr + uv.y * ru);

  // Geodesic integration: a = -1.5 RS L^2 / r^5 x, with L = |x cross v| conserved.
  vec3 pos = eye, vel = rd;
  vec3 Lvec = cross(pos, vel);
  float gravCoeff = -1.5 * RS * dot(Lvec, Lvec);
  vec4 diskAccum = vec4(0.0);
  vec3 glow = vec3(0.0);
  bool absorbed = false;
  int diskCrossings = 0;
  float minR = 1000.0;
  float diskTime = u_beat * p_spin;
  float diskGain = p_disk * (1.0 + p_punch * k);
  float maxSteps = 200.0 / max(p_step, 1.0);

  for (int i = 0; i < 200; i++) {
    if (float(i) >= maxSteps) break;
    float r = length(pos);
    float h = 0.16 * clamp(r - 0.4 * RS, 0.06, 3.5) * p_step;
    float invR2 = 1.0 / (r * r);
    vec3 acc = (gravCoeff * invR2 * invR2 / r) * pos;
    vec3 p1 = pos + vel * h + 0.5 * acc * h * h;
    float r1 = length(p1);
    float invR12 = 1.0 / (r1 * r1);
    vec3 acc1 = (gravCoeff * invR12 * invR12 / r1) * p1;
    vec3 v1 = vel + 0.5 * (acc + acc1) * h;
    minR = min(minR, r1);

    // Crossing the disk plane: the first two crossings are the disk and its lensed
    // image; later ones are attenuated (they make the thin photon ring).
    if (pos.y * p1.y < 0.0 && diskAccum.a < 0.97) {
      vec3 hit = mix(pos, p1, pos.y / (pos.y - p1.y));
      vec4 dc = shadeDisk(hit, vel, diskTime);
      dc.rgb *= diskGain;
      if (diskCrossings >= 2) { dc.rgb *= 0.15; dc.a *= 0.15; }
      diskAccum.rgb += dc.rgb * dc.a * (1.0 - diskAccum.a);
      diskAccum.a += dc.a * (1.0 - diskAccum.a);
      glow += dc.rgb * 0.04 * max(dot(dc.rgb, vec3(0.3, 0.5, 0.2)) * dc.a - 0.3, 0.0);
      diskCrossings++;
    }
    if (r1 < 6.0) {
      float pDist = abs(r1 - 1.5 * RS);
      glow += vec3(0.8, 0.6, 0.35) * (1.0 / (1.0 + pDist * pDist * 20.0) * h * 0.001 / max(r1 * r1, 0.2));
      glow += vec3(0.5, 0.25, 0.08) * max(exp(-(r1 - RS) * 3.5) * h * 0.003, 0.0);
    }
    if (r1 < RS * 0.35) { absorbed = true; break; }
    if (r1 > 25.0 && r1 > r) break;
    if (r1 > 55.0) break;
    pos = p1;
    vel = v1;
  }

  vec3 col = absorbed ? vec3(0.0) : starField(normalize(vel));
  col = col * (1.0 - diskAccum.a) + diskAccum.rgb;

  // Chromatic fringe at the shadow's edge; the photon ring pulses on the kick.
  float ringDist = abs(minR - 1.5 * RS);
  float baseChroma = (0.1 + 0.5 * p_chromatic) * p_ring * (1.0 + p_punch * 1.5 * k);
  float spread = 0.08 + 0.18 * p_chromatic;
  float falloff = 20.0 + 15.0 * (1.0 - p_chromatic);
  col.r += exp(-(ringDist + spread) * (ringDist + spread) * falloff) * 0.3 * baseChroma;
  col.b += exp(-(ringDist - spread) * (ringDist - spread) * falloff) * 0.35 * baseChroma;
  col += glow;

  col *= 1.4 * p_bright;
  vec3 a = col * (col + 0.0245786) - 0.000090537;
  vec3 b = col * (0.983729 * col + 0.4329510) + 0.238081;
  col = smoothstep(0.0, 1.0, a / b);
  return clamp(pow(max(col, 0.0), vec3(0.92)), 0.0, 1.0);
}
