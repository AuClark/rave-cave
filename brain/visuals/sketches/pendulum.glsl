// Pendulum: a pendulum wave (after "Pendulum Wave" in Paul Bakaus's Radiant collection,
// MIT). Pendulum i swings (base + i) times per cycle, so they drift from a line through
// snakes and braids and fall back into line at the end of every cycle. The cycle is in
// beats, so the line comes back on the phrase (128 beats = 32 bars, about the original's
// 60 s at 126 BPM). Everything is closed-form: each trail lies on its bob's arc, and a pixel
// on the arc finds when the bob last passed it by solving A cos(wt) = its angle. The
// original's click ripple is a ripple from the centre on every beat.
// Its cycle runs on u_cbeat, so its climax ("climax" in the JSON) can land on the drop.
// Params are p_* uniforms; ranges and defaults are in pendulum.json.
uniform float p_count, p_cycle, p_base, p_amp, p_trail, p_size, p_punch, p_wave, p_curve,
              p_frame, p_tint, p_hue, p_spread, p_sat, p_bright, p_bg, p_follow;

#define PI 3.1415927
#define TAU 6.2831853
#define MAXN 40

// The original's colours: amber (left) through gold to coral (right), or a tint.
vec3 pcol(float t) {
  vec3 amber = vec3(200.0, 149.0, 108.0) / 255.0;
  vec3 gold  = vec3(212.0, 165.0, 116.0) / 255.0;
  vec3 coral = vec3(224.0, 120.0, 80.0) / 255.0;
  vec3 c = t < 0.5 ? mix(amber, gold, t * 2.0) : mix(gold, coral, (t - 0.5) * 2.0);
  float lum = dot(c, vec3(0.299, 0.587, 0.114));
  vec3 tinted = hsv(mix(p_hue, u_hue, p_follow) + (t - 0.5) * p_spread, p_sat, lum * 1.25);
  return mix(c, tinted, p_tint) * p_bright;
}

vec3 over(vec3 c, vec3 s, float a) { return mix(c, s, clamp(a, 0.0, 1.0)); }
float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / max(dot(ba, ba), 1e-9), 0.0, 1.0));
}
float lineCov(float dpx, float w) {           // a line w px wide, box-filtered to the pixel
  float wc = max(w, 1.0);
  return clamp(0.5 * wc + 0.5 - dpx, 0.0, 1.0) * (w / wc);
}
float disk(float dpx, float rpx) { return clamp(rpx - dpx + 0.5, 0.0, 1.0); }

