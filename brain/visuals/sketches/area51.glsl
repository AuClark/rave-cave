// Area 51: things in the sky. Modes:
//   0 Radar: a scope with a beat-locked sweep; blips light as it passes, one moves wrong
//   1 Tractor beam: a saucer at the top, lights chasing round its rim, a beam that grows
//     through a BUILD and blazes on the DROP, rings falling and particles rising in it
//   2 Crop circle: a glowing formation in a night field, satellites turning, pulsing on the beat
// Params are p_* uniforms; ranges and defaults are in area51.json.
uniform float p_mode, p_speed, p_size, p_rings, p_count, p_beam, p_build, p_glow, p_hue, p_sat,
              p_follow, p_beat;

#define TAU 6.2831853
#define PI 3.1415927

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float A = u_aspect;
  vec2 p = (uv - 0.5) * vec2(A, 1.0);                     // y down
  float px = u_px;
  vec3 hc = hsv(p_hue + (p_follow > 0.5 ? u_hue : 0.0), p_sat, 1.0);
  bool drop = abs(u_scene - 7.0) < 0.5, build = abs(u_scene - 4.0) < 0.5 || abs(u_scene - 6.0) < 0.5;
  vec3 col = vec3(0.0);

  if (p_mode < 0.5) {
    // Radar. Sweep: one turn per 4 beats at Speed 1.
    vec2 q = p / (0.46 * p_size);
    float r = length(q), a = atan(q.y, q.x);
    float qpx = px / (0.46 * p_size);
    float sw = mod(t * p_speed * TAU / 4.0, TAU);
    float behind = mod(sw - a, TAU);
    float scope = 1.0 - smoothstep(1.0 - qpx, 1.0 + qpx, r);
    float trail = exp(-behind * 2.2) * scope;
    float grid = 0.0;
    float nr = max(1.0, floor(p_rings));
    float ringd = abs(fract(r * nr + 0.5) - 0.5) / nr;
    grid += (1.0 - smoothstep(0.004 - qpx, 0.004 + qpx, ringd)) * step(r, 1.0);
    grid += (1.0 - smoothstep(0.003 - qpx, 0.003 + qpx, min(abs(q.x), abs(q.y)))) * scope;
    grid += 1.0 - smoothstep(0.006 - qpx, 0.006 + qpx, abs(r - 1.0));
    float blips = 0.0;
    for (int i = 0; i < 16; i++) {
      float fi = float(i);
      if (fi >= p_count) break;
      vec2 bp = vec2(hash(vec2(fi, 1.0)), hash(vec2(fi, 2.0))) * 1.6 - 0.8;
      if (fi < 0.5) bp = 0.6 * vec2(cos(t * 0.37), sin(t * 0.53 + sin(t * 0.21) * 2.0));   // the one that moves wrong
      else bp += 0.03 * vec2(sin(t * 0.05 + fi), cos(t * 0.04 + fi));
      if (length(bp) > 0.95) continue;
      float ab = atan(bp.y, bp.x);
      float lit = exp(-mod(sw - ab, TAU) * 1.2);
      blips += (1.0 - smoothstep(0.02 - qpx, 0.02 + qpx, length(q - bp))) * (0.25 + lit * 1.5) * (fi < 0.5 ? 1.5 : 1.0);
      blips += p_glow * 0.02 / (dot(q - bp, q - bp) + 0.002) * lit * 0.1;
    }
    col = hc * (grid * 0.35 + trail * 0.7 + blips) + hc * scope * 0.04;
    col *= 1.0 + 0.3 * k;
  } else if (p_mode < 1.5) {
    // Tractor beam.
    float lvl = p_beam;
    if (build) lvl = mix(lvl, 1.0, p_build * u_sp);
    if (drop) lvl = 1.0 + 0.5 * exp(-u_since * 0.6);
    vec2 sc = vec2(0.0, -0.3 + 0.01 * sin(t * PI * 0.5));      // saucer centre (up is -y)
    float S = 0.22 * p_size;
    vec2 d = (p - sc) / S;
    // Beam: a cone from the saucer's belly to the ground.
    float yb = p.y - sc.y - 0.05 * S;
    float half0 = 0.35 * S + yb * 0.55;
    float inBeam = yb > 0.0 ? 1.0 - smoothstep(half0 - px * 2.0, half0 + px * 2.0, abs(p.x)) : 0.0;
    float across = yb > 0.0 ? abs(p.x) / max(half0, 1e-3) : 1.0;
    float rings = pow(0.5 + 0.5 * cos(TAU * (yb * p_rings * 2.0 - t * p_speed)), 6.0);
    float parts = 0.0;
    vec2 pg = vec2(p.x * 40.0, yb * 40.0 + t * p_speed * 6.0);
    vec2 pid = floor(pg);
    if (hash(pid) > 0.93) parts = 1.0 - smoothstep(0.1, 0.35, length(fract(pg) - 0.5));
    vec3 beam = hc * inBeam * lvl * (0.18 + 0.25 * (1.0 - across * across) + 0.5 * rings * 0.6 + parts * 0.8);
    beam *= 1.0 - smoothstep(0.35, 0.55, p.y);                  // fades into the ground
    // Saucer: a disc, a dome, lights chasing round the rim on the beat.
    float disc = length(d * vec2(1.0, 4.0)) - 1.0;
    float dome = length((d - vec2(0.0, -0.18)) * vec2(1.6, 1.6)) - 0.55;
    dome = max(dome, d.y + 0.05);
    float body = min(disc, dome);
    float spx = px / S;
    float bodyM = 1.0 - smoothstep(-spx * 4.0, spx * 4.0, body);
    vec3 metal = mix(vec3(0.25, 0.27, 0.3), vec3(0.75, 0.8, 0.85), clamp(-d.y * 2.0 + 0.5, 0.0, 1.0));
    float n = max(3.0, floor(p_count));
    float lights = 0.0;
    for (int i = 0; i < 16; i++) {
      float fi = float(i);
      if (fi >= n) break;
      float ang = fi / n * PI;                               // front half of the rim
      vec2 lp = vec2(-cos(ang) * 0.92, sin(ang) * 0.08);
      float on = abs(mod(floor(t * 2.0), n) - fi) < 0.5 ? 1.0 : 0.25;
      lights += (1.0 - smoothstep(0.05, 0.08, length((d - lp) * vec2(1.0, 1.0)))) * on;
    }
    col = beam + mix(vec3(0.0), metal, bodyM) + hc * lights * 1.5 + hc * p_glow * 0.25 * exp(-max(body, 0.0) * 3.0) * lvl;
    // A few stars.
    vec2 st = floor(uv * vec2(A, 1.0) * 90.0);
    col += vec3(0.6) * step(0.997, hash(st)) * (1.0 - inBeam) * (0.5 + 0.5 * sin(t + hash(st + 1.0) * 6.0));
  } else {
    // Crop circle, from above, at night.
    vec2 q = p / (0.42 * p_size);
    float qpx = px / (0.42 * p_size);
    float r = length(q), a = atan(q.y, q.x);
    float swirl = sin(a * 40.0 + r * 30.0) * 0.5 + 0.5;
    float field = 0.1 + 0.06 * sin((q.x + q.y * 0.3) * 160.0 + hash(floor(q * 10.0)) * 6.0);
    float n = max(3.0, floor(p_count));
    float rot = t * p_speed * TAU / 32.0;
    float dd = abs(r - 0.62) - 0.035;                           // main ring
    dd = min(dd, r - 0.22);                                     // centre disc
    dd = min(dd, abs(r - 0.36) - 0.012);                        // inner ring
    float sec = TAU / n;
    float as = mod(a - rot + sec * 0.5, sec) - sec * 0.5;
    vec2 sp = r * vec2(cos(as), sin(as));
    dd = min(dd, length(sp - vec2(0.62, 0.0)) - 0.11);          // satellites on the ring
    dd = min(dd, length(sp - vec2(0.95, 0.0)) - 0.045);         // small ones outside
    dd = min(dd, max(abs(sp.y) - 0.012, max(sp.x - 0.95, 0.62 - sp.x)));   // paths out to them
    float nr = floor(p_rings);
    if (nr > 0.5) dd = min(dd, abs(abs(fract(r * nr * 1.5) - 0.5) - 0.25) * 0.3 / nr + 0.004);
    float flatM = 1.0 - smoothstep(-qpx, qpx, dd);
    float outline = 1.0 - smoothstep(0.004 - qpx, 0.004 + qpx, abs(dd));
    vec3 wheat = vec3(0.12, 0.13, 0.1) * field * 4.0;
    vec3 flattened = mix(vec3(0.3, 0.32, 0.25), hc, 0.6) * (0.6 + 0.4 * swirl);
    col = mix(wheat, flattened * (0.7 + 0.6 * k), flatM) + hc * outline * p_glow * (0.6 + k);
    col += hc * p_glow * 0.15 * exp(-max(dd, 0.0) * 18.0);
  }
  return 1.0 - exp(-col * 1.3);
}
