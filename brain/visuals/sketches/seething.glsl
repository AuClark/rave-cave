// Seething: a lumpy ball of living cells, after Andy Lomas's video for Max Cooper. Cells are
// a jittering Voronoi pattern shaded as little domes on a shaded sphere; Folds carves brain-like
// creases through it; the mass breathes on the kick and grows through the song section.
// Params are p_* uniforms; ranges and defaults are in seething.json.
uniform float p_size, p_grow, p_lumps, p_density, p_jitter, p_cspeed, p_folds, p_fscale, p_shade,
              p_bg, p_hue, p_spread, p_sat, p_follow, p_beat;

#define TAU 6.2831853

float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  p.y = -p.y;
  float r = length(p);
  vec2 dir = p / max(r, 1e-4);

  // The mass: a lumpy outline that breathes and grows.
  float R = p_size * (1.0 + p_grow * (u_sp - 0.5)) * (1.0 + 0.05 * k);
  R *= 1.0 + p_lumps * (0.14 * (vnoise(dir * 2.5 + t * 0.03) - 0.5) + 0.06 * (vnoise(dir * 7.0 - t * 0.05) - 0.5));
  float inside = 1.0 - smoothstep(R - u_px, R + u_px, r);
  vec3 bg = vec3(p_bg);
  if (inside <= 0.0) return bg;

  // Fake sphere normal, and the cells on it (squashed towards the rim).
  float rr = clamp(r / R, 0.0, 0.999);
  float z = sqrt(1.0 - rr * rr);
  vec3 n = vec3(p / R, z);
  vec2 cp = p / R / (0.6 + 0.4 * z) * p_density;
  vec2 ci = floor(cp);
  float f1 = 9.0, f2 = 9.0;
  vec2 best = vec2(0.0), bid = vec2(0.0);
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 id = ci + vec2(float(i), float(j));
    vec2 o = vec2(hash(id), hash(id + 7.7));
    o = 0.5 + p_jitter * 0.45 * sin(TAU * (o + t * p_cspeed / 8.0));
    vec2 dv = id + o - cp;
    float d = dot(dv, dv);
    if (d < f1) { f2 = f1; f1 = d; best = dv; bid = id; } else if (d < f2) f2 = d;
  }
  f1 = sqrt(f1); f2 = sqrt(f2);
  float edge = f2 - f1;                                     // 0 on the walls between cells
  float cellR = 0.5;
  vec2 bump = -best / cellR;
  vec3 nn = normalize(n + vec3(bump * 1.3 * (1.0 - smoothstep(0.0, cellR, f1)), 0.0));

  // Folds: creases where a sum of waves crosses zero.
  float fold = 1.0;
  if (p_folds > 0.0) {
    float fs = 0.0;
    vec2 fp = p / R * p_fscale;
    for (int i = 0; i < 6; i++) {
      float fi = float(i), ang = fi * 0.5236 + 0.3 * hash(vec2(fi, 2.0));
      fs += cos(dot(fp, vec2(cos(ang), sin(ang))) * 6.2832 + hash(vec2(fi, 5.0)) * 6.2832 + t * 0.05 * (fi - 2.5));
    }
    fold = mix(1.0, smoothstep(0.0, 0.5, abs(fs) * 0.4), p_folds);
  }

  float diff = clamp(dot(nn, normalize(vec3(-0.5, 0.6, 0.7))), 0.0, 1.0);
  float spec = pow(clamp(dot(reflect(-normalize(vec3(-0.5, 0.6, 0.7)), nn), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 20.0);
  float wall = smoothstep(0.0, 0.2, edge);
  float light = mix(1.0, 0.25 + 0.85 * diff, p_shade) * wall * fold;
  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0) + p_spread * (hash(bid) - 0.5) * 0.2;
  vec3 col = hsv(hue0, p_sat, 1.0) * light + vec3(spec) * 0.35 * p_shade * wall;
  col *= 0.35 + 0.65 * z + 0.2 * k;                          // darker at the rim
  return mix(bg, col, inside);
}
