// Phyllotaxis: a sunflower spiral growing from the centre (after "Phyllotaxis Spiral" in
// Paul Bakaus's Radiant collection, MIT). Point n sits at n golden angles round and
// spacing * sqrt(n) out. Its nearest neighbours are always a Fibonacci number of points
// away, so a pixel finds the few points that can touch it by solving for its place in the
// local Fibonacci lattice, not by looking at all of them. Growth runs over a cycle of beats
// (the oldest points fade from the middle, as in the original, and everything fades before
// it restarts). The original's per-point breathing is kept in the dot sizes; positions get
// a smooth ripple instead, which a pixel can still invert. Tilt replaces the mouse drag.
// Params are p_* uniforms; ranges and defaults are in phyllotaxis.json.
uniform float p_count, p_spacing, p_grow, p_cycle, p_spin, p_breath, p_tilt, p_ripple,
              p_size, p_glow, p_lattice, p_centre, p_vignette, p_punch,
              p_tint, p_hue, p_cspread, p_sat, p_bright, p_bg, p_follow;

#define PI 3.1415927
#define TAU 6.2831853
#define GAT 0.3819660113   // the golden angle in turns (1 - 1/phi)

vec3 over(vec3 c, vec3 s, float a) { return mix(c, s, clamp(a, 0.0, 1.0)); }
float disk(float dpx, float rpx) { return clamp(rpx - dpx + 0.5, 0.0, 1.0); }
float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / max(dot(ba, ba), 1e-9), 0.0, 1.0));
}

// The original's colours cycle amber -> gold -> coral along the spiral, or a tint.
vec3 pcol(float n) {
  vec3 amber = vec3(200.0, 149.0, 108.0) / 255.0;
  vec3 gold  = vec3(212.0, 165.0, 116.0) / 255.0;
  vec3 coral = vec3(224.0, 120.0, 80.0) / 255.0;
  float c = mod(n * 0.015, 3.0), t = fract(c);
  vec3 o = c < 1.0 ? mix(amber, gold, t) : (c < 2.0 ? mix(gold, coral, t) : mix(coral, amber, t));
  float lum = dot(o, vec3(0.299, 0.587, 0.114));
  vec3 tinted = hsv(mix(p_hue, u_hue, p_follow) + p_cspread * sin(TAU * c / 3.0), p_sat, lum * 1.25);
  return mix(o, tinted, p_tint) * p_bright;
}

// Where point n sits before rotation, ripple and tilt.
vec2 basePos(float n) {
  float a = TAU * fract(n * GAT);
  return p_spacing * sqrt(n) * vec2(cos(a), sin(a));
}

// Shared per-frame motion.
float g_rot, g_ra, g_rk, g_rw, g_cx, g_cy, g_sx, g_sy;
const float PERSP = 0.64;     // the original's 0.0008 per pixel, in surface heights

vec2 toScreen(vec2 b) {
  float r = length(b);
  float c = cos(g_rot), s = sin(g_rot);
  vec2 f = mat2(c, s, -s, c) * b;
  f *= (r + g_ra * sin(g_rk * r - g_rw)) / max(r, 1e-6);
  float pz = 1.0 + (f.x * g_sx + f.y * g_sy) * PERSP;
  return vec2(f.x * g_cx, f.y * g_cy) * pz;
}

