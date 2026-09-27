// Orb: a black glass orb with a pearl circling inside it, on warm vintage paper, after
// Whiskas fx's video for Max Cooper's Harmonisch Serie. Mirror folds it into repeating copies
// and Split pulls the colour channels apart on the kick (the video's later look).
// Params are p_* uniforms; ranges and defaults are in orb.json.
uniform float p_size, p_wobble, p_pearl, p_orbit, p_gloss, p_warm, p_mirror, p_tile, p_split,
              p_hue, p_sat, p_follow, p_beat;

#define TAU 6.2831853

float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 scene(vec2 p, float k) {
  float t = u_beat;
  // Paper: cream in the middle, burnt at the edges.
  vec3 paper = mix(vec3(0.93, 0.88, 0.74), vec3(0.3, 0.24, 0.16), clamp(dot(p, p) * 0.9, 0.0, 1.0));
  vec3 col = mix(vec3(0.05), paper, p_warm);

  // Orb, slightly irregular.
  float R = p_size * (1.0 + 0.05 * k);
  float r = length(p), a = atan(p.y, p.x);
  R *= 1.0 + p_wobble * 0.06 * (vnoise(vec2(cos(a), sin(a)) * 2.0 + t * 0.05) - 0.5);
  float px = u_px;
  float orb = 1.0 - smoothstep(R - px, R + px, r);
  float rr = clamp(r / R, 0.0, 1.0);
  vec3 glass = mix(vec3(0.03, 0.025, 0.02), vec3(0.28, 0.24, 0.2), pow(rr, 5.0));        // rim catches light
  glass += paper * 0.25 * smoothstep(0.55, 1.0, rr) * (0.5 + 0.5 * p.y / max(R, 1e-3));
  vec2 hl = (p - vec2(-0.35, -0.4) * R) / R;
  glass += vec3(1.0) * p_gloss * 0.5 * exp(-dot(hl * vec2(1.0, 2.2), hl * vec2(1.0, 2.2)) * 30.0);
  col = mix(col, glass, orb);

  // Pearl in a pale hollow, circling at Orbit cycles per 4 beats.
  float ang = t * p_orbit * TAU / 4.0;
  vec2 c = vec2(cos(ang), sin(ang) * 0.6) * R * 0.3;
  float pr = R * p_pearl * (1.0 + 0.1 * k);
  float hol = 1.0 - smoothstep(pr * 1.45 - px, pr * 1.45 + px, length(p - c));
  col = mix(col, paper * 0.95, hol * orb);
  vec2 q = (p - c) / pr;
  float pm = 1.0 - smoothstep(1.0 - px / pr, 1.0 + px / pr, length(q));
  float z = sqrt(max(0.0, 1.0 - dot(q, q)));
  vec3 nrm = vec3(q, z);
  float diff = clamp(dot(nrm, normalize(vec3(-0.5, -0.6, 0.6))), 0.0, 1.0);
  vec3 tint = hsv(p_hue + (p_follow > 0.5 ? u_hue : 0.0) + 0.1 * q.x, p_sat, 1.0);
  vec3 pearl = mix(vec3(0.55, 0.5, 0.45), tint, 0.4) * (0.3 + 0.8 * diff);
  pearl += vec3(1.0) * pow(diff, 30.0) * p_gloss;
  col = mix(col, pearl, pm * orb);
  return col;
}

vec3 content(vec2 uv) {
  float k = kick() * p_beat;
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  // Mirror: 1 folds into four mirrored quadrants, 2 tiles a grid of them.
  if (p_mirror > 0.5) {
    if (p_mirror > 1.5) p = (fract(p * p_tile + 0.5) - 0.5) / p_tile;
    else p = abs(p) - vec2(0.25 * u_aspect, 0.25);
  }
  if (p_split <= 0.0) return scene(p, k);
  vec2 o = vec2(p_split * 0.02 * (0.3 + k), 0.0);
  return vec3(scene(p + o, k).r, scene(p, k).g, scene(p - o, k).b);
}
