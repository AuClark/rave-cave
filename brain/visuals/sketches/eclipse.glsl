// Eclipse: a solar eclipse, played out. The moon crosses the sun over a cycle of beats:
// a bite, a crescent, Baily's beads through the valleys on the moon's limb, the diamond
// ring, then totality with the corona, chromosphere and pink prominences, and back out.
// Or set the phase by hand, or let it reach totality as each song section ends (so a
// BUILD lands on totality). A smaller moon gives an annular ring of fire; Miss gives a
// partial eclipse. The corona, chromosphere, solar wind, bloom and stars are from "Eclipse
// Glow" in Paul Bakaus's Radiant collection (MIT), with reversed smoothsteps rewritten
// (undefined in GLSL), its hash renamed (it clashed with the renderer's), stars and grain
// sized from u_px, and time in beats. Params are p_* uniforms; ranges and defaults are in eclipse.json.
// Its cycle runs on u_cbeat, so its climax ("climax" in the JSON) can land on the drop.
uniform float p_corona, p_rays, p_size, p_speed, p_diamond, p_punch, p_flare, p_stars,
              p_hue, p_follow, p_bright, p_cycle, p_hold, p_phase, p_section, p_path, p_miss,
              p_moon, p_sun, p_prom;

#define PI 3.14159265359
#define TAU 6.28318530718

