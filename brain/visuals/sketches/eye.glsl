// Eye: the all-seeing eye for the capstone. An almond eye with a gold iris that looks
// around, blinks on the last beat of some bars, dilates with energy, opens through a
// BUILD and fully on the DROP. Optional rays and the dollar-bill triangle around it.
// Params are p_* uniforms; ranges and defaults are in eye.json.
uniform float p_size, p_open, p_build, p_drop, p_blink, p_look, p_lspeed, p_iris, p_irings, p_fibres,
              p_pupil, p_dilate, p_sclera, p_rays, p_raylen, p_rspin, p_tri, p_width, p_glow,
              p_hue, p_sat, p_follow, p_beat;

#define TAU 6.2831853
#define PI 3.1415927

// Equilateral triangle, apex up (y up), half side r (after Inigo Quilez).
float sdTri(vec2 p, float r) {
  const float k = 1.7320508;
  p.x = abs(p.x) - r;
  p.y = p.y + r / k;
  if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
  p.x -= clamp(p.x, -2.0 * r, 0.0);
  return -length(p) * sign(p.y);
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) / p_size;     // eye is 1 unit wide
  p.y = -p.y;                                             // y up
  float px = u_px / p_size;
  float w = max(p_width / p_size, px);
  vec3 gold = hsv(p_hue + (p_follow > 0.5 ? u_hue : 0.0), p_sat, 1.0);

  // How open: base, rising through a BUILD / PREDROP, fully on the DROP, blinking.
  float o = p_open;
  if (abs(u_scene - 4.0) < 0.5 || abs(u_scene - 6.0) < 0.5) o = mix(o, 1.0, p_build * u_sp);
  if (abs(u_scene - 7.0) < 0.5) o = mix(o, 1.0, p_drop * smoothstep(0.0, 1.0, u_since));
  float bb = mod(t, 4.0);
  if (hash(vec2(floor(t / 4.0), 3.7)) < p_blink && bb > 3.0) o *= 1.0 - sin(PI * clamp((bb - 3.0) / 0.5, 0.0, 1.0));

  // Almond: half height 0.3 * o * (1 - x^2) across a half width of 0.5.
  float W = 0.5, xn = p.x / W;
  float hh = o * 0.3 * max(0.0, 1.0 - xn * xn);
  float sl = o * 0.3 * 2.0 * p.x / (W * W);
  float dl = abs(p.x) > W ? length(vec2(abs(p.x) - W, p.y)) : (abs(p.y) - hh) / sqrt(1.0 + sl * sl);
  float inside = 1.0 - smoothstep(-px, px, dl);
  float outline = 1.0 - smoothstep(w - px, w + px, abs(dl));

  // Iris and pupil, looking around slowly.
  vec2 g = p_look * vec2(0.26 * sin(t * TAU * p_lspeed / 8.0 + 1.3 * sin(t * 0.11)),
                         0.07 * sin(t * TAU * p_lspeed / 5.0 + 0.7));
  vec2 q = p - g;
  float r = length(q), a = atan(q.y, q.x);
  float ri = p_iris * 0.3;
  float rp = ri * clamp(p_pupil * (1.0 + p_dilate * (u_energy - 0.5)) * (1.0 + 0.25 * k), 0.05, 0.95);
  float rr = clamp((r - rp) / max(ri - rp, 1e-3), 0.0, 1.0);
  float rings = 0.5 + 0.5 * cos(rr * p_irings * TAU - t * TAU * 0.25);
  float fib = 0.5 + 0.5 * cos(a * floor(p_fibres + 0.5) + 3.0 * sin(rr * 6.0 + t * 0.5));
  float pat = p_irings > 0.5 ? rings : 1.0;
  pat *= p_fibres > 0.5 ? 0.45 + 0.55 * fib : 1.0;
  vec3 irisCol = gold * (0.3 + 0.7 * pat) * (1.0 - 0.75 * smoothstep(0.75, 1.0, rr));
  float irisM = 1.0 - smoothstep(ri - px, ri + px, r);
  float pupilM = 1.0 - smoothstep(rp - px, rp + px, r);
  float hl = 1.0 - smoothstep(0.16 * ri - px, 0.16 * ri + px, length(q - vec2(-0.32, 0.34) * ri));

  vec3 sclera = vec3(0.95, 0.92, 0.85) * p_sclera * (0.55 + 0.45 * smoothstep(0.0, 0.12, -dl));
  vec3 eye = mix(sclera, irisCol, irisM);
  eye = mix(eye, vec3(0.0), pupilM);
  eye += vec3(0.9) * hl * irisM;

  // Outside: rays, a halo round the lid, and the triangle.
  float R = length(p), A = atan(p.y, p.x);
  vec3 col = vec3(0.0);
  if (p_rays > 0.5) {
    float ray = pow(0.5 + 0.5 * cos(A * floor(p_rays + 0.5) + t * p_rspin * TAU / 16.0), 8.0);
    col += gold * ray * exp(-max(R - 0.3, 0.0) / max(p_raylen, 0.01)) * (0.5 + 0.9 * k) * (0.3 + 0.7 * o);
  }
  col += gold * p_glow * 0.5 * exp(-max(dl, 0.0) * 14.0) * (1.0 - inside);
  if (p_tri > 0.5) {
    float dt = sdTri(p - vec2(0.0, -0.1), 0.82);
    col = mix(col, gold * 0.12, (1.0 - smoothstep(-px, px, dt)) * 0.5);
    col += gold * (1.0 - smoothstep(w - px, w + px, abs(dt))) * 1.2;
  }
  col = mix(col, eye, inside) + gold * outline;
  return col * (0.85 + 0.15 * k);
}
