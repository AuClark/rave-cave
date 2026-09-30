// Shared by the Visuals page (index.html) and the Launchpad (pad.html): musical rate values,
// the energy randomiser behind Calm / Groove / Drop, and the beat-quantised launcher.
//
// Vanilla, no build step, loaded with a plain <script> before the page's own code.

"use strict";

const VJ = (() => {

  // ---------------------------------------------------------------- musical rates
  // Everything is stored in cycles per beat, as everywhere else in the rig. A 1/4 note is one
  // beat, so rate 1; a 1/1 is a bar of four, so rate 0.25. Dotted (·) is half again as long,
  // a triplet (T) two thirds as long.
  const NOTES = (() => {
    const base = [[8, "8/1"], [4, "4/1"], [2, "2/1"], [1, "1/1"], [0.5, "1/2"],
                  [0.25, "1/4"], [0.125, "1/8"], [0.0625, "1/16"], [0.03125, "1/32"]];
    const out = [];
    for (const [bars, label] of base) {
      const beats = bars * 4;
      out.push({ cpb: 1 / beats, label });
      out.push({ cpb: 1 / (beats * 1.5), label: label + "·" });
      out.push({ cpb: 1 / (beats * 2 / 3), label: label + "T" });
    }
    return out.sort((a, b) => a.cpb - b.cpb);
  })();

  // Sketch speeds run backwards as well as forwards, and nought means stopped, so those get the
  // whole ladder. An automation rate only ever needs the forward half.
  const RNOTES = [...NOTES.slice().reverse().map(n => ({ cpb: -n.cpb, label: "-" + n.label })),
                  { cpb: 0, label: "stop" }, ...NOTES];
  const HZ = [0.02, 0.05, 0.1, 0.2, 0.33, 0.5, 1, 2, 3, 5, 8].map(v => ({ cpb: v, label: v + " Hz" }));

  const near = (list, v) => list.reduce((b, n) => Math.abs(n.cpb - v) < Math.abs(b.cpb - v) ? n : b, list[0]);
  const snapRate = v => near(RNOTES, v);

  // ---------------------------------------------------------------- energy
  // "Energy" means how busy the picture is: how fast things move, how many of them there are,
  // how hard the track drives them. Which way a parameter pushes comes from the sketch where it
  // says so ("energy": 1 busier, -1 calmer, 0 neither); otherwise it is a known mover, a known
  // settler, or simply randomised. A speed's energy is how fast it goes and not which way, so
  // its magnitude is aimed and the direction left to chance.
  //
  // Two kinds are never touched. "quality" buys frame rate, not looks, and a dice roll on it is
  // how you end up at nine frames a second on the projector. "fixed" is identity -- Hypnotoad's
  // collar and line weight, say: randomising those does not give you a different look, it gives
  // you something that is no longer the thing it is supposed to be.
  const BUSY = new Set(["aamt", "bamt", "camt", "bounce", "dance", "noodle", "boil", "film", "glow",
    "jitter", "twist", "spin", "zoom", "patspin", "patscale", "prop", "propodds", "pat", "detail",
    "cast", "density", "speed", "wspeed", "wspd", "gspeed", "flow", "orbit", "beat", "punch",
    "aliens", "legs", "kal", "rosette", "burst", "lines", "trees", "people", "glitch", "rays"]);
  const CALM = new Set(["fog", "bg", "swap", "far", "day", "climb"]);

  const isRate = p => p.kind === "rate";
  const skip = p => p.id === "follow" || p.kind === "quality" || p.kind === "fixed";
  const dirOf = p => p.energy !== undefined ? p.energy
    : (isRate(p) || BUSY.has(p.id)) ? 1 : CALM.has(p.id) ? -1 : 0;

  const quant = (p, v) => {
    v = isRate(p) ? snapRate(v).cpb : Math.round(v / p.step) * p.step;
    return Math.max(p.min, Math.min(p.max, v));
  };

  // A whole new set of values at the given energy (0 calm .. 1 full on). lo/hi come from the
  // caller so the ranges on the sliders are respected: nothing ever leaves them.
  function energyValues(params, lo, hi, e) {
    const out = {};
    for (const p of params) {
      if (skip(p)) continue;
      const a = lo(p), b = hi(p), dir = dirOf(p);
      let t;
      if (dir === 0) t = Math.random();
      else {
        const jit = 0.12 + 0.22 * e;
        t = Math.min(1, Math.max(0, (dir > 0 ? e : 1 - e) + (Math.random() - 0.5) * 2 * jit));
      }
      let v = a + t * (b - a);
      if (isRate(p) && a < 0 && b > 0) {
        const mag = Math.max(Math.abs(a), Math.abs(b)) * t;
        v = (Math.random() < 0.5 ? -1 : 1) * mag;
      }
      out[p.id] = quant(p, Math.max(a, Math.min(b, v)));
    }
    return out;
  }

  // Intensity: one fader, calm to full on, played live. Unlike energyValues nothing is random, so
  // dragging it back and forth goes back and forth through the same looks rather than rolling new
  // ones. Only the parameters that have a direction move (how busy, how hard the track drives
  // the picture); the rest, the look itself, stays as it is.
  //
  // It stays on the beat: every speed is snapped to a note value (1/4, 1/8 ...), so a moving thing
  // still lands on the grid at any intensity, and the track drives (Hit, Move, Change) are what
  // the fader leans on most. It never retimes anything, it only says how much.
  function intensityValues(params, lo, hi, e, cur = {}) {
    const out = {};
    for (const p of params) {
      if (skip(p)) continue;
      const dir = dirOf(p);
      if (!dir) continue;
      const a = lo(p), b = hi(p), t = dir > 0 ? e : 1 - e;
      let v = a + t * (b - a);
      if (isRate(p) && a < 0 && b > 0) {                  // a speed: how fast, keeping which way it turns
        const sign = (cur[p.id] ?? p.default) < 0 ? -1 : 1;
        v = sign * Math.max(Math.abs(a), Math.abs(b)) * Math.max(t, 0.06);
      }
      out[p.id] = quant(p, Math.max(a, Math.min(b, v)));
    }
    return out;
  }
  // Where the fader sits for a set of values: the average of the same mapping read backwards.
  function intensityOf(params, lo, hi, cur = {}) {
    let sum = 0, n = 0;
    for (const p of params) {
      if (skip(p) || !dirOf(p)) continue;
      const a = lo(p), b = hi(p); if (b === a) continue;
      let v = cur[p.id] ?? p.default;
      if (isRate(p) && a < 0 && b > 0) { v = Math.abs(v); sum += v / Math.max(Math.abs(a), Math.abs(b)); n++; continue; }
      const t = (v - a) / (b - a);
      sum += dirOf(p) > 0 ? t : 1 - t; n++;
    }
    return n ? Math.max(0, Math.min(1, sum / n)) : 0.5;
  }

  // The fader itself, the same on every page that has one: the whole bar is the control (drag or
  // tap anywhere on it), a fill that breathes on the beat, arrow keys for a laptop. onInput gets
  // 0..1 while it moves, at most every 40 ms; set(v) moves it from outside (ignored mid-drag).
  function fader(el, onInput, label = "Intensity") {
    el.classList.add("s5fader"); el.tabIndex = 0; el.setAttribute("role", "slider");
    el.setAttribute("aria-label", label); el.setAttribute("aria-valuemin", 0); el.setAttribute("aria-valuemax", 100);
    el.innerHTML = `<div class="f"></div><div class="t"><span>${label}</span><b>–</b></div>`;
    const fill = el.querySelector(".f"), num = el.querySelector("b");
    let v = 0.5, busy = false, last = 0, tm = null;
    const paint = x => { v = x; fill.style.width = (x * 100).toFixed(1) + "%"; num.textContent = Math.round(x * 100); el.setAttribute("aria-valuenow", Math.round(x * 100)); };
    const emit = () => { clearTimeout(tm); const now = performance.now();
      if (now - last > 40) { last = now; onInput(v); } else tm = setTimeout(() => { last = performance.now(); onInput(v); }, 40); };
    const at = e => { const r = el.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); };
    el.addEventListener("pointerdown", e => { busy = true; el.setPointerCapture(e.pointerId); el.classList.add("drag"); paint(at(e)); emit(); });
    el.addEventListener("pointermove", e => { if (busy) { paint(at(e)); emit(); } });
    for (const ev of ["pointerup", "pointercancel"]) el.addEventListener(ev, () => { busy = false; el.classList.remove("drag"); });
    el.addEventListener("keydown", e => { const d = { ArrowRight: .05, ArrowUp: .05, ArrowLeft: -.05, ArrowDown: -.05 }[e.key];
      if (d) { e.preventDefault(); e.stopPropagation(); paint(Math.max(0, Math.min(1, v + d))); emit(); } });
    paint(v);
    return {
      set: x => { if (!busy && x != null && Math.abs(x - v) > 0.004) paint(x); },
      beat: f => el.style.setProperty("--pulse", f ? Math.pow(1 - f.frac, 3).toFixed(3) : 0),
      get value() { return v; }, get busy() { return busy; },
    };
  }

  // ---------------------------------------------------------------- quantised launch
  // A tap can either happen now or wait for the next musical boundary, so a change always lands
  // on the beat however sloppily it was hit. Nothing here touches the shader or the network
  // timing: it simply holds the action until the beat comes round.
  //
  // The boundaries are worked out on a beat counter shifted so every downbeat is a multiple of
  // four -- the same trick as barBeat() in the shaders -- so "1 bar" means the 1 and not
  // wherever the track happened to start.
  const GRID = [
    { beats: 0, label: "now" },
    { beats: 1, label: "1 beat" },
    { beats: 4, label: "1 bar" },
    { beats: 8, label: "2 bars" },
    { beats: 16, label: "4 bars" },
  ];

  function barBeat(f) {
    return f.beat - ((((Math.floor(f.beat) - (Math.round(f.bwb) - 1)) % 4) + 4) % 4);
  }

  class Launcher {
    constructor(frameOf) { this.frameOf = frameOf; this.grid = 4; this.pending = []; }

    // Returns null if it fired at once, otherwise how many beats until it does.
    launch(fn, tag) {
      const f = this.frameOf();
      if (!f || !this.grid) { fn(); return null; }
      const bb = barBeat(f);
      // A hair of slack, so a tap landing right on the line fires on that line and not a whole
      // bar later; a tap a fraction early is what a human hitting the 1 actually does.
      const at = this._next(bb);
      if (tag) this.pending = this.pending.filter(q => q.tag !== tag);   // one pending per slot
      this.pending.push({ at, fn, tag });
      return at - bb;
    }

    _next(bb) { return Math.ceil((bb + 0.08) / (this.grid || 1)) * (this.grid || 1); }

    cancel(tag) { this.pending = this.pending.filter(q => q.tag !== tag); }
    waiting(tag) { return this.pending.some(q => q.tag === tag); }

    // Call once a frame. Returns 0..1 through the wait for whatever is queued, for a progress ring.
    tick() {
      const f = this.frameOf();
      if (!f) return 0;
      const bb = barBeat(f);
      // The beat counter goes backwards when a new track is loaded. A pad queued for beat 300
      // would then wait out the whole new track, so anything now further off than one grid
      // step is put on the next boundary of the new count instead.
      for (const q of this.pending) if (q.at - bb > (this.grid || 1) + 0.1) q.at = this._next(bb);
      const due = this.pending.filter(q => q.at <= bb);
      if (due.length) {
        this.pending = this.pending.filter(q => q.at > bb);
        for (const q of due) q.fn();
      }
      if (!this.pending.length) return 0;
      const next = Math.min(...this.pending.map(q => q.at));
      return 1 - Math.max(0, Math.min(1, (next - bb) / this.grid));
    }
  }

  return { NOTES, RNOTES, HZ, near, snapRate, isRate, skip, dirOf, quant, energyValues, intensityValues, intensityOf, fader,
           GRID, barBeat, Launcher };
})();
