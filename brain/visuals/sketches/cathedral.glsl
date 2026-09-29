// Cathedral: a kaleidoscopic fractal you fly through and never reach the end of. Space is
// mirrored into a few wedges around the axis of travel and then folded back into itself,
// which builds arches inside arches inside arches: the detail keeps going however far in
// you look, because it is the same fold at every scale. A cylinder is cut down the middle
// so there is always a nave to fly along and the camera never ends up inside the stone.
//
// Raymarched, so the depth is real: near stonework hides what is behind it, the light falls
// off, and the far end goes to fog. The colour comes from an orbit trap -- how close the
// fold carried each point to each axis -- so the palette is a property of the geometry
// rather than a gradient laid over the top, and neighbouring stone is a different hue.
//
// Drivers (docs/reactive.md): A Hit -> a ring of light released down the nave and the walls
// breathing out; B Move -> the fold angle, which reshapes the whole building; C Change ->
// the fold's offset and the palette, so the cathedral becomes a different cathedral.
//
// This is the only sketch that marches, so it costs several times what a flat one does.
// Detail is the knob that buys the frame rate back: Steps turns out to be nearly free either
// way, because most rays stop on a hit or run out of Depth long before they reach the cap.
// Measured numbers and what to turn down first are in docs/visuals.md.
// Params are p_* uniforms; ranges and defaults are in cathedral.json.
uniform float p_sides, p_detail, p_scale, p_form, p_fold, p_bore,
              p_bay, p_twist, p_spin, p_sway,
              p_steps, p_far, p_fog, p_glow, p_shade,
              p_aband, p_aloop, p_ashape, p_aamt,
              p_bband, p_bloop, p_bshape, p_bamt,
              p_cband, p_cloop, p_cshape, p_camt,
              p_hue, p_spread, p_sat, p_follow;

#define TAU 6.2831853
#define CELL 2.0                 // one bay of the corridor, in world units

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }

// Set once per pixel, so map() -- called up to a hundred times -- does no setup of its own.
float gZ, gSides, gIter, gScale, gBore, gTwist;
vec3 gOff;
mat2 gRA, gRB;
vec4 gTrap;                      // the orbit trap of the last point map() looked at

float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// The kaleidoscope: mirror the cross-section into n wedges. Mirrors are isometries, so the
// distance field survives the fold and the march stays honest.
vec2 kal(vec2 p, float n) {
  float seg = TAU / n;
  float a = abs(mod(atan(p.y, p.x) + seg * 0.5, seg) - seg * 0.5);
  return length(p) * vec2(cos(a), sin(a));
}

// Distance to the cathedral, and the orbit trap left in gTrap for whoever wants the colour.
//
// The order matters. Mirror first, so the picture is symmetrical about the axis of travel;
// then tile space into identical cells, so there is stonework in every direction however
// far the ray goes, instead of one bounded lump the ray sails past; then fold the cell into
// itself, which is where the detail below the cell size comes from.
float map(vec3 p) {
  float r = length(p.xy);                       // the radius before folding: the nave is cut with this
  p.xy = rot(p.z * gTwist) * p.xy;              // the corridor turns as it goes
  p.xy = kal(p.xy, gSides);
  p.z += gZ;                                    // travel
  p = mod(p + CELL * 0.5, CELL) - CELL * 0.5;   // bay after identical bay, in all three directions
  float zc = p.z;                               // where we are within the bay, for the ribs below
  float s = 1.0;
  gTrap = vec4(1e10);
  for (int i = 0; i < 8; i++) {
    if (float(i) >= gIter) break;
    p = abs(p);                                 // fold into one octant
    if (p.x < p.y) p.xy = p.yx;                 // and sort it: the sort is what makes the arches
    if (p.x < p.z) p.xz = p.zx;
    if (p.y < p.z) p.yz = p.zy;
    p.xy = gRA * p.xy;
    p = p * gScale - gOff * (gScale - 1.0);     // scale about the offset: the same shape, smaller
    p.yz = gRB * p.yz;
    s *= gScale;
    gTrap = min(gTrap, vec4(abs(p), dot(p, p)));
  }
  // Tiling makes the fold's answer only good for half a cell, so cap it there or the ray
  // steps clean through the stonework in the next cell. The nave is a real cylinder rather
  // than a tiled one, so it keeps its full distance and the ray still crosses open space fast.
  float d = min((sdBox(p, vec3(0.92)) - 0.015) / s, CELL * 0.5);
  // Cut the nave, so the camera always has somewhere to go. A plain cylinder reads as a flat
  // wall wherever the ray grazes it, so the cut pinches once per bay: transverse ribs, which
  // is what a vault is, and they pass at the rate the bays do. One period per cell, so the
  // ribs meet themselves at the join instead of showing it.
  float nave = gBore * (1.0 + 0.10 * sin(zc * TAU / CELL));
  return max(d, nave - r);
}