vec3 content(vec2 uv) {
  vec2 P = uv * vec2(u_aspect, 1.0);           // y down, surface height 1
  float W = u_aspect;
  float U = p_size / 800.0;                    // one of the original's pixels (800 px high)
  float px = u_px;
  float margin = 0.1 * W, usable = W - 2.0 * margin;
  float pivotY = 0.08, maxD = 0.72, minD = 0.38;
  float N = p_count;
  float A = p_amp * PI / 180.0;
  float k = kick();
  vec3 amber = pcol(0.0), gold = pcol(0.5);

  vec3 col = vec3(p_bg);

  // Frame: faint reference lines at the rest positions and the pivot bar.
  for (int r = 0; r < 3; r++) {
    float ry = pivotY + minD + (maxD - minD) * float(r) * 0.5;
    float on = step(margin * 0.5, P.x) * step(P.x, W - margin * 0.5);
    col = over(col, amber, 0.04 * p_frame * on * lineCov(abs(P.y - ry) / px, U / px));
  }
  float onBar = step(margin - 20.0 * U, P.x) * step(P.x, W - margin + 20.0 * U);
  col = over(col, amber, 0.15 * p_frame * onBar * lineCov(abs(P.y - pivotY) / px, U / px));

  // Time within the cycle: every pendulum makes a whole number of swings per cycle, so
  // this keeps the phases exact however long the show runs.
  float tc = mod(u_cbeat, p_cycle) / p_cycle;
  float T0 = 1.0 / p_base, Tn = 1.0 / (p_base + N - 1.0);
  float Lmax = T0 * T0, Lmin = Tn * Tn;        // physical length goes with period squared

  // Pass 1: trails, and the curve joining the bobs.
  float conG = 0.0, conC = 0.0;
  vec2 prev = vec2(0.0);
  for (int i = 0; i < MAXN; i++) {
    float fi = float(i);
    if (fi >= N) break;
    float osc = p_base + fi;
    vec2 piv = vec2(margin + usable * fi / max(N - 1.0, 1.0), pivotY);
    float T = 1.0 / osc;
    float Ld = minD + (maxD - minD) * (T * T - Lmin) / max(Lmax - Lmin, 1e-9);
    float th = TAU * osc * tc;                  // phase now
    float dist = length(vec2(piv.x - 0.5 * W, pivotY + Ld - 0.5));
    float ripple = p_wave * 0.15 * sin(dist * 16.0 - u_frac * 8.0) * exp(-dist * 2.4) * exp(-4.0 * u_frac);
    float a = A * cos(th) + ripple;
    vec2 bob = piv + Ld * vec2(sin(a), cos(a));
    vec3 ci = pcol(fi / max(N - 1.0, 1.0));

    // Trail: on the arc, the most recent time the bob passed this angle.
    vec2 d = P - piv;
    float dr = abs(length(d) - Ld) / px;
    if (dr < 3.0 * p_size + 2.0) {
      float phi = atan(d.x, d.y);
      if (abs(phi) < A) {
        float c = acos(clamp(phi / A, -1.0, 1.0));
        float t1 = th - mod(th - c, TAU);
        float t2 = th - mod(th - (TAU - c), TAU);
        float age = (th - max(t1, t2)) / (TAU * osc / p_cycle);   // in beats
        if (age < p_trail) {
          float f = 1.0 - age / p_trail;
          col = over(col, ci, f * f * 0.25 * lineCov(dr, 2.0 * U / px));
        }
      }
    }
    if (i > 0) {
      float dc = segDist(P, prev, bob) / px;
      conG = max(conG, lineCov(dc, 6.0 * U / px));
      conC = max(conC, lineCov(dc, U / px));
    }
    prev = bob;
  }
  col = over(col, gold, 0.08 * p_curve * conG);
  col = over(col, gold, 0.15 * p_curve * conC);

  // Pass 2: strings, pivots and the glowing bobs, which brighten on the kick.
  float punch = 1.0 + p_punch * k;
  for (int i = 0; i < MAXN; i++) {
    float fi = float(i);
    if (fi >= N) break;
    float osc = p_base + fi;
    vec2 piv = vec2(margin + usable * fi / max(N - 1.0, 1.0), pivotY);
    float T = 1.0 / osc;
    float Ld = minD + (maxD - minD) * (T * T - Lmin) / max(Lmax - Lmin, 1e-9);
    float th = TAU * osc * tc;
    float dist = length(vec2(piv.x - 0.5 * W, pivotY + Ld - 0.5));
    float ripple = p_wave * 0.15 * sin(dist * 16.0 - u_frac * 8.0) * exp(-dist * 2.4) * exp(-4.0 * u_frac);
    float a = A * cos(th) + ripple;
    vec2 bob = piv + Ld * vec2(sin(a), cos(a));
    if (abs(P.x - piv.x) > Ld * sin(A + 0.2) + 20.0 * U) continue;   // nothing of this one here
    vec3 ci = pcol(fi / max(N - 1.0, 1.0));
    vec3 hot = min(ci + vec3(40.0, 40.0, 30.0) / 255.0, 1.0);
    vec3 core = min(ci + vec3(60.0, 60.0, 50.0) / 255.0, 1.0);

    col = over(col, ci, 0.2 * lineCov(segDist(P, piv, bob) / px, U / px));
    col = over(col, ci, 0.3 * disk(length(P - piv) / px, 2.0 * U / px));

    float db = length(P - bob);
    float g = db / (18.0 * U);
    if (g < 1.0) {
      float ga = g < 0.3 ? mix(0.3, 0.1, g / 0.3) : mix(0.1, 0.0, (g - 0.3) / 0.7);
      col = over(col, ci, ga * punch);
      float m = db / (8.0 * U);
      if (m < 1.0) col = over(col, hot, 0.6 * (1.0 - m) * punch);
      col = over(col, core, 0.9 * disk(db / px, 3.0 * U / px));
    }
  }
  return col;
}