float ehash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(mix(ehash(i), ehash(i + vec2(1.0, 0.0)), f.x),
             mix(ehash(i + vec2(0.0, 1.0)), ehash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm3(vec2 p) {
  float v = 0.0, a = 0.5;
  mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
  for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = rot * p * 2.1 + vec2(1.7, 9.2); a *= 0.5; }
  return v;
}
float fbm4(vec2 p) {
  float v = 0.0, a = 0.5;
  mat2 rot = mat2(0.866, 0.5, -0.5, 0.866);
  for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = rot * p * 2.05 + vec2(3.1, 7.4); a *= 0.48; }
  return v;
}
vec3 hueShift(vec3 c, float turns) {
  float a = turns * TAU;
  vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec3 content(vec2 uv0) {
  float S = max(p_size, 0.05);
  vec2 uv = (uv0 - 0.5) * vec2(u_aspect, 1.0) / min(u_aspect, 1.0) / S;
  uv.y = -uv.y;
  vec2 pix = uv0 * vec2(u_aspect, 1.0) / u_px;   // output pixels, for stars and grain
  float t = u_beat * p_speed;
  float k = kick();
  float coronaSize = p_corona * (1.0 + 0.15 * p_punch * k);
  float rayIntensity = p_rays * (1.0 + 0.5 * p_punch * k);

  float r = length(uv);
  float a = atan(uv.y, uv.x);
  vec3 col = vec3(0.005, 0.003, 0.008);

  // Stars: sparse, twinkling, fading near the corona.
  vec2 starGrid = floor(pix / 3.0);
  float starHash = ehash(starGrid * 0.73 + vec2(13.7, 29.3));
  float starBright = step(0.997, starHash) * (sin(t * 1.5 + starHash * 100.0) * 0.4 + 0.6) * ehash(starGrid * 1.31 + vec2(7.1, 3.9));
  col += vec3(0.7, 0.75, 0.9) * starBright * smoothstep(0.15, 0.45, r) * 0.6 * p_stars;

  float discRadius = 0.15;                     // the sun
  float R = discRadius;
  float pxc = u_px / min(u_aspect, 1.0) / S;   // one output pixel here
  float chromoRadius = discRadius + 0.008;
  float rotAngle = a + t * 0.05;

  // ── The moon's path. s runs 0 → 1 over the cycle (or is set by hand, or by the song
  // section); the moon crosses the sun and holds still in totality for Hold of it. ──
  float s = p_phase;
  if (p_cycle > 0.0) s = mod(u_cbeat, p_cycle) / p_cycle;
  if (p_section > 0.5) s = 0.5 * clamp(u_sp, 0.0, 1.0);   // totality as the section ends
  float x = 2.0 * s - 1.0;
  float f = sign(x) * max(abs(x) - p_hold, 0.0) / max(1.0 - p_hold, 1e-3);
  float Rm = R * p_moon;
  float D = R + Rm + 0.03;
  float pa = radians(p_path);
  vec2 dir = vec2(cos(pa), sin(pa));
  vec2 mc = dir * (D * f) + vec2(-dir.y, dir.x) * p_miss * R;   // moon centre
  vec2 dm2 = uv - mc;
  float dm = length(dm2);
  float am = atan(dm2.y, dm2.x);
  // Mountains on the moon's limb: near contact the sun shines through the valleys
  // between them (Baily's beads).
  float Rl = Rm * (1.0 + 0.007 * (vnoise(vec2(am * 18.0, 3.0)) - 0.5) + 0.004 * (vnoise(vec2(am * 55.0, 9.0)) - 0.5));
  float moonMask = 1.0 - smoothstep(Rl - pxc, Rl + pxc, dm);
  float sunMask = 1.0 - smoothstep(R - pxc, R + pxc, r);
  // How thick the last sliver of sun is: <= 0 is totality.
  float gap = R + length(mc) - Rm;
  // A moon smaller than the sun never covers it (annular): no corona, just a ring of fire.
  float covers = smoothstep(0.97, 1.0, p_moon);
  float tot = (1.0 - smoothstep(0.0, 0.25 * R, gap)) * covers;
  float cor = tot * (1.0 + 0.15 * p_punch * k);
  col = vec3(0.005, 0.003, 0.008) + (col - vec3(0.005, 0.003, 0.008)) * tot;   // stars only in totality

  // Corona rays: three noise octaves at different speeds, uneven streamers.
  float ray1 = fbm3(vec2(rotAngle * 3.0, r * 4.0 - t * 0.08));
  float ray2 = fbm3(vec2(rotAngle * 7.0 + 5.0, r * 6.0 - t * 0.12));
  float ray3 = fbm4(vec2(rotAngle * 13.0 + 10.0, r * 8.0 - t * 0.18));
  float rays = ray1 * 0.5 + ray2 * 0.3 + ray3 * 0.2;
  rays *= 0.7 + 0.3 * sin(a * 2.0 + 0.5) * sin(a * 3.0 + t * 0.02) + 0.15 * sin(a * 5.0 + 1.7);

  float coronaOuter = discRadius + 0.35 * coronaSize;
  float inside = smoothstep(discRadius - 0.01, discRadius + 0.03, r);
  float radialFalloff = (1.0 - smoothstep(discRadius + 0.02, coronaOuter, r)) * inside;
  float rayReach = discRadius + 0.6 * coronaSize;
  float rayFalloff = (1.0 - smoothstep(discRadius + 0.03, rayReach, r)) * inside;

  float colorMix = smoothstep(discRadius, coronaOuter, r);
  vec3 innerColor = vec3(1.0, 0.75, 0.30), outerColor = vec3(0.8, 0.35, 0.08);
  vec3 coronaColor = mix(innerColor, outerColor, colorMix);
  col += coronaColor * radialFalloff * (0.4 + rays * 0.6) * 1.2 * rayIntensity * cor;
  col += mix(coronaColor, outerColor, 0.5) * rayFalloff * pow(max(rays, 0.0), 1.5) * 0.8 * rayIntensity * cor;

  // Chromosphere: a thin bright ring, only seen around totality.
  float chromoDist = abs(r - chromoRadius);
  float chromo = exp(-chromoDist * chromoDist / 0.00008) * (0.7 + fbm3(vec2(rotAngle * 10.0, t * 0.2)) * 0.5);
  col += vec3(1.0, 0.85, 0.5) * chromo * 1.2 * rayIntensity * cor;

  // Solar wind: fine radial streaks.
  float wind = smoothstep(0.95, 1.0, ehash(vec2(floor((a + t * 0.02) * 80.0), floor((r - t * 0.06) * 100.0))));
  float windFade = smoothstep(discRadius, discRadius + 0.05, r) * (1.0 - smoothstep(discRadius + 0.06, rayReach + 0.08, r));
  col += vec3(1.0, 0.85, 0.55) * wind * windFade * 0.06 * rayIntensity * cor;

  // Bloom and a soft horizontal lens streak (corona light, so with totality).
  col += vec3(0.4, 0.25, 0.1) * exp(-max(r - discRadius, 0.0) * 2.5) * smoothstep(discRadius - 0.05, discRadius + 0.01, r) * 0.25 * rayIntensity * cor;
  col += vec3(0.3, 0.18, 0.06) * exp(-r * 1.2) * 0.15 * rayIntensity * cor;
  float streak = exp(-uv.y * uv.y * 80.0) * exp(-abs(r - discRadius) * 5.0) * smoothstep(discRadius - 0.02, discRadius + 0.05, r);
  col += vec3(0.6, 0.4, 0.2) * streak * 0.08 * rayIntensity * p_flare * cor;

  // The visible sun: bright, darker toward its limb, with a little glare while it shows.
  float mu = sqrt(max(1.0 - (r / R) * (r / R), 0.0));
  vec3 photo = mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.9, 0.8), mu) * (0.45 + 0.55 * mu) * p_sun;
  float fire = 1.0 - covers;                   // annular: the ring blazes
  photo *= 1.0 + 1.3 * fire;
  float glare = (1.0 - tot) * exp(-max(r - R, 0.0) * 14.0) * (1.0 - sunMask) * 0.25 * p_sun * (1.0 + 2.0 * fire);
  col += vec3(1.0, 0.7, 0.4) * glare;
  col = mix(col, photo, sunMask);

  // Prominences: pink flames at the limb, peeking past the moon in totality.
  float pn = vnoise(vec2(a * 7.0 + 2.0, t * 0.03));
  float pk = max(pn - 0.62, 0.0) / 0.38;      // only the few highest peaks become flames
  float promH = R * (p_moon + 0.05 * pow(pk, 0.8) * p_prom);   // reaching past the moon's edge
  float prom = (1.0 - smoothstep(promH - 1.5 * pxc, promH + 1.5 * pxc, r)) * smoothstep(R * 0.98, R, r) * smoothstep(0.0, 0.15, pk);
  prom *= 0.6 + 0.4 * smoothstep(promH, R * p_moon, r);   // brighter at the base
  col = mix(col, vec3(0.95, 0.12, 0.32) * (1.0 + 0.4 * k * p_punch), clamp(prom * tot * p_prom, 0.0, 1.0) * 0.9);

  // The moon, in front of it all.
  vec3 moonCol = vec3(0.5, 0.4, 0.3) * vnoise(dm2 * 40.0) * 0.008;
  col = mix(col, moonCol, moonMask);

  // Diamond ring: the last (and first) sliver of sun, on the limb away from the moon,
  // blazing just before and after totality; flares on the kick.
  vec2 away = length(mc) > 1e-4 ? -normalize(mc) : -dir;
  vec2 Pd = away * R;
  float dd = length(uv - Pd);
  float ring = smoothstep(-0.004, 0.002, gap) * (1.0 - smoothstep(0.002, 0.03, gap));
  float diamondBoost = p_diamond * (1.0 + p_punch * k) * ring * covers;
  col += vec3(1.0, 0.95, 0.85) * exp(-dd * dd / 0.00025) * 2.0 * diamondBoost;
  col += vec3(1.0, 0.75, 0.4) * exp(-dd * 18.0) * 0.6 * diamondBoost;
  col += vec3(0.9, 0.7, 0.4) * exp(-pow((uv - Pd).y * 60.0, 2.0)) * exp(-abs((uv - Pd).x) * 6.0) * 0.25 * diamondBoost * p_flare;

  col += (ehash(pix + fract(t * 43.0) * 1000.0) - 0.5) * 0.015;
  col *= 0.7 + 0.3 * (1.0 - smoothstep(0.3, 1.1, r));

  col = max(col, vec3(0.0));
  col = hueShift(col, p_hue + p_follow * u_hue);
  col = max(col * p_bright, vec3(0.0));
  col = col / (1.0 + col * 0.3);
  float lum = dot(col, vec3(0.299, 0.587, 0.114));
  col = mix(col, col * vec3(1.06, 0.97, 0.90), (1.0 - smoothstep(0.0, 0.05, lum)) * 0.2);
  return clamp(col, 0.0, 1.0);
}