// Surface normal from a tetrahedron of samples: four map() calls instead of six.
vec3 normalAt(vec3 p, float e) {
  vec2 k = vec2(1.0, -1.0);
  return normalize(k.xyy * map(p + k.xyy * e) + k.yyx * map(p + k.yyx * e) +
                   k.yxy * map(p + k.yxy * e) + k.xxx * map(p + k.xxx * e));
}

vec3 content(vec2 uv) {
  float A = drive(p_aband, p_aloop, p_ashape, p_aamt);   // Hit    -> the ring down the nave
  float B = drive(p_bband, p_bloop, p_bshape, p_bamt);   // Move   -> the fold angle
  float C = drive(p_cband, p_cloop, p_cshape, p_camt);   // Change -> the offset and the palette

  // The building. B bends the fold and C moves where it lands, so the same six sliders
  // describe a different cathedral every time C re-rolls.
  gSides = max(2.0, floor(p_sides + 0.5));
  gIter = floor(p_detail + 0.5);
  gScale = p_scale;
  gBore = p_bore * (1.0 + 0.30 * A);                     // the walls breathe out on the hit
  gTwist = p_twist * (1.0 + B);
  // C moves the fold's offset, which is what a different cathedral is. It scales all three
  // components together: that is the family the shape was chosen from, and every value of
  // it from a few floating chunks to solid crystal is worth looking at.
  float form = p_form * (1.0 + 0.35 * C);
  gOff = vec3(form, form * 0.62, form * 0.35);
  // The fold angle is the sensitive one. Past about a seventh of a turn the fold throws the
  // attractor apart and there is nothing left to light, so the slider is mapped onto the
  // window that always builds something and B only ever nudges it about inside that window.
  float fa = mix(0.030, 0.120, clamp(p_fold, 0.0, 1.0)) + 0.020 * B;
  gRA = rot(fa * TAU);
  gRB = rot((fa * 0.73 - 0.006 * B) * TAU);
  gZ = mod(u_beat / max(p_bay, 0.05) * CELL, CELL);      // travel, wrapped: still exact at hour four

  // The camera sits at the origin and the corridor comes to meet it. Roll is in cycles per
  // beat like every other speed here. Sway pushes it off the axis for parallax, but the
  // mirror symmetry about that axis is most of why this is worth staring at, so a little
  // goes a long way: past about a fifth the picture stops being a kaleidoscope.
  vec2 sp = (uv - 0.5) * vec2(u_aspect, 1.0);
  sp.y = -sp.y;
  float rad = length(sp);
  sp = rot(u_beat * p_spin * TAU) * sp;
  vec3 rd = normalize(vec3(sp * (1.05 - 0.22 * A), 1.0)); // the hit punches the lens in
  float sw = p_sway * p_bore * 0.55;                      // never further out than the nave is wide
  vec3 ro = vec3(sw * sin(u_beat * 0.061), sw * cos(u_beat * 0.043), 0.0);

  // March. Tiling and the twist both make the distance an over-estimate in places, so every
  // step is taken short of it; the twist is the worse of the two, so it shortens them further.
  float FAR = p_far;
  float steps = max(12.0, floor(p_steps + 0.5));
  float stepScale = 0.82 - 0.22 * clamp(gTwist * 2.0, 0.0, 1.0);
  float aph = fract(barBeat() / loopBeats(p_aloop));      // how far the hit's ring has got
  float wz = aph * FAR;
  float t = 0.02, si = 0.0, glow = 0.0;
  bool hit = false;
  for (int i = 0; i < 96; i++) {
    if (float(i) >= steps) break;
    float d = map(ro + rd * t);
    float eps = max(0.0006, t * u_px * 0.7);              // one pixel wide, so it cannot shimmer
    if (d < eps) { hit = true; break; }
    // Light leaking out of the stone, gathered along the ray. Integrated over the distance
    // covered rather than summed per step, so Steps changes the sharpness and not the
    // exposure -- otherwise turning the quality down would also turn the lights up.
    float dt = d * stepScale;
    float dz = t - wz;
    glow += exp(-14.0 * d) * dt * (1.0 + 5.0 * A * exp(-8.0 * dz * dz));
    t += dt;
    si += 1.0;
    if (t > FAR) break;
  }
  glow *= p_glow * 0.8;

  float hue0 = p_hue + (p_follow > 0.5 ? u_hue : 0.0);
  vec3 haze = hsv(fract(hue0 - 0.05), 0.85 * p_sat, 1.0) * 0.05;   // distance deepens, it does not dirty
  vec3 col;
  if (hit) {
    vec3 pos = ro + rd * t;
    vec4 tr = gTrap;                                      // grab it before normalAt overwrites it
    vec3 n = normalAt(pos, max(0.0008, t * u_px * 0.9));
    vec3 lig = normalize(vec3(0.45, 0.75, -0.55));
    float dif = clamp(dot(n, lig), 0.0, 1.0);
    float rim = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.5);
    float spe = pow(clamp(dot(reflect(rd, n), lig), 0.0, 1.0), 26.0);
    float ao = clamp(1.2 - 1.1 * si / steps, 0.09, 1.0);  // steps spent is a good guess at how enclosed it is

    // Colour out of the orbit trap: how near the fold carried this point to the axes, which
    // is a different answer for every piece of stone and the same answer every frame.
    float t1 = clamp(log2(tr.w + 1.0) * 0.45, 0.0, 1.0);
    float t2 = clamp(tr.x * 1.3, 0.0, 1.0);
    // The two traps sit around a third, not a half, so centre the spread on where they
    // actually land. Centring on 0.5 tips every hue a fifth of a turn towards green.
    float tv = 0.62 * t1 + 0.38 * t2;
    vec3 base = hsv(fract(hue0 + p_spread * (tv - 0.33) * 2.2 + 0.10 * C), p_sat, 1.0);

    col = base * mix(1.0, 0.02 + 1.05 * dif, p_shade) * ao;
    col += base * rim * 0.40 * ao;
    col += spe * 0.5 * p_shade * ao;
    col += base * A * 0.35 * exp(-6.0 * (t - wz) * (t - wz));   // the ring lights the stone it passes
    col = mix(haze, col, exp(-t * p_fog));
  } else {
    float far = pow(1.0 - clamp(rad * 1.6, 0.0, 1.0), 3.0);     // light at the end of the nave
    col = haze + hsv(fract(hue0 + 0.08), 0.5 * p_sat, 1.0) * 0.16 * far;
  }
  col += hsv(fract(hue0 + 0.06 + 0.10 * C), 0.55 * p_sat, 1.0) * glow;
  // A shoulder on the highlights. Without it the glow and the specular clip flat white and
  // the whole thing goes to pale mush; with it the bright stone keeps its colour and the
  // picture can stand a hard beat without blowing out.
  return 1.0 - exp(-col * 1.25);
}
