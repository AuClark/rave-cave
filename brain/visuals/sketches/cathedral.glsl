// Cathedral: a gothic nave you fly down and never reach the end of. The building is built,
// not found: a polished floor, an arcade of pointed arches opening onto dark side aisles,
// clustered piers every bay rising into transverse and diagonal ribs that meet at the crown
// of a pointed vault. Above the arcade each bay is one great traceried window, and the
// tracery is the fractal: an arch holding two smaller arches and an oculus, each of which
// holds the same again -- which is how gothic windows really are drawn, arches inside
// arches inside arches, mirrored about every mullion like a kaleidoscope.
//
// Light is the subject. A rose window burns at the far end and throws beams back down the
// nave; the sun comes in through the windows on the left, so shafts of coloured light slant
// across the air and pool on the floor and the far piers; the haze glows with the window's
// colour, so distance brightens instead of going murky, and the stone stands dark against
// it -- which is also what a projector wants: bright lights, deep darks, few mid-greys.
//
// Drivers (docs/reactive.md): A Hit -> the rose window flares, the shafts brighten and a wave
// of light runs up the nave towards you; B Move -> the glass glitters cell by cell and the
// camera sways; C Change -> the glass palette turns and the tracery re-forms. The kick also
// lurches the camera forward on every beat (Surge), so the travel itself has a pulse.
//
// Cost: the scene is a handful of analytic shapes, so a march step is a few lines of
// arithmetic and the normal is three more map() calls. The tracery and the glass are worked
// out once per pixel, only on the pixels that land on a window, and anti-aliased there.
// Params are p_* uniforms; ranges and defaults are in cathedral.json.
uniform float p_sides, p_detail, p_scale, p_form, p_fold, p_bore, p_height,
              p_bay, p_surge, p_twist, p_spin, p_sway, p_kal,
              p_steps, p_far, p_fog, p_glow, p_rose, p_shade,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_spread, p_sat, p_follow;

#define TAU 6.2831853
#define CELL 2.0                 // one bay, in world units; piers at z = 0 mod CELL
#define Y0 -1.0                  // the floor; the camera flies a little over a unit above it
#define WU 0.7                   // half-width of a clerestory window
#define RECESS 0.12              // how deep the glass sits behind the face of the wall

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

// Set once per pixel, so map() does no setup of its own.
float gZ, gW, gYs, gYA, gWB, gTwist, gHue, gB, gC, gIter, gTs, gTc, gTy0, gOcR, gFoil;
vec3 gL;
float gPart;                     // what the last point was nearest: 0 wall, 1 pier or rib
float gCell;                     // which pane of the tracery the last tracery() call landed in

// How far the nave has wandered sideways at depth z, measured from where the camera is. Side
// to side only, so the floor stays a flat plane and can still be hit exactly. Eight bays to
// a swing; the wrap of the travel (32 bays) holds a whole number of them, so it never jumps.
float wind(float z) {
  float k = TAU / (8.0 * CELL);
  return gTwist * (sin((z + gZ) * k) - sin(gZ * k));
}

// A pointed (equilateral) arch as a 2D distance, negative inside: half-width ww, straight
// sides up to the springing line ys, then two arcs each centred on the opposite side.
float archSD(float x, float y, float ww, float ys) {
  float sd = abs(x) - ww;
  return y < ys ? sd : length(vec2(abs(x) + ww, y - ys)) - 2.0 * ww;
}

// Distance to the plain nave: positive in the open, negative inside the wall.
float naveWall(float x, float y) {
  if (y < gYs) return gW - x;
  return 2.0 * gW - length(vec2(x + gW, y - gYs));
}

// The clerestory window of a bay, as (zw, y) on the wall; negative inside the opening.
float clere(float zw, float y) { return max(archSD(zw, y - gWB, WU, 1.3 * WU), gWB - y); }

