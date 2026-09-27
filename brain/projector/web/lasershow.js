// Sektor5 laser shows for the Stage view: big-show laser looks, locked to the show's beat clock.
//
// laserFrame(lookId, f, ctx) says what one laser fixture draws this frame:
//   { cue, level, beams: [{ yaw, pitch, rgb }], sheet: null | { dirs: [[yaw, pitch], ...], rgbA, rgbB, amount } }
// Angles are radians in the fixture's own frame (0,0 = straight at its aim point). yaw > 0 is towards
// stage centre, so every look is mirrored left/right; pitch > 0 is up. A sheet is a continuous plane
// (or, when its first and last directions meet, a cone) of scanned light, like a liquid sky or tunnel.
//
// f is the Stage page's show frame (scene, beat, frac, progress, since, hue, intensity).
// ctx: { side: -1 left | 1 right, idx, count (lasers in the rig), t (seconds), seed (per track),
//        classic: { n, spread, rgb } for the "classic" look }.
//
// Each look picks a cue per section (intro, groove, build, drop, breakdown) and changes cue every
// 8 bars (every 4 in a drop), so the show moves on with the phrasing of the track.

const TAU = Math.PI * 2, PI = Math.PI;
const lerp = (a, b, k) => a + (b - a) * k;
const hash = n => { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
function hsl(h, s = 1, l = 0.5) {
  h = ((h % 1) + 1) % 1;
  const k = n => (n + h * 12) % 12, a = s * Math.min(l, 1 - l);
  const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1));
  return [f(0), f(8), f(4)];
}
export function strHash(s) { let h = 7; for (const c of String(s || "")) h = (h * 31 + c.charCodeAt(0)) | 0; return Math.abs(h); }

// ------------------------------------------------------------------ colours
const WHITE = [1, 1, 1], ICE = [0.75, 0.9, 1], RED = [1, 0.04, 0.02], GREEN = [0.08, 1, 0.18], CYAN = [0, 0.85, 1],
      VIOLET = [0.45, 0.12, 1], AMBER = [1, 0.55, 0.05];
const PAL = {
  epic:      (x, i, f)    => i % 2 ? hsl(f.hue) : ICE,                    // cool white with the track's colour
  mafia:     (x, i)       => i % 3 === 1 ? WHITE : RED,                   // red and white, nothing else
  trance:    (x, i)       => i % 4 === 3 ? CYAN : GREEN,                  // the classic green, a little cyan
  afterlife: (x, i)       => i % 3 === 2 ? VIOLET : ICE,                  // cold white and violet
  mainstage: (x, i, f, t) => hsl(x * 0.75 + t * 0.07),                    // full rainbow across the fan, drifting
  techno:    (x, i)       => i % 5 === 4 ? AMBER : WHITE,                 // white with amber flashes
};

// ------------------------------------------------------------------ cues
// Each cue: (f, c, o) -> { beams, sheet }. o: { pal, tight (1 = full size, less = narrower),
// spin (rotation speed factor), ...the look's own parameters }.
const beamsOf = (n, o, f, c, fn) => {
  const out = [];
  for (let i = 0; i < n; i++) { const x = n === 1 ? 0.5 : i / (n - 1), [yaw, pitch] = fn(x, i); out.push({ yaw, pitch, rgb: o.pal(x, i, f, c.t) }); }
  return out;
};
const sheetOf = (n, o, f, c, fn, amount, closed = false) => {
  const dirs = [];
  for (let i = 0; i < n; i++) dirs.push(fn(closed ? i / n : i / (n - 1)));
  if (closed) dirs.push(dirs[0]);
  return { dirs, rgbA: o.pal(0, 0, f, c.t), rgbB: o.pal(1, 1, f, c.t), amount };
};

