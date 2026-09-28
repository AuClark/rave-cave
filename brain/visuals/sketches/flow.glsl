// Flow: particles streaming through a noise flow field, leaving fading trails (after
// "Flow Field with Particle Trails" in Paul Bakaus's Radiant collection, MIT). The original
// keeps its trails by never clearing a Canvas 2D frame; sketches have no frame memory, so
// each pixel traces its streamline backwards instead. Every grid cell releases a particle
// from a seed point once per lifetime; a pixel is lit when its streamline passes a seed and
// that particle's head went past the pixel less than a trail length ago. Seeds move each
// lifetime, so there are no fixed sources. Beat-locked: speed is in surface heights per beat.
// Params are p_* uniforms; ranges and defaults are in flow.json.
uniform float p_scale, p_curl, p_evolve, p_density, p_speed, p_trail, p_width, p_vary, p_steps,
              p_punch, p_push, p_hue, p_spread, p_sat, p_bright, p_bg, p_follow;

#define TAU 6.2831853
#define MAXSTEPS 32

// 3D simplex noise (Ian McEwan, Ashima Arts; MIT).
vec4 permute(vec4 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
float snoise(vec3 v) {
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
  vec3 i = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;
  i = mod(i, 289.0);
  vec4 p = permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0))
                                 + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                                 + i.x + vec4(0.0, i1.x, i2.x, 1.0));
  vec3 ns = (1.0 / 7.0) * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);
  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);
  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));
  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);
  vec4 nrm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= nrm.x; p1 *= nrm.y; p2 *= nrm.z; p3 *= nrm.w;
  vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Flow direction at q (surface heights from the centre). The original steers by
// noise * 2π; Push bends the streams away from the centre on the kick.
vec2 flowDir(vec2 q, float z, float push) {
  float a = snoise(vec3(q * p_scale, z)) * TAU * p_curl;
  vec2 d = vec2(cos(a), sin(a));
  float r = length(q);
  d += push * q / max(r, 1e-3) * exp(-2.0 * r * r);
  return d / max(length(d), 1e-3);
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick();
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
  float z = t * p_evolve;

  float cell = 1.0 / p_density;                 // one particle per cell
  float h = 0.25 * cell;                         // trace step (keeps a segment inside its seed's cell)
  float reach = p_steps * h;                     // how far a particle travels in its life
  float life = reach / max(p_speed, 1e-3);       // in beats
  float r = 0.5 * p_width * u_px;                // line half-width

  // A second trace one pixel to the side measures how much the stream spreads between
  // the seed and here. Without it, where the flow diverges, every pixel whose stream
  // squeezes past a seed lights up and the thin trail becomes a fan.
  vec2 d0 = flowDir(p, z, p_push * k);
  vec2 q = p, qs = p + vec2(-d0.y, d0.x) * u_px;

  float lit = 0.0;
  vec2 dprev = d0;
  for (int i = 0; i < MAXSTEPS; i++) {
    if (float(i) >= p_steps) break;
    vec2 dq = flowDir(q, z, p_push * k);
    // A trace that doubles back has reached a point the streams fan out from and
    // would bounce there, lighting the whole fan. No particle comes from there: stop.
    if (dot(dq, dprev) < -0.2) break;
    dprev = dq;
    vec2 q1 = q - dq * h;                          // one step upstream
    vec2 qs1 = qs - flowDir(qs, z, p_push * k) * h;
    // Seed-side spacing per pixel here. Capped: where streams merge the side trace can
    // jump to another stream, and an unbounded J lights whole wedges.
    // Only the sideways part counts: shear turns the spacing along the stream, where it no
    // longer shrinks as streams squeeze together.
    vec2 sep = ((qs + qs1) - (q + q1)) * 0.5;
    float J = clamp(abs(sep.x * dq.y - sep.y * dq.x) / u_px, 1e-3, 1.0);
    vec2 c = floor((q + q1) * 0.5 * p_density);
    float age = t / life + hash(c + 0.37);        // in lifetimes, staggered per cell
    float gen = floor(age);
    float A = age - gen;                           // 0..1 through this particle's life
    vec2 seed = (c + 0.25 + 0.5 * vec2(hash(c + gen * 1.31 + 5.1), hash(c + gen * 2.17 + 9.7))) * cell;
    // Closest point on the segment q -> q1 to the seed, and the distance along the stream.
    vec2 ba = q1 - q, pa = seed - q;
    float f = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float d = length(pa - ba * f) / J;             // distance from the particle's path, in this pixel's units
    float s = (float(i) + f) * h;                  // seed to this pixel, downstream
    float behind = A * reach - s;                  // how far the head is past this pixel
    float v = hash(c + gen * 0.73 + 3.3);          // per-particle width and alpha, like the original
    float rw = r * mix(1.0, 0.35 + 1.3 * v, p_vary) * (1.0 + 0.5 * p_punch * k);
    float line = 1.0 - smoothstep(rw - 0.75 * u_px, rw + 0.75 * u_px, d);
    float trail = step(0.0, behind) * exp(-2.0 * behind / max(p_trail, 1e-3));
    float alpha = mix(1.0, 0.35 + 0.65 * hash(c + gen * 0.51 + 7.7), p_vary);
    float fade = smoothstep(0.0, 0.08, A) * (1.0 - smoothstep(0.85, 1.0, A));
    lit = max(lit, line * trail * alpha * fade);
    q = q1; qs = qs1;
  }

  // Colour by a second, slower noise, as in the original's palette lookup.
  float cn = snoise(vec3(p * p_scale * 1.5 + 100.0, z * 0.5));
  float hue = mix(p_hue, u_hue, p_follow) + cn * p_spread;
  vec3 col = hsv(hue, p_sat, 1.0) * p_bright * (1.0 + p_punch * k);
  return mix(vec3(p_bg), col, lit);
}