float map(vec3 p) {
  p.x -= wind(p.z);                             // the Wind slider (id twist)
  float x = abs(p.x), y = p.y;
  float z = p.z + gZ;
  float zl = mod(z + CELL * 0.5, CELL) - CELL * 0.5;   // 0 at a pier
  float zw = mod(z, CELL) - CELL * 0.5;                // 0 half way between piers
  float g = naveWall(x, y);
  // Open space: the nave, the arcade cut through its wall in every bay, and the low aisle
  // behind the arcade. A union of spaces is a max of their distances.
  float xo = gW + 1.5;
  float sp = max(g, min(-archSD(zw, y, 0.56, gYA - 0.97), xo - x));
  sp = max(sp, min(min(x - gW - 0.3, xo - x), gYA + 0.25 - y));
  // The clerestory glass, set back into the wall.
  sp = max(sp, min(-clere(zw, y), g + RECESS));

  // Piers rising into transverse ribs: one rounded bar up the wall and over the arch, so the
  // pier and its rib meet without a seam. Fluted, so they catch the light.
  float rr = 0.12 + 0.03 * gW;
  float fl = abs(zl) < 0.4 ? 0.012 * cos(atan(zl, x - gW) * 10.0) : 0.0;
  float rib = (y < gYs ? length(vec2(x - (gW - 0.07), zl))
                       : length(vec2(length(vec2(x + gW, y - gYs)) - (2.0 * gW - 0.07), zl))) - rr - fl;
  // Diagonal ribs from the top of each pier to the crown in the middle of the bay, and a
  // ridge rib running along the crown.
  if (y > gYs) {
    float dg = (x / gW + abs(zl) - 1.0) * gW / sqrt(1.0 + gW * gW);
    rib = min(rib, max(min(abs(dg) - 0.05, x - 0.05), abs(g) - 0.07));
  }
  gPart = sp < rib ? 0.0 : 1.0;                 // (the floor is intersected exactly, not marched)
  return min(rib, sp);
}

// Stained glass: one colour per pane, from the show hue out across Spread.
vec3 glass(float id) {
  float h = hash(vec2(id, 3.7));
  float hu = gHue + p_spread * (h - 0.5) * 0.9 + (h > 0.8 ? 0.5 * p_spread : 0.0) + 0.14 * gC;
  float v = 0.6 + 0.4 * hash(vec2(id, 9.1));
  v *= 1.0 + gB * 1.8 * (hash(vec2(id, floor(u_beat * 2.0))) - 0.35);   // hats: the glass glitters
  return hsv(fract(hu), p_sat, max(v, 0.2));
}

// Gothic tracery, q in window units (half-width 1, springing at 1.3). An arch holds an
// oculus in its head and two smaller arches below, and each of those holds the same again:
// mirror, shift, scale, repeat -- a kaleidoscopic fold. Returns the distance to the stone
// (negative on a bar) in window units, and leaves the pane it landed in in gCell.
float tracery(vec2 q, float bw) {
  float d = 1e3, k = 1.0, id = 1.0;
  for (int i = 0; i < 5; i++) {
    if (float(i) >= gIter) break;
    float da = archSD(q.x, q.y, 1.0, 1.3);
    d = min(d, (abs(da) - bw) * k);
    if (da > 0.0 && i > 0) break;                // in the spandrel between two arches
    // The oculus, cusped into foils as Fold rises.
    vec2 oc = q - vec2(0.0, 2.25);
    float an = atan(oc.x, oc.y);
    float nf = 3.0 + floor(gFoil * 3.0);
    float doc = length(oc) - gOcR * (1.0 - 0.22 * gFoil * (0.5 + 0.5 * cos(an * nf)));
    d = min(d, (abs(doc) - bw) * k);
    if (doc < 0.0) { id = id * 4.0 + 3.0 + floor(mod(an / TAU * nf + 0.5, nf)) * 0.25; break; }
    float sx = step(0.0, q.x);
    q = vec2(abs(q.x) - gTc, q.y - gTy0) * gTs;
    k /= gTs;
    id = id * 4.0 + sx;
  }
  gCell = id;
  return d;
}

// Sunlight: trace p back along the light to the left wall and see whether it came in
// through a window. Returns the light's colour, black where the wall blocked it.
vec3 sun(vec3 p) {
  p.x -= wind(p.z);
  float s = (p.x + gW) / gL.x;
  vec3 e = p - gL * s;
  float z = e.z + gZ;
  float bayi = floor(z / CELL);
  float zw = z - bayi * CELL - CELL * 0.5;
  float m = (1.0 - smoothstep(-0.25, 0.05, clere(zw, e.y))) * step(0.0, s);
  float hu = gHue + p_spread * (fract(bayi * 0.618) - 0.5) * 0.9 + 0.14 * gC;
  return m * mix(vec3(1.0, 0.92, 0.8), hsv(fract(hu), p_sat, 1.0), 0.75);
}