const CUES = {
  // A wide fan swinging across the crowd, a half-swing per beat.
  fan: (f, c, o) => ({ beams: beamsOf(o.n || 24, o, f, c, x => [
    (x - 0.5) * 1.7 * o.tight + Math.sin(f.beat * PI / 2) * 0.45, -0.02 + 0.03 * Math.sin(f.beat * PI + x * 6)]) }),

  // The rippling horizon: a dense fan whose beams rise and fall in a wave that travels across it.
  wave: (f, c, o) => ({ beams: beamsOf(o.n || 48, o, f, c, x => [
    (x - 0.5) * 2.0 * o.tight, -0.03 + 0.13 * (o.amp || 1) * Math.sin(TAU * x * 1.5 - f.beat * PI / 2 * o.spin)]) }),

  // A cone of beams round the aim line, turning; its surface drawn as a faint scanned sheet.
  tunnel: (f, c, o) => {
    const n = o.n || 32, kick = Math.exp(-5 * f.frac), R = (o.R || 0.22) * o.tight * (0.88 + 0.12 * kick);
    const rot = f.beat * PI / (o.slow ? 16 : 4) * o.spin * c.side;
    const dir = x => [0.12 + R * Math.cos(TAU * x + rot), R * 0.8 * Math.sin(TAU * x + rot)];
    return { beams: beamsOf(n, o, f, c, (x, i) => dir(i / n)), sheet: sheetOf(64, o, f, c, dir, 0.35, true) };
  },

  // Liquid sky: a single sheet of light over the crowd's heads, rippling slowly like water.
  sky: (f, c, o) => {
    const dir = x => [(x - 0.5) * 2.2, -0.04 + 0.035 * Math.sin(TAU * x * 2 + c.t * 1.3 * o.spin) + 0.02 * Math.sin(TAU * x * 5 - c.t * 2.1)];
    return { beams: beamsOf(2, o, f, c, x => dir(x)), sheet: sheetOf(80, o, f, c, dir, 1) };
  },

  // Crossfire: beams from each side shooting across the centre, flipping high/low on every beat.
  cross: (f, c, o) => ({ beams: beamsOf(o.n || 12, o, f, c, (x, i) => [
    0.2 + x * 0.95 + 0.15 * Math.sin(f.beat * PI / 4), ((i + Math.floor(f.beat)) % 2 ? 0.05 : -0.1)]) }),

  // Knives: a vertical fan slicing sideways across the room.
  knives: (f, c, o) => ({ beams: beamsOf(o.n || 14, o, f, c, x => [
    Math.sin(f.beat * PI / 2 * o.spin + c.idx) * 0.75, lerp(-0.3, 0.35, x) * o.tight]) }),

  // Chase: a few beams jumping to new random spots on every step (quarter or eighth notes).
  chase: (f, c, o) => {
    const div = o.div || 2, step = Math.floor(f.beat * div);
    return { beams: beamsOf(o.n || 6, o, f, c, (x, i) => {
      const r = k => hash(step * 31 + i * 7 + c.idx * 101 + c.seed % 997 + k);
      return [lerp(-0.9, 0.9, r(0)), lerp(-0.25, 0.2, r(1))];
    }) };
  },

  // Audience scan: a fan tilting from the floor up over the crowd and back, over two bars.
  scan: (f, c, o) => {
    const p = -0.28 + 0.36 * (0.5 - 0.5 * Math.cos(f.beat * PI / 4 * o.spin));
    return { beams: beamsOf(o.n || 36, o, f, c, x => [(x - 0.5) * 1.9 * o.tight, p]) };
  },

  // Sunburst: spokes bursting out from the centre once a bar, turning.
  burst: (f, c, o) => {
    const ph = (((f.beat % 4) + 4) % 4) / 4, R = 0.04 + 0.75 * Math.pow(ph, 0.6), rot = f.beat * PI / 8 * c.side;
    return { beams: beamsOf(o.n || 16, o, f, c, (x, i) => { const a = TAU * i / (o.n || 16) + rot; return [0.1 + R * Math.cos(a), R * 0.6 * Math.sin(a)]; }),
             fade: 1 - 0.6 * ph };
  },

  // Zigzag lattice: alternate beams tilting up and down, crossing into a diamond mesh.
  zigzag: (f, c, o) => ({ beams: beamsOf(o.n || 28, o, f, c, (x, i) => [
    (x - 0.5) * 1.8 * o.tight, -0.02 + (i % 2 ? 1 : -1) * 0.15 * Math.sin(f.beat * PI / 2 * o.spin)]) }),

  // Converge (builds): a wide fan closing to a single point in the middle as the build rises.
  converge: (f, c, o) => {
    const k = Math.pow(f.progress || 0, 0.8);
    return { beams: beamsOf(o.n || 32, o, f, c, x => [
      lerp((x - 0.5) * 2.0, 0.3, k) + 0.03 * Math.sin(f.beat * PI), lerp(0.12 * Math.sin(TAU * x * 2 + f.beat * PI / 2), 0, k)]) };
  },

  // The original simulated fan, in the fixture's own colour, beams and spread.
  classic: (f, c, o) => {
    const { n, spread, rgb } = c.classic, sc = f.scene;
    let sweep = Math.sin(f.beat * PI / 2) * 0.6, width = 1;
    if (sc === "DROP") sweep = Math.sin(f.beat * PI) * 0.9;
    else if (sc === "BUILD" || sc === "HOLD") { width = 1 - 0.85 * (f.progress || 0); sweep = 0; }
    else if (sc === "BREAKDOWN") { width = 0.15; sweep = Math.sin(f.beat * PI / 8) * 0.3; }
    else if (sc === "INTRO" || sc === "OUTRO") width = 0.5;
    const out = [];
    for (let i = 0; i < n; i++) {
      const k = n === 1 ? 0 : i / (n - 1) - 0.5;
      out.push({ yaw: (k * width + sweep) * spread * -c.side, pitch: -Math.sin(f.beat * 0.7 + i) * 0.05 * width, rgb });
    }
    return { beams: out };
  },
};