vec3 content(vec2 uv) {
  float k = kick();
  vec2 P = (uv - 0.5) * vec2(u_aspect, 1.0);   // y down, as in the canvas
  float U = p_size / 800.0;                    // one of the original's pixels (800 px high)
  float px = u_px;
  float mn = min(u_aspect, 1.0), mx = max(u_aspect, 1.0);

  g_rot = u_beat * p_spin * TAU / 64.0;
  float tx = p_tilt * sin(TAU * u_beat / 64.0), ty = 0.6 * p_tilt * cos(TAU * u_beat / 48.0);
  g_cx = cos(tx); g_cy = cos(ty); g_sx = sin(tx); g_sy = sin(-ty);
  g_ra = 0.02 * p_ripple * (0.4 + 0.6 * k);
  g_rk = TAU * 4.0; g_rw = TAU * u_beat;       // one ring outward per beat
  float sp = p_spacing;

  // Growth: the head H is the newest point; the newest `count` points are shown.
  float cyc = mod(u_beat, p_cycle) / p_cycle;
  float H = p_grow > 0.5 ? cyc * p_count * 1.3 : p_count;
  float rate = p_count * 1.3 / p_cycle;        // points per beat
  float lo = max(0.0, H - p_count);
  float len = max(H - lo, 1.0);
  float endFade = p_grow > 0.5 ? 1.0 - smoothstep(0.92, 1.0, cyc) : 1.0;

  vec3 col = vec3(p_bg);

  // Centre glow, breathing with the bar and flashing on the kick.
  float pulse = (0.4 + 0.15 * sin(TAU * u_beat / p_breath)) * (1.0 + p_punch * k) * p_centre * endFade;
  float gr = length(P) / (120.0 * U);
  if (gr < 1.0) {
    float ga = gr < 0.3 ? mix(0.35, 0.15, gr / 0.3) : (gr < 0.7 ? mix(0.15, 0.05, (gr - 0.3) / 0.4) : mix(0.05, 0.0, (gr - 0.7) / 0.3));
    col = over(col, gr < 0.5 ? pcol(0.0) : pcol(100.0), ga * pulse);
  }

  // Undo tilt (closed form), rotation and ripple (a few fixed-point steps) to find the
  // pixel's place on the flat spiral.
  float a = P.x / g_cx, b = P.y / g_cy;
  float m = (a * g_sx + b * g_sy) * PERSP;
  float pz = 0.5 * (1.0 + sqrt(max(1.0 + 4.0 * m, 0.0)));
  vec2 f = vec2(a, b) / pz;
  float rf = length(f);
  float th = atan(f.y, f.x) - g_rot;
  float rb = rf;
  for (int i = 0; i < 4; i++) rb = rf - g_ra * sin(g_rk * rb - g_rw);
  rb = max(rb, 0.0);
  float np = (rb / sp) * (rb / sp);

  // The local lattice: the two Fibonacci steps whose neighbours are closest here.
  float nr = floor(np + 0.5);
  float target = 1.6 * sqrt(max(np, 1.0));
  float f1 = 1.0, f2 = 2.0;
  for (int i = 0; i < 20; i++) {
    if (f2 > target) break;
    float t = f1 + f2; f1 = f2; f2 = t;
  }
  // Solve in (index, angle) space, where the lattice is exact: point n + a*f1 + b*f2 is
  // a*d1 + b*d2 turns round from point n (d = the step's golden-angle turns, wrapped).
  float d1 = f1 * GAT - floor(f1 * GAT + 0.5), d2 = f2 * GAT - floor(f2 * GAT + 0.5);
  float dn = np - nr;
  float dphi = th / TAU - fract(nr * GAT);
  dphi -= floor(dphi + 0.5);
  float det = f1 * d2 - f2 * d1;
  float c1 = floor((dn * d2 - f2 * dphi) / det + 0.5);
  float c2 = floor((f1 * dphi - d1 * dn) / det + 0.5);

  // Lattice lines between neighbours (strides 1, 8, 13, 21), faint and only when short.
  if (p_lattice > 0.0) {
    for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
      float n = nr + (c1 + float(i)) * f1 + (c2 + float(j)) * f2;
      if (n < lo || n > H) continue;
      vec2 S = toScreen(basePos(n));
      float fin = p_grow > 0.5 ? min(1.0, (H - n) / (1.4 * rate)) : 1.0;
      for (int s = 0; s < 4; s++) {
        float st = s == 0 ? 1.0 : (s == 1 ? 8.0 : (s == 2 ? 13.0 : 21.0));
        float n2 = n + st;
        if (n2 > H) continue;
        vec2 S2 = toScreen(basePos(n2));
        float L = length(S2 - S) / (80.0 * U);
        if (L > 1.0) continue;
        float base = s == 0 ? 0.06 : (s == 1 ? 0.04 : 0.025);
        float fin2 = p_grow > 0.5 ? min(1.0, (H - n2) / (1.4 * rate)) : 1.0;
        float cov = clamp(0.5 * U / px + 0.5 - segDist(P, S, S2) / px, 0.0, 1.0) * min(0.5 * U / px, 1.0);
        col = over(col, pcol(n), base * (1.0 - L) * fin * fin2 * cov * p_lattice * 2.5 * endFade);
      }
    }
  }

  // Points: glow, dot and a bright centre, sizes breathing along the spiral.
  for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
    float n = nr + (c1 + float(i)) * f1 + (c2 + float(j)) * f2;
    if (n < lo || n > H) continue;
    vec2 S = toScreen(basePos(n));
    float d = length(P - S);
    float age = (H - n) / max(rate, 1e-3);                  // beats since it appeared
    if (p_grow < 0.5) age = 100.0;
    float fin = min(1.0, age / 1.4);
    float fout = clamp((n - lo) / (0.1 * len), 0.0, 1.0);
    float br = 1.0 + 0.12 * sin(TAU * u_beat / p_breath + n * 0.1);
    float size = (1.2 + 2.5 * min(1.0, age / 4.4)) * br * (1.0 + 0.5 * p_punch * k);
    float al = fin * fout * (0.6 + 0.4 * br) * endFade;
    vec3 pc = pcol(n);
    float gR = size * 4.0 * U;
    if (d < gR) col = over(col, pc, al * 0.15 * (1.0 - d / gR) * p_glow * smoothstep(1.5, 2.5, size) * smoothstep(0.2, 0.4, al));
    col = over(col, pc, al * disk(d / px, size * U / px));
    col = over(col, vec3(1.0, 240.0 / 255.0, 220.0 / 255.0), al * 0.5 * smoothstep(0.35, 0.45, al) * disk(d / px, 0.4 * size * U / px));
  }

  // Vignette, as in the original.
  float r0 = 0.2 * mn, r1 = 0.75 * mx;
  col = mix(col, vec3(10.0 / 255.0), p_vignette * clamp((length(P) - r0) / (r1 - r0), 0.0, 1.0));
  return col;
}