// The rose window, e in window radii: an oculus, `n` petals and a ring of foils, leaded.
vec3 rose(vec2 e, float n, float aa) {
  float r = length(e);
  float a = atan(e.y, e.x) + 0.08 * gC;
  float seg = TAU / n;
  float ai = floor(a / seg + 0.5);
  float af = a - ai * seg;
  vec2 pc = r * vec2(cos(af), sin(af));
  float spoke = r * abs(sin(seg * 0.5 - abs(af)));
  float lead = min(abs(r - 0.24), abs(r - 0.66));
  float id;
  if (r < 0.24) {                               // the oculus
    lead = min(lead, abs(r - 0.11));
    id = r < 0.11 ? 1.0 : 2.0;
  } else if (r < 0.66) {                        // the petals
    float dp = length(pc - vec2(0.45, 0.0)) - 0.16;
    lead = min(lead, min(abs(dp), spoke));
    id = dp < 0.0 ? 10.0 + mod(ai, 2.0) : 20.0 + mod(ai, 3.0);
  } else {                                      // the ring of foils, two to a petal
    float af2 = abs(af) - seg * 0.25;
    float df = length(vec2(r * cos(af2) - 0.82, r * sin(af2))) - 0.095;
    lead = min(lead, min(abs(df), spoke));
    id = df < 0.0 ? 40.0 + step(0.0, af) : 50.0;
  }
  float m = smoothstep(0.015, 0.03 + aa, lead) * (1.0 - smoothstep(0.93, 0.96, r));
  return glass(id) * m;
}

vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> light flare
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> glass glitter, sway
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> palette, tracery
  gB = B; gC = C;

  gW = p_bore;
  gYs = Y0 + 2.7 * p_height;                    // the springing line of the vault
  gYA = Y0 + 0.62 * (gYs - Y0);                 // the crown of the arcade
  gWB = gYA + 0.2;                              // the sill of the clerestory
  gTwist = 4.0 * p_twist;
  // Tracery: Scale is how much smaller each generation of arches is (2 = they touch), Form
  // the oculus in each head (C swells it, so the windows re-form on the chords), Fold how
  // far the oculus is cusped into foils.
  gIter = floor(p_detail + 0.5);
  gTs = mix(2.0, 2.6, clamp((p_scale - 1.3) / 1.1, 0.0, 1.0));
  gTc = 1.0 - 1.0 / gTs;
  gTy0 = 0.7 - 1.3 / gTs;
  gOcR = clamp(0.36 + 0.14 * p_form * (1.0 + 0.3 * C), 0.3, 0.62);
  gFoil = clamp(p_fold, 0.0, 1.0);
  gL = normalize(vec3(0.62, -0.62, -0.34));     // the sun, in through the left-hand windows

  // Travel: bays per beat, and on every beat an extra lurch delivered in the first moments
  // after the kick. Continuous and always forwards, so it never snaps back.
  float fb = floor(u_beat), fr = u_beat - fb;
  float sg = 0.9 * p_surge;
  float trav = fb * (1.0 + sg) + fr + sg * (1.0 - exp(-7.0 * fr)) / (1.0 - exp(-7.0));
  gZ = mod(trav / max(p_bay, 0.05), 32.0) * CELL;     // wrapped: still exact at hour four

  gHue = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  vec3 endCol = mix(vec3(1.0, 0.93, 0.82), hsv(fract(gHue), p_sat, 1.0), 0.45);

  // Camera: near the axis, looking a little up the vault.
  vec2 sp = (uv - 0.5) * vec2(u_aspect, 1.0);
  sp.y = -sp.y;
  sp = rot(u_beat * p_spin * TAU + 0.02 * B * sin(u_beat * 1.3)) * sp;
  // Kaleidoscope: fold the screen angle into mirrored wedges about the centre. Narrow wedges
  // are turned to look at the windows up the side of the vault, where the colour is. A mirror fold is seamless
  // (neighbouring wedges meet in reflection, never in a jump), and Roll, applied before it,
  // turns the building inside the wedges the way turning a kaleidoscope does.
  float nk = floor(p_kal + 0.5);
  if (nk > 0.5) {
    float seg = TAU / nk;
    float ka = atan(sp.x, sp.y);
    ka = abs(mod(ka + 0.5 * seg, seg) - 0.5 * seg);
    ka += max(0.0, 0.8 - 0.25 * seg);   // centre narrow wedges on the clerestory glass, not bare vault
    sp = length(sp) * vec2(sin(ka), cos(ka));
  }
  vec3 rd = normalize(vec3(sp * (1.0 - 0.12 * A), 1.0));
  float sw = p_sway * gW * 0.45;
  vec3 ro = vec3(sw * sin(u_beat * TAU / 16.0), 0.15 + 0.4 * sw * cos(u_beat * TAU / 24.0), 0.0);
  // Look up towards the rose window, most of the way: a taller nave tips the head back.
  rd.yz = rot(-min(0.65 * atan((gYs + 0.4 * gW - ro.y) / p_far), 0.42)) * rd.yz;

  float FAR = p_far;
  float steps = max(12.0, floor(p_steps + 0.5));
  float stepScale = 0.95 - 0.2 * clamp(gTwist, 0.0, 1.0);
  // The floor is a plane, so it is hit exactly rather than marched: rays skimming a floor
  // are the slowest thing a marcher does, and this way they cost nothing.
  float tF = rd.y < -1e-4 ? (Y0 - ro.y) / rd.y : 1e5;
  float tMax = min(FAR, tF);
  float t = 0.05, si = 0.0, d = 1.0;
  bool hit = false;
  for (int i = 0; i < 96; i++) {
    if (float(i) >= steps) break;
    d = map(ro + rd * t);
    if (d < max(0.001, t * u_px * 1.2)) { hit = true; break; }
    t += d * stepScale;
    si += 1.0;
    if (t > tMax) break;
  }
  float part = gPart;
  if (!hit) {
    if (t >= tMax && tF <= FAR) { hit = true; t = tF; part = 2.0; }   // the floor
    else if (t < tMax) hit = true;                                    // out of steps: call it stone
  }
  t = min(t, FAR);

  // The haze glows towards the rose window, so distance brightens rather than dirties.
  vec2 rp = rd.xy / max(rd.z, 0.05) - vec2(wind(FAR) - ro.x, gYs + 0.4 * gW - ro.y) / FAR;
  float dr = length(rp);
  float ra = atan(rp.y, rp.x);
  float flare = 1.0 + 1.6 * A;
  vec3 haze = endCol * (0.03 + (0.5 * exp(-dr * 8.0) + 0.12 * exp(-dr * 2.5)) * (0.6 + 0.4 * flare) * p_rose);

  // Sunbeams: the light in the air along the ray, from a few cheap lookups.
  vec3 shaft = vec3(0.0);
  for (int k = 0; k < 10; k++) {
    float tk = t * (float(k) + 0.5) / 10.0;
    shaft += sun(ro + rd * tk) * exp(-tk * p_fog * 0.8);
  }
  shaft *= t / 10.0;

  vec3 col;
  if (hit) {
    vec3 pos = ro + rd * t;
    float e = max(0.0015, t * u_px * 1.5);
    vec3 n = part > 1.5 ? vec3(0.0, 1.0, 0.0)
           : normalize(vec3(map(pos + vec3(e, 0, 0)), map(pos + vec3(0, e, 0)), map(pos + vec3(0, 0, e))) - d);
    vec3 wp = pos;
    wp.x -= wind(wp.z);
    float ax = abs(wp.x);
    float z = wp.z + gZ;
    float bayi = floor(z / CELL);
    float bayk = mod(bayi, 32.0);
    float zw = z - bayi * CELL - CELL * 0.5;

    // Pale limestone, laid in courses: the joints are what make it read as stone.
    vec3 stone = part > 1.5 ? vec3(0.50, 0.47, 0.44) : (part > 0.5 ? vec3(0.80, 0.76, 0.70) : vec3(0.68, 0.64, 0.58));
    if (part < 0.5) {
      float cy = wp.y * 3.2;
      float cz = z * 1.6 + 0.5 * mod(floor(cy), 2.0);
      vec2 jq = abs(fract(vec2(cz, cy)) - 0.5);
      float jw = 0.5 - clamp(t * u_px * 3.0, 0.03, 0.5);
      stone *= 1.0 - 0.4 * smoothstep(jw - 0.02, jw + 0.01, max(jq.x, jq.y)) * (1.0 - clamp(t * 0.1, 0.0, 1.0));
      stone *= 0.9 + 0.2 * hash(floor(vec2(cz, cy)) + bayk);
    }
    float ao = clamp(1.25 - 1.1 * si / steps, 0.15, 1.0);

    vec3 lo = normalize(vec3(-pos.x * 0.1, 0.25, 1.0));   // towards the far end
    float dif = max(dot(n, lo), 0.0);
    float sky = 0.5 + 0.5 * n.y;
    vec3 sunc = sun(pos) * max(dot(n, -gL), 0.0);
    float rim = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);
    vec3 stoneL = mix(vec3(1.0, 0.93, 0.82), endCol, 0.15);

    col = stone * stoneL * ((0.05 + 0.6 * dif * p_shade) * p_rose + 0.07 * sky) * ao;
    col += stone * sunc * 2.2 * p_glow * (0.6 + 0.4 * ao);
    col += stoneL * rim * (part > 1.5 ? 0.08 : 0.35) * ao * p_rose;
    if (part > 1.5) {
      // A floor of dark and pale marble in a diamond pattern, with the nave reflected in it
      // as a narrow streak. Real value contrast, so it reads as floor from any roll angle
      // instead of a pale flat plane; the pattern fades before it is fine enough to fizz.
      vec2 fq = vec2(z + wp.x, z - wp.x) * 0.9;
      vec2 ff = abs(fract(fq) - 0.5);
      float fade = clamp(t * u_px * 18.0, 0.0, 1.0);
      float chk = mod(floor(fq.x) + floor(fq.y), 2.0);
      float grout = smoothstep(0.44, 0.49, max(ff.x, ff.y));
      col *= mix(mix(0.45, 1.05, chk) * (1.0 - 0.6 * grout), 0.75, fade);
      float sp2 = pow(max(dot(reflect(rd, n), lo), 0.0), 40.0);
      col += endCol * sp2 * 0.55 * p_rose * (0.6 + 0.4 * flare) * mix(0.6 + 0.4 * chk, 0.8, fade);
    }
    if (part < 0.5) {
      float aisle = step(gW + 0.2, ax);
      col *= 1.0 - 0.6 * aisle;                           // the aisles sit in shadow
      float aa = t * u_px * 2.0;
      vec3 gc = vec3(0.0);
      float m = 0.0;
      if (aisle < 0.5 && naveWall(ax, wp.y) < 0.03 - RECESS && clere(zw, wp.y) < 0.0) {
        // A clerestory window: tracery bars in stone, glass in the panes between.
        float tb = tracery(vec2(zw, wp.y - gWB) / WU, 0.06) * WU;
        m = smoothstep(-aa, aa, tb);
        // Inside each pane, small quarries of hand-made glass, each a slightly different shade.
        vec2 qd = vec2(zw * 9.0, wp.y * 7.0);
        vec2 qf = abs(fract(qd) - 0.5);
        m *= 0.35 + 0.65 * smoothstep(0.02, 0.06 + aa * 8.0, min(qf.x, qf.y));
        float lit = wp.x < 0.0 ? 1.0 : 0.55;                // the sun side burns brighter
        gc = glass(gCell + bayk * 7.0 + (wp.x < 0.0 ? 0.0 : 3.0)) * (0.45 + 1.1 * lit);
        gc *= 0.75 + 0.5 * hash(floor(qd) + gCell);
      } else if (aisle > 0.5 && ax > gW + 1.45) {
        // An aisle window, seen through the arcade: a plain lancet in diamond quarries.
        m = 1.0 - smoothstep(-aa, aa, archSD(zw, wp.y - Y0 - 0.45, 0.34, gYA - Y0 - 1.3));
        vec2 qd = vec2(zw + wp.y * 0.55, zw - wp.y * 0.55) * 6.0;
        vec2 qf = abs(fract(qd) - 0.5);
        m *= smoothstep(0.03, 0.09 + aa, min(qf.x, qf.y));
        gc = glass(floor(qd.x) * 7.0 + floor(qd.y) * 3.0 + bayk * 11.0 + 50.0) * (wp.x < 0.0 ? 0.9 : 0.5);
      }
      col = mix(col, gc * flare, m);
    }
    // The kick's wave of light, travelling up the nave towards the camera.
    float aph = fract(barBeat() / loopBeats(p_aloop));
    float wz = FAR * (1.0 - aph);
    col += endCol * A * 0.5 * exp(-3.0 * (t - wz) * (t - wz)) * ao;
    col = mix(haze, col, exp(-t * p_fog));
  } else {
    // The end of the nave: the rose window in the west wall, the wall itself lost in light.
    vec3 ep = ro + rd * FAR;
    vec2 e = (ep.xy - vec2(wind(ep.z), gYs + 0.4 * gW)) / (0.6 * gW);
    vec3 rw = rose(e, max(4.0, floor(p_sides + 0.5)), FAR * u_px * 1.5 / (0.6 * gW));
    float inR = 1.0 - smoothstep(0.93, 0.98, length(e));
    col = haze * (1.0 - 0.75 * inR) + rw * (1.6 * p_rose) * flare * max(exp(-FAR * p_fog * 0.3), 0.55);
  }
  // Beams from the rose window, only in the air a ray actually crossed.
  float beams = pow(0.5 + 0.5 * sin(ra * 7.0 + 0.4 * sin(ra * 3.0 + u_beat * 0.06)), 3.0) *
                (0.5 + 0.5 * sin(ra * 13.0 - u_beat * 0.03));
  col += endCol * beams * exp(-dr * 2.5) * (t / FAR) * 0.35 * p_glow * flare * p_rose;
  col += shaft * 0.17 * p_glow * (1.0 + 1.2 * A);
  return 1.0 - exp(-col * 1.35);
}