// ------------------------------------------------------------------ looks
// Styles modelled on the big touring shows (no artist's actual show data is used).
export const LOOKS = {
  auto:      { label: "Auto · new look each track" },
  epic:      { label: "Epic · Prydz-style", pal: "epic",
               intro: [["sky"], ["tunnel", { R: 0.1, slow: 1 }]], groove: [["wave"], ["tunnel"], ["fan"], ["scan"]],
               build: [["tunnel", { R: 0.35 }], ["converge"]], breakdown: [["sky"], ["tunnel", { R: 0.08, slow: 1 }]],
               drop: [["wave", { n: 64, amp: 1.4 }], ["tunnel", { R: 0.32, n: 48 }], ["burst", { n: 24 }], ["scan", { n: 48 }]] },
  mafia:     { label: "Red & white · SHM-style", pal: "mafia", dropGate: 2,
               intro: [["knives", { n: 6 }]], groove: [["cross"], ["chase"], ["knives"], ["zigzag"]],
               build: [["converge", { n: 24 }], ["knives", { n: 20 }]], breakdown: [["sky"], ["knives", { n: 4, spin: 0.25 }]],
               drop: [["cross", { n: 18 }], ["zigzag", { n: 36 }], ["chase", { n: 10, div: 4 }], ["knives", { n: 24, spin: 2 }]] },
  trance:    { label: "Trance green · ASOT-style", pal: "trance",
               intro: [["sky"]], groove: [["tunnel"], ["wave"], ["fan"], ["zigzag"]],
               build: [["tunnel", { R: 0.3 }], ["converge"]], breakdown: [["sky"], ["tunnel", { R: 0.12, slow: 1 }]],
               drop: [["tunnel", { R: 0.3, n: 48 }], ["wave", { n: 64 }], ["burst"], ["fan", { n: 40 }]] },
  afterlife: { label: "Dark & cinematic · Afterlife-style", pal: "afterlife",
               intro: [["knives", { n: 3, spin: 0.25 }]], groove: [["knives", { n: 5, spin: 0.5 }], ["sky"], ["tunnel", { R: 0.06, n: 12, slow: 1 }], ["scan", { n: 12, spin: 0.5 }]],
               build: [["tunnel", { R: 0.2, n: 16 }]], breakdown: [["sky"], ["knives", { n: 2, spin: 0.2 }]],
               drop: [["tunnel", { R: 0.26, n: 24 }], ["sky"], ["knives", { n: 10 }], ["wave", { n: 20, amp: 0.7, spin: 0.5 }]] },
  mainstage: { label: "Mainstage rainbow · Garrix-style", pal: "mainstage",
               intro: [["fan", { n: 12 }]], groove: [["fan"], ["zigzag"], ["chase", { n: 8 }], ["scan"]],
               build: [["converge", { n: 40 }], ["burst"]], breakdown: [["sky"], ["tunnel", { R: 0.1, slow: 1 }]],
               drop: [["burst", { n: 24 }], ["zigzag", { n: 40 }], ["scan", { n: 48 }], ["fan", { n: 48 }], ["chase", { n: 12, div: 4 }]] },
  techno:    { label: "Warehouse techno · strobing white", pal: "techno", dropGate: 4,
               intro: [["knives", { n: 4 }]], groove: [["chase", { n: 4 }], ["knives", { n: 8 }], ["cross", { n: 6 }]],
               build: [["converge", { n: 16 }]], breakdown: [["sky"]],
               drop: [["chase", { n: 8, div: 4 }], ["knives", { n: 16, spin: 2 }], ["cross", { n: 12 }], ["zigzag", { n: 24 }]] },
  classic:   { label: "Classic · fixture colour" },
};
const AUTO_POOL = ["epic", "mafia", "trance", "afterlife", "mainstage", "techno"];
export function resolveLook(id, seed) { return id === "auto" || !LOOKS[id] ? AUTO_POOL[seed % AUTO_POOL.length] : id; }

