// Pipes: white square pipes running through a grey tiled room, after Graphset's video for
// Max Cooper's Echoes Reality. Each grid cell holds a straight, a corner or nothing (Truchet
// tiles), shaded as a tube with a drop shadow; two layers drift at different speeds for depth,
// and cells re-roll every few bars. Params are p_* uniforms; ranges and defaults in pipes.json.
uniform float p_scale, p_width, p_density, p_square, p_drift, p_reroll, p_layers, p_shadow, p_room,
              p_hue, p_sat, p_beat;

float sdSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Distance to the pipe path in one cell (q in 0..1): type 0-1 straights, 2-5 corners.
float pipeD(vec2 q, float type, float sq) {
  vec2 c = q - 0.5;
  if (type < 0.5) return abs(c.y);
  if (type < 1.5) return abs(c.x);
  // Corner joining two edge midpoints: rotate so it always joins left and top.
  float r = type - 2.0;
  if (r > 0.5) c = vec2(-c.y, c.x);
  if (r > 1.5) c = vec2(-c.y, c.x);
  if (r > 2.5) c = vec2(-c.y, c.x);
  vec2 d = c + 0.5;                                      // corner at the cell's top-left
  float round0 = abs(length(d) - 0.5);                   // quarter circle
  float square0 = min(sdSeg(d, vec2(0.0, 0.5), vec2(0.5, 0.5)), sdSeg(d, vec2(0.5, 0.5), vec2(0.5, 0.0)));
  return mix(round0, square0, sq);
}

// One layer of pipes: returns (coverage, shade, shadow).
vec3 layer(vec2 P, float scale, float seed, float w, float px) {
  vec2 g = P * scale;
  vec2 id = floor(g), q = fract(g);
  float roll = floor(u_beat / max(p_reroll * 4.0, 1.0));
  float h = hash(id + seed + (hash(id + seed * 3.0) < 0.3 ? roll * 0.17 : 0.0));
  float cov = 0.0, shade = 0.0, sh = 0.0;
  if (h < p_density) {
    float type = floor(hash(id + seed + 5.5) * 6.0);
    float d = pipeD(q, type, p_square);
    float pw = w * scale;
    float ppx = px * scale;
    cov = 1.0 - smoothstep(pw - ppx, pw + ppx, d);
    float tt = clamp(d / pw, 0.0, 1.0);
    shade = 1.0 - tt * tt * 0.65;                        // round tube: bright centre, darker edges
    float ds = pipeD(fract(g - vec2(0.12, -0.12)), type, p_square);
    sh = 1.0 - smoothstep(pw - ppx, pw + ppx * 6.0, ds);
  }
  return vec3(cov, shade, sh);
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float A = u_aspect;
  vec2 P = vec2(uv.x * A, uv.y);

  // Room: grey tiles, a darker floor with lines running to a vanishing point.
  vec3 col = vec3(0.55);
  vec2 tg = abs(fract(P * 30.0) - 0.5);
  col -= 0.08 * p_room * (1.0 - smoothstep(0.44, 0.5, max(tg.x, tg.y)));
  if (uv.y > 0.7) {
    float fy = (uv.y - 0.7) / 0.3;
    col *= 0.75 - 0.2 * fy;
    float lx = (uv.x - 0.5) / max(fy, 0.02);
    col -= 0.08 * p_room * (1.0 - smoothstep(0.0, 0.03, abs(fract(lx * 6.0) - 0.5) - 0.47));
  }
  col *= 1.0 - 0.4 * dot(uv - 0.5, uv - 0.5);

  vec3 white = mix(vec3(0.95), hsv(p_hue, 1.0, 1.0), p_sat);
  float w = p_width;
  // Far layer first (smaller, slower), then near.
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    if (fi >= p_layers) break;
    float sc = fi < 0.5 && p_layers > 1.5 ? p_scale * 1.8 : p_scale;
    float sp = fi < 0.5 && p_layers > 1.5 ? 0.5 : 1.0;
    vec2 Q = P + vec2(t * p_drift * sp / 32.0, 0.0);
    vec3 L = layer(Q, sc, fi * 17.0, w * (fi < 0.5 && p_layers > 1.5 ? 0.8 : 1.0), u_px);
    col *= 1.0 - p_shadow * 0.45 * L.z * (1.0 - L.x);
    vec3 pc = white * L.y * (0.9 + 0.15 * k) * (fi < 0.5 && p_layers > 1.5 ? 0.8 : 1.0);
    col = mix(col, pc, L.x);
  }
  return clamp(col, 0.0, 1.0);
}