const SECTION = { INTRO: "intro", OUTRO: "intro", GROOVE: "groove", BUILD: "build", HOLD: "build", DROP: "drop", BREAKDOWN: "breakdown" };
const LEVEL = { intro: 0.45, groove: 0.75, build: 0.5, drop: 1, breakdown: 0.6 };

export function laserFrame(lookId, f, ctx) {
  const id = resolveLook(lookId, ctx.seed), sec = SECTION[f.scene];
  const off = { cue: "off", level: 0, beams: [], sheet: null };
  if (!sec || f.black) return off;                                          // IDLE, PREDROP blackout
  if (sec === "drop" && f.since < 0.25) return off;                         // the drop hit belongs to the strobe
  if (id === "classic") return { cue: "classic", level: sec === "drop" ? 1 : sec === "intro" || sec === "breakdown" ? 0.45 : 0.9, sheet: null, ...CUES.classic(f, ctx, {}) };
  const L = LOOKS[id], list = L[sec], bar = Math.floor(f.beat / 4);
  const pick = sec === "build" ? ctx.seed : Math.floor(bar / (sec === "drop" ? 4 : 8)) + ctx.seed;
  const [cue, params] = list[pick % list.length];
  const prog = f.progress || 0;
  const o = { pal: PAL[L.pal], tight: sec === "build" ? 1 - 0.65 * prog : 1, spin: sec === "build" ? 1 + 2 * prog : 1, ...params };
  const out = CUES[cue](f, ctx, o);
  let level = LEVEL[sec] * (out.fade ?? 1);
  const kick = Math.exp(-6 * f.frac);
  if (sec === "groove" || sec === "drop") level *= 0.72 + 0.28 * kick;
  // Gating: builds stutter faster as they rise; some looks chop the drop; every drop's 4th bar stutters.
  let gate = 0;
  if (sec === "build") { level *= 0.6 + 0.4 * prog; gate = prog < 0.5 ? 2 : prog < 0.85 ? 4 : 8; }
  else if (sec === "drop") gate = (bar % 4 === 3 && f.beat % 4 >= 2) ? 8 : L.dropGate || 0;
  if (gate && ((f.beat * gate) % 1 + 1) % 1 >= 0.5) level = 0;
  return { cue: `${id} · ${cue}`, level: level * (f.intensity ?? 0.8) / 0.8, beams: out.beams, sheet: out.sheet || null };
}
