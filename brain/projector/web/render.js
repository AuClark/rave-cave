// Sektor5 projection renderer: shared by the projector output (index.html) and the
// editor's live preview (edit.html).
//
// Each surface is a quad given by four corners in normalised screen coordinates
// (0..1, y down). Content is drawn per pixel through the inverse homography of that
// quad, so it lands with correct perspective on angled surfaces. Masks are black
// polygons drawn on top. All content is beat-locked to the show engine's state.
// Surfaces can have rounded corners and a border band drawn over their content.
// Content "gen" is a generative sketch from the visuals service (:8110): the live one (whatever the
// Visuals page shows), or the surface's own "sketch" (+ "preset"), fetched and compiled once.
// With several projectors, each surface and mask belongs to one; draw() renders one projector.
// Sketches can also read the live track's waveform by beat: wave(beat) (see COMMON).

"use strict";

const SCENES = { IDLE: 0, INTRO: 1, GROOVE: 2, BREAKDOWN: 3, BUILD: 4, HOLD: 5, PREDROP: 6, DROP: 7, OUTRO: 8, PAUSED: 9 };

// ---------------------------------------------------------------- live show state

// Updates arrive ~20x/s with network jitter, so the displayed beat doesn't snap to each one:
// it runs at the track's tempo and eases towards the reported position (at most 10% faster
// or slower), only jumping on a seek or track change.
class ShowClock {
  constructor() { this.s = null; this.at = 0; this.lead = 60; this.titleVer = 0; this.title = ""; this.b = null; this.last = 0; }
  update(s) {
    this.s = s; this.at = performance.now();
    const t = s && s.title ? s.title : "";
    if (t !== this.title) { this.title = t; this.titleVer++; }
  }
  // Everything the shaders need, extrapolated to "now + lead".
  frame(now) {
    const s = this.s;
    const dtBeats = s && s.bpm ? ((now - this.at + this.lead) / 1000) * s.bpm / 60 : 0;
    if (!s || !s.live || !s.bpm) {
      this.b = null;
      const b = now / 500;                                  // 120 BPM idle clock
      return { scene: SCENES.IDLE, beat: b, frac: b % 1, bwb: 1 + (Math.floor(b) % 4), bar: 0, hue: (now / 60000) % 1,
               progress: 0, since: 0, energy: 0.3, sp: 0 };
    }
    const target = (s.beat || 0) + dtBeats, rate = s.bpm / 60;
    const dt = Math.min(0.1, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    if (this.b === null || Math.abs(target - this.b) > 4) this.b = target;
    else {
      const pred = this.b + dt * rate, lim = 0.1 * rate * dt;
      this.b = pred + Math.max(-lim, Math.min(lim, (target - pred) * Math.min(1, dt / 0.4)));
    }
    const beat = this.b;
    const bwb = ((((s.bwb || 1) - 1) + Math.floor(beat) - Math.floor(s.beat || 0)) % 4 + 4) % 4 + 1;
    const scene = SCENES[s.scene] ?? SCENES.GROOVE;
    return { scene, beat, frac: ((beat % 1) + 1) % 1, bwb, bar: s.bar || 0, hue: s.hue || 0,
             progress: s.progress || 0, since: scene === SCENES.DROP ? (s.since_drop || 0) + dtBeats : 0,
             energy: s.energy ?? 0.5, sp: s.section_progress || 0 };
  }
}

// ---------------------------------------------------------------- parameter automation

// Any sketch parameter can move on its own between a range the user sets. The control page
// stores the settings; the value itself is worked out here, every frame, from the beat. That
// keeps it locked to the music, costs nothing on the network, needs no shader recompile, and
// means the projector and the preview arrive at the same number without talking to each other.
//
// rate is in cycles per beat like every other speed in the rig: a 1/4 note is one beat, so
// rate 1. hz: true is the one intentional exception and free-runs on wall time instead --
// see docs/reactive.md. Shapes: 0 sine, 1 triangle, 2 saw up, 3 saw down, 4 square,
// 5 random step, 6 smooth random.
//
// duty (0..1, default 0.5) is how much of a square's cycle is spent at the top. Down at 0.15 it
// is a strobe rather than a chop, which is what the Launchpad's STROBE pad wants.
function autoHash(n) { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); }
function autoEval(a, beat, inBar, time) {
  const t = (a.hz ? time : (a.retrig ? inBar : beat)) * (a.rate || 0) + (a.phase || 0);
  const x = t - Math.floor(t), n = Math.floor(t);
  let v;
  switch (a.shape | 0) {
    case 1: v = 1 - Math.abs(2 * x - 1); break;
    case 2: v = x; break;
    case 3: v = 1 - x; break;
    case 4: v = x < (a.duty === undefined ? 0.5 : a.duty) ? 1 : 0; break;
    case 5: v = autoHash(n); break;
    case 6: { const u = x * x * (3 - 2 * x); v = autoHash(n) * (1 - u) + autoHash(n + 1) * u; break; }
    default: v = 0.5 - 0.5 * Math.cos(6.2831853 * x);
  }
  const lo = a.lo, hi = a.hi;
  return lo + (hi - lo) * v;
}

// ---------------------------------------------------------------- homography

// Unit square (0,0),(1,0),(1,1),(0,1) -> quad corners. Returns 3x3 row-major.
function squareToQuad(c) {
  const [x0, y0] = c[0], [x1, y1] = c[1], [x2, y2] = c[2], [x3, y3] = c[3];
  const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  const dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  let g = 0, h = 0;
  if (Math.abs(dx3) > 1e-9 || Math.abs(dy3) > 1e-9) {
    const det = dx1 * dy2 - dx2 * dy1 || 1e-9;
    g = (dx3 * dy2 - dx2 * dy3) / det;
    h = (dx1 * dy3 - dx3 * dy1) / det;
  }
  return [x1 - x0 + g * x1, x3 - x0 + h * x3, x0,
          y1 - y0 + g * y1, y3 - y0 + h * y3, y0,
          g, h, 1];
}

function invert3(m) {
  const [a, b, c, d, e, f, g, h, i] = m;
  const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  const det = a * A + b * B + c * C || 1e-12;
  return [A / det, -(b * i - c * h) / det, (b * f - c * e) / det,
          B / det, (a * i - c * g) / det, -(a * f - c * d) / det,
          C / det, -(a * h - b * g) / det, (a * e - b * d) / det];
}

// Row-major 3x3 -> column-major Float32Array for uniformMatrix3fv.
const colMajor = m => new Float32Array([m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]);

function quadSize(c, W, H) {
  const d = (p, q) => Math.hypot((p[0] - q[0]) * W, (p[1] - q[1]) * H);
  return [(d(c[0], c[1]) + d(c[3], c[2])) / 2, (d(c[0], c[3]) + d(c[1], c[2])) / 2];
}
function quadAspect(c, W, H) {
  const [w, h] = quadSize(c, W, H);
  return h > 1 ? w / h : 1;
}

// ---------------------------------------------------------------- shaders

// Each surface is drawn as its bounding box (u_box, in clip space), not the whole screen.
const VERT = `attribute vec2 a; uniform vec4 u_box;
void main() { gl_Position = vec4(mix(u_box.xy, u_box.zw, a * 0.5 + 0.5), 0.0, 1.0); }`;

const COMMON = `
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform vec2 u_res; uniform mat3 u_Hinv; uniform float u_aspect;
uniform float u_beat, u_frac, u_bwb, u_bar, u_hue, u_scene, u_progress, u_since, u_energy, u_sp;
uniform float u_opacity, u_bright, u_sel, u_time;
uniform float u_radius, u_border, u_bbright, u_bsat, u_bpulse;
uniform float u_px;   // one output pixel in surface units (surface height = 1), for anti-aliasing
uniform sampler2D u_tex;
// The live track's waveform, resampled per beat by the visuals service (trackwave.py).
// u_wv = (texture width, height, samples per beat, beats; 0 = none). u_wloop = 1 for the demo/sample.
uniform sampler2D u_wave; uniform vec4 u_wv; uniform float u_wloop;
vec4 waveTexel(float i) {
  return texture2D(u_wave, (vec2(mod(i, u_wv.x), floor(i / u_wv.x)) + 0.5) / u_wv.xy);
}
// (height, bass, mids, highs), each 0..1, at a beat position in the track (1 = its first beat).
vec4 wave(float beat) {
  float n = u_wv.w * u_wv.z;
  if (n < 1.0) return vec4(0.0);
  float i = (beat - 1.0) * u_wv.z;
  if (u_wloop > 0.5) i = mod(i, n);
  if (i < 0.0 || i > n - 1.0) return vec4(0.0);
  float i0 = floor(i);
  return mix(waveTexel(i0), waveTexel(min(i0 + 1.0, n - 1.0)), i - i0);
}
// Words typed on the Visuals page, drawn to a texture by the page and handed to every sketch.
// Eight rows of 1/8 the height, one word each, white on black, each word scaled to fit its row
// with its letterforms intact. u_textn says how many rows are actually in use.
uniform sampler2D u_text; uniform float u_textn;
// Coverage of word ROW at uv, where uv is 0..1 across that word's own row and uv.y = 0 is the
// top of it. Off the edge of the word it is 0, so a sketch can lay it anywhere without clipping.
float word(vec2 uv, float row) {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
  float k = mod(floor(row + 0.5), max(1.0, u_textn));
  return texture2D(u_text, vec2(uv.x, (k + uv.y) * 0.125)).r;
}
vec3 hsv(float h, float s, float v) {
  vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
  return v * mix(vec3(1.0), k, s);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float kick() { return exp(-6.0 * u_frac); }
// --- Audio-reactive drivers (docs/reactive.md) ------------------------------
// One frequency band of the live track, 0..1. 0 = off, and off means 1.0: not gated
// by sound, so the shape below runs on tempo alone (the LFO case).
float band(float b, float beat) {
  if (b < 0.5) return 1.0;
  vec4 w = wave(beat);
  if (b < 1.5) return w.y;          // kick / low end
  if (b < 2.5) return w.z;          // chords / mids
  if (b < 3.5) return w.w;          // hats / highs
  if (b < 4.5) return w.x;          // everything
  return u_energy;                  // the show engine's energy
}
// Loop length in beats: half a beat, a beat, then 1, 2, 4, 8, 16 bars.
float loopBeats(float r) {
  if (r < 0.5) return 0.5;
  if (r < 1.5) return 1.0;
  if (r < 2.5) return 4.0;
  if (r < 3.5) return 8.0;
  if (r < 4.5) return 16.0;
  if (r < 5.5) return 32.0;
  return 64.0;
}
// The beat counter shifted so every downbeat is a multiple of 4, which puts loops of a
// bar or longer on the "1" instead of wherever the track's first beat happened to fall.
float barBeat() { return u_beat - mod(floor(u_beat) - (u_bwb - 1.0), 4.0); }
// A driver, 0..1: the loop says when it fires, the band says how hard.
float drive(float bd, float rate, float shape, float amt) {
  float L = loopBeats(rate), bb = barBeat();
  float ph = fract(bb / L);                                        // 0..1 through this loop
  float n = floor(bb / L);                                         // which loop we are in
  // How loud the band was when the loop fired. Two samples over the first beat, so a long
  // loop isn't decided by whatever happened to be in one 32nd note.
  float hit = max(band(bd, n * L + 0.15), band(bd, n * L + 0.55));
  float v;
  if      (shape < 0.5) v = band(bd, u_beat);                      // follow
  else if (shape < 1.5) v = hit * exp(-5.0 * ph * max(L, 1.0));    // punch
  else if (shape < 2.5) v = hit * ph;                              // ramp
  else if (shape < 3.5) v = hit * (0.5 - 0.5 * cos(6.2831 * ph));  // swell
  else if (shape < 4.5) v = hit * step(ph, 0.5);                   // gate
  else                  v = hit * hash(vec2(n, bd));               // step
  return amt * clamp(v, 0.0, 1.0);
}
vec3 content(vec2 uv);
void main() {
  vec2 p = vec2(gl_FragCoord.x / u_res.x, 1.0 - gl_FragCoord.y / u_res.y);
  vec3 q = u_Hinv * vec3(p, 1.0);
  vec2 uv = q.xy / q.z;
  if (q.z <= 0.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) discard;
  // Rounded-rectangle distance in surface units (height = 1): < 0 inside.
  vec2 hs = vec2(u_aspect, 1.0) * 0.5, sp = (uv - 0.5) * vec2(u_aspect, 1.0);
  float rad = min(u_radius, min(hs.x, hs.y));
  vec2 qd = abs(sp) - hs + rad;
  float sd = length(max(qd, 0.0)) + min(max(qd.x, qd.y), 0.0) - rad;
  float a = smoothstep(0.0, 1.5 * u_px, -sd) * u_opacity;
  vec3 c = content(uv) * u_bright;
  if (u_border > 0.0) {
    float band = smoothstep(-u_border - 1.5 * u_px, -u_border, sd);
    vec3 bc = mix(vec3(1.0), hsv(u_hue, 1.0, 1.0), u_bsat) * u_bbright * mix(1.0, kick(), u_bpulse);
    c = mix(c, bc * u_bright, band);
  }
  if (u_sel > 0.5) c = mix(c, vec3(0.2, 0.9, 1.0), 0.25 * step(-sd, 0.012));
  gl_FragColor = vec4(c, a);
}
`;

const CONTENT = {
  solid: `vec3 content(vec2 uv) { return hsv(u_hue, 0.9, 0.85); }`,

  pulse: `vec3 content(vec2 uv) {
    float accent = u_bwb < 1.5 ? 0.35 : 0.0;
    vec3 c = hsv(u_hue + 0.03 * mod(u_bar, 4.0), 1.0, 0.12 + 0.88 * kick());
    return mix(c, vec3(0.12 + 0.88 * kick()), accent * kick());
  }`,

  tunnel: `vec3 content(vec2 uv) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float r = length(p) + 0.02, a = atan(p.y, p.x);
    float rings = 0.5 + 0.5 * cos((0.6 / r - u_beat * 0.5) * 6.2831);
    float spokes = 0.75 + 0.25 * cos(a * 8.0 + u_beat * 0.8);
    float v = rings * spokes * (0.25 + 0.75 * kick()) * smoothstep(0.0, 0.08, r);
    return hsv(u_hue + r * 0.4 + 0.05 * u_bar, 1.0, v);
  }`,

  bars: `vec3 content(vec2 uv) {
    float n = 16.0, i = floor(uv.x * n), fx = fract(uv.x * n);
    float h = 0.15 + 0.85 * hash(vec2(i, floor(u_beat))) * (0.35 + 0.65 * u_energy);
    h *= 0.45 + 0.55 * kick();
    float lit = step(1.0 - uv.y, h) * step(0.08, fx) * step(fx, 0.92);
    float cap = step(abs((1.0 - uv.y) - h), 0.012) * step(0.08, fx) * step(fx, 0.92);
    return hsv(u_hue + i / (n * 2.0), 1.0, lit * (0.35 + 0.65 * (1.0 - uv.y) / max(h, 0.01))) + cap;
  }`,

  title: `vec3 content(vec2 uv) {
    float t = texture2D(u_tex, uv).r;
    vec3 bg = hsv(u_hue, 1.0, 0.06 + 0.1 * kick());
    return mix(bg, mix(hsv(u_hue, 0.35, 1.0), vec3(1.0), kick() * 0.6), t);
  }`,

  show: `vec3 content(vec2 uv) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float r = length(p), k = kick();
    int sc = int(u_scene + 0.5);
    if (sc == 6) return vec3(0.0);                                  // PREDROP: blackout
    if (sc == 7) {                                                  // DROP
      if (u_since < 0.25) return vec3(1.0);
      float ring = exp(-abs(r - fract(u_since) * 0.9) * 18.0);
      vec3 base = hsv(u_hue + (mod(floor(u_since), 2.0) > 0.5 ? 0.5 : 0.0), 1.0, 0.25 + 0.75 * k);
      return mix(base * 0.6, vec3(1.0), ring * 0.85);
    }
    if (sc == 4 || sc == 5) {                                       // BUILD / HOLD
      float pr = u_progress;
      float rate = pr < 0.5 ? 1.0 : pr < 0.75 ? 2.0 : pr < 0.9 ? 4.0 : 8.0;
      float on = step(fract(u_beat * rate), 0.45);
      float fill = step(1.0 - uv.y, 0.15 + 0.85 * pr);
      vec3 c = mix(hsv(u_hue, 1.0, 1.0), vec3(1.0), pr * 0.8);
      return c * fill * (on > 0.5 ? 0.3 + 0.7 * pr : 0.03);
    }
    if (sc == 3) {                                                  // BREAKDOWN: sparse, synced
      float hb = 0.5 + 0.5 * cos(3.14159 * mod(u_beat, 2.0));
      float pl = 0.5 + 0.25 * sin(p.x * 5.0 + u_beat * 0.3) + 0.25 * sin((p.x + p.y * 2.0) * 3.0 - u_beat * 0.2);
      vec3 c = hsv(u_hue - 0.05 + 0.3 * pl, 0.55 + 0.35 * u_sp, (0.03 + 0.08 * u_energy + 0.05 * u_sp) * (0.5 + 0.5 * hb));
      vec2 cell = floor(uv * vec2(24.0 * u_aspect, 24.0));
      float eighth = floor(u_beat * 2.0);
      float spark = step(0.985 - 0.02 * u_sp, hash(cell + eighth)) * exp(-fract(u_beat * 2.0) * 5.0);
      return c + vec3(spark * (0.6 + 0.4 * u_sp));
    }
    if (sc == 2) {                                                  // GROOVE
      float wave = exp(-abs(r - (u_frac * 0.8)) * 10.0) * k;
      vec3 c = hsv(u_hue + 0.03 * mod(u_bar, 4.0) + r * 0.2, 1.0, 0.1 + 0.55 * k);
      c += hsv(u_hue + 0.5, 0.6, 1.0) * wave * 0.7;
      if (u_bwb < 1.5) c = mix(c, vec3(1.0), 0.3 * k);
      return c;
    }
    float breathe = 0.5 + 0.5 * sin(u_beat * 3.14159 / 4.0);       // INTRO / OUTRO / IDLE / PAUSED
    float fade = sc == 8 ? 0.6 : sc == 9 ? 0.3 : 1.0;
    return hsv(u_hue + uv.x * 0.15, 0.8, (0.05 + 0.12 * breathe) * fade * (1.0 - 0.5 * r));
  }`,
};
// Test card: grid, border, diagonals, centre circle, coloured corners (no derivative extension needed).
CONTENT.test = `vec3 content(vec2 uv) {
  vec2 g = abs(fract(uv * 10.0 + 0.5) - 0.5) * 10.0;
  float grid = step(min(g.x * u_aspect, g.y), 0.02);
  float border = step(min(min(uv.x, 1.0 - uv.x) * u_aspect, min(uv.y, 1.0 - uv.y)), 0.012);
  float diag = step(abs(uv.x - uv.y), 0.004) + step(abs(uv.x - (1.0 - uv.y)), 0.004);
  vec2 cp = (uv - 0.5) * vec2(u_aspect, 1.0);
  float circle = step(abs(length(cp) - 0.4), 0.004);
  vec3 c = vec3(0.35) * grid + vec3(1.0) * clamp(border + circle + diag * 0.6, 0.0, 1.0);
  float m = 0.12;
  if (uv.x < m / u_aspect && uv.y < m) c = vec3(1.0, 0.0, 0.0);
  if (uv.x > 1.0 - m / u_aspect && uv.y < m) c = vec3(0.0, 1.0, 0.0);
  if (uv.x > 1.0 - m / u_aspect && uv.y > 1.0 - m) c = vec3(0.0, 0.3, 1.0);
  if (uv.x < m / u_aspect && uv.y > 1.0 - m) c = vec3(1.0, 1.0, 0.0);
  return c;
}`;

// ---------------------------------------------------------------- renderer

class MapRenderer {
  constructor(canvas, overlay) {
    this.cv = canvas; this.ov = overlay; this.o = overlay.getContext("2d");
    const gl = canvas.getContext("webgl", { antialias: false, premultipliedAlpha: false, preserveDrawingBuffer: false });
    if (!gl) throw new Error("WebGL not available");
    this.gl = gl;
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    this.progs = {};
    for (const [name, src] of Object.entries(CONTENT)) this.progs[name] = this._program(COMMON + src);
    this.tex = gl.createTexture();
    this.titleCanvas = document.createElement("canvas");
    this.titleCanvas.width = 1024; this.titleCanvas.height = 256;
    this.titleVer = -1;
    this.layout = null;
    this.clock = new ShowClock();
    this.genParams = {};      // live values from the visuals service
    this.genAuto = {};        // per-parameter automation settings, from the same place
    this.genSpec = {};        // id -> {min, max, step, kind} out of the sketch's schema
    this.genLive = {};        // what the shader actually gets: genParams with automation applied
    this.genFreeze = false;   // hold every automated value where it is (the page's Freeze)
    this._frz = null;
    this.lastFrame = null;    // the clock frame this draw used, for pages that want to read it
    this.genError = null;
    this.liveSketch = null;   // the active sketch's name
    this.sketches = {};       // "name|preset" -> { prog, values } once loaded, { loading } / { error } before
    this.wave = null;         // the live track's waveform (setWave)
    this.waveTex = gl.createTexture();
    this.textTex = gl.createTexture();
    this.textN = 1;
    this.textCanvas = document.createElement("canvas");
    // 2048 across eight rows is 256px a row. A near ring can magnify one row over half the
    // screen, and at 128 the diagonals of the letterforms stair-step visibly.
    this.textCanvas.width = 2048; this.textCanvas.height = 2048;
    this.setText("SEKTOR5");
  }

  // The live track's waveform from the visuals service: RGBA bytes (height, bass, mids, highs), base64.
  setWave(w) {
    const gl = this.gl, bin = atob(w.data), px = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) px[i] = bin.charCodeAt(i);
    gl.bindTexture(gl.TEXTURE_2D, this.waveTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w.w, w.h, 0, gl.RGBA, gl.UNSIGNED_BYTE, px);
    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.NEAREST], [gl.TEXTURE_MAG_FILTER, gl.NEAREST],
                          [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]])
      gl.texParameteri(gl.TEXTURE_2D, k, v);
    this.wave = { w: w.w, h: w.h, spb: w.spb, beats: w.beats, loop: w.loop ? 1 : 0, title: w.title, source: w.source };
  }

  // The words typed on the Visuals page, drawn into an eight-row atlas: one word per row,
  // each scaled to fit its row so the letterforms stay right whatever the word's length. Split
  // on | or a newline. Done on the CPU once per change, so the shader just samples it.
  setText(str) {
    const words = String(str || "").split(/[|\n]/).map(w => w.trim()).filter(Boolean).slice(0, 8);
    if (!words.length) words.push("SEKTOR5");
    this.textN = words.length;
    const c = this.textCanvas, g = c.getContext("2d"), ROW = c.height / 8;
    g.fillStyle = "#000"; g.fillRect(0, 0, c.width, c.height);
    g.fillStyle = "#fff"; g.textAlign = "center"; g.textBaseline = "middle";
    words.forEach((w, i) => {
      let size = Math.round(ROW * 0.82);
      g.font = `900 ${size}px system-ui, sans-serif`;
      const max = c.width * 0.96;
      const wide = g.measureText(w).width;
      if (wide > max) {                                   // long words shrink to fit their row
        size = Math.max(8, Math.floor(size * max / wide));
        g.font = `900 ${size}px system-ui, sans-serif`;
      }
      g.fillText(w, c.width / 2, i * ROW + ROW / 2);
    });
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, this.textTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, gl.LUMINANCE, gl.UNSIGNED_BYTE, c);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    this.text = str;
  }

  // Compile the visuals service's sketch as content "gen". A broken sketch keeps the last good one.
  setSketch(sk) {
    // The sketch that was live may have been changed on the Visuals page: fetch it afresh next time.
    if (this.liveSketch && this.liveSketch !== sk.name)
      for (const k of Object.keys(this.sketches)) if (k.startsWith(this.liveSketch + "|")) delete this.sketches[k];
    this.liveSketch = sk.name;
    try {
      const ids = sk.groups.flatMap(g => g.params.map(p => p.id));
      const spec = {};
      for (const g of sk.groups) for (const p of g.params)
        spec[p.id] = { min: p.min, max: p.max, step: p.step, kind: p.kind || "" };
      this.genSpec = spec;
      const prog = this._program(COMMON + sk.glsl, ids.map(id => "p_" + id));
      prog.ids = ids; prog.name = sk.name;
      this.progs.gen = prog; this.genError = null;
    } catch (e) {
      this.genError = String(e); console.error("sketch", sk.name, e);
    }
  }

  // What a "gen" surface draws: the live sketch, or its own one (loaded on first use; nothing until then).
  // The live one gets genLive -- the held values with this frame's automation on top. A surface
  // pinned to its own sketch gets the plain values it was fetched with: automation belongs to the
  // sketch the Visuals page is driving, and there is only one set of it.
  sketchFor(s) {
    if (!s.sketch || s.sketch === this.liveSketch) return this.progs.gen ? { prog: this.progs.gen, values: this.genLive } : null;
    const key = s.sketch + "|" + (s.preset || ""), e = this.sketches[key];
    if (!e) this._loadSketch(s.sketch, s.preset, key);
    return e && e.prog ? e : null;
  }

  async _loadSketch(name, preset, key) {
    this.sketches[key] = { loading: true };
    const base = visualsBase();
    try {
      const r = await fetch(`${base}/api/sketches/${encodeURIComponent(name)}` + (preset ? `?preset=${encodeURIComponent(preset)}` : ""));
      if (!r.ok) throw new Error(`${name}: ${r.status}`);
      const { sketch: sk, values } = await r.json();
      const ids = sk.groups.flatMap(g => g.params.map(p => p.id));
      const prog = this._program(COMMON + sk.glsl, ids.map(id => "p_" + id));
      prog.ids = ids; prog.name = sk.name;
      this.sketches[key] = { prog, values };
    } catch (e) {
      console.error("sketch", name, e);
      this.sketches[key] = { error: String(e) };
      setTimeout(() => { if (this.sketches[key] && this.sketches[key].error) delete this.sketches[key]; }, 15000);   // retry later
    }
  }

  _program(fsrc, extra = []) {
    const gl = this.gl;
    const sh = (type, src) => {
      const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const p = gl.createProgram();
    gl.attachShader(p, sh(gl.VERTEX_SHADER, VERT)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fsrc));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const u = {};
    for (const n of ["u_res", "u_Hinv", "u_aspect", "u_beat", "u_frac", "u_bwb", "u_bar", "u_hue", "u_scene", "u_progress",
                     "u_since", "u_energy", "u_sp", "u_opacity", "u_bright", "u_sel", "u_time", "u_tex",
                     "u_radius", "u_border", "u_bbright", "u_bsat", "u_bpulse", "u_px", "u_box",
                     "u_wave", "u_wv", "u_wloop", "u_text", "u_textn", ...extra])
      u[n] = gl.getUniformLocation(p, n);
    return { p, u, a: gl.getAttribLocation(p, "a") };
  }

  _updateTitle() {
    if (this.clock.titleVer === this.titleVer) return;
    this.titleVer = this.clock.titleVer;
    const c = this.titleCanvas, g = c.getContext("2d");
    g.fillStyle = "#000"; g.fillRect(0, 0, c.width, c.height);
    g.fillStyle = "#fff"; g.textAlign = "center"; g.textBaseline = "middle";
    let size = 120, text = this.clock.title || "SEKTOR5";
    g.font = `900 ${size}px system-ui, sans-serif`;
    while (g.measureText(text).width > c.width * 0.92 && size > 30) { size -= 6; g.font = `900 ${size}px system-ui, sans-serif`; }
    g.fillText(text, c.width / 2, c.height / 2);
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, this.tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, gl.LUMINANCE, gl.UNSIGNED_BYTE, c);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  }

  resize(w, h) {
    if (this.cv.width === w && this.cv.height === h) return;
    for (const c of [this.cv, this.ov]) { c.width = w; c.height = h; }
  }

  // GPU name, for the projector's stats.
  gpuName() {
    const gl = this.gl, ext = gl.getExtension("WEBGL_debug_renderer_info");
    return String(ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER)).slice(0, 80);
  }

  draw(now, opts = {}) {
    const gl = this.gl, L = this.layout;
    const W = this.cv.width, H = this.cv.height;
    gl.viewport(0, 0, W, H);
    gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
    if (this.ovDirty) { this.o.clearRect(0, 0, W, H); this.ovDirty = false; }   // skip when nothing was drawn
    if (!L) return;
    this.clock.lead = L.lead_ms ?? 60;
    const f = this.clock.frame(now);
    this.lastFrame = f;
    this._genFrame(f, now);
    this._updateTitle();
    gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    const P = this.projectorId(opts.projector), mine = x => (x.projector || "main") === P;
    for (const s of L.surfaces) {
      if (!mine(s)) continue;
      const test = L.test || opts.test;
      let pr = this.progs[test ? "test" : s.content] || this.progs.show, vals = this.genParams;
      if (!test && s.content === "gen") {
        const g = this.sketchFor(s);
        if (!g) continue;                                       // its sketch is still loading
        pr = g.prog; vals = g.values;
      }
      gl.useProgram(pr.p);
      gl.enableVertexAttribArray(pr.a);
      gl.vertexAttribPointer(pr.a, 2, gl.FLOAT, false, 0, 0);
      const u = pr.u;
      gl.uniform2f(u.u_res, W, H);
      gl.uniformMatrix3fv(u.u_Hinv, false, colMajor(invert3(squareToQuad(s.corners))));
      const xs = s.corners.map(c => c[0]), ys = s.corners.map(c => c[1]);
      gl.uniform4f(u.u_box, 2 * Math.min(...xs) - 1, 1 - 2 * Math.max(...ys), 2 * Math.max(...xs) - 1, 1 - 2 * Math.min(...ys));
      const [qw, qh] = quadSize(s.corners, W, H);
      gl.uniform1f(u.u_aspect, qh > 1 ? qw / qh : 1);
      gl.uniform1f(u.u_px, 1 / Math.max(qh, 1));
      gl.uniform1f(u.u_beat, f.beat); gl.uniform1f(u.u_frac, f.frac); gl.uniform1f(u.u_bwb, f.bwb);
      gl.uniform1f(u.u_bar, f.bar); gl.uniform1f(u.u_hue, (f.hue + (s.hue_shift || 0) + 1) % 1);
      gl.uniform1f(u.u_scene, f.scene); gl.uniform1f(u.u_progress, f.progress); gl.uniform1f(u.u_since, f.since);
      gl.uniform1f(u.u_energy, f.energy); gl.uniform1f(u.u_sp, f.sp);
      gl.uniform1f(u.u_opacity, s.opacity ?? 1); gl.uniform1f(u.u_bright, L.brightness ?? 1);
      gl.uniform1f(u.u_sel, L.edit && L.selected === s.id ? 1 : 0);
      gl.uniform1f(u.u_time, now / 1000);
      gl.uniform1f(u.u_radius, s.radius || 0); gl.uniform1f(u.u_border, s.border || 0);
      gl.uniform1f(u.u_bbright, s.border_bright ?? 1); gl.uniform1f(u.u_bsat, s.border_sat ?? 0);
      gl.uniform1f(u.u_bpulse, s.border_pulse ?? 0);
      if (pr.ids) for (const id of pr.ids) gl.uniform1f(u["p_" + id], vals[id] ?? 0);
      const wv = this.wave;
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, wv ? this.waveTex : this.tex); gl.uniform1i(u.u_wave, 1);
      gl.uniform4f(u.u_wv, wv ? wv.w : 1, wv ? wv.h : 1, wv ? wv.spb : 0, wv ? wv.beats : 0);
      gl.uniform1f(u.u_wloop, wv ? wv.loop : 0);
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, this.textTex); gl.uniform1i(u.u_text, 2);
      gl.uniform1f(u.u_textn, this.textN);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, this.tex); gl.uniform1i(u.u_tex, 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    // Masks (black) on the overlay, then edit handles.
    const o = this.o;
    o.fillStyle = "#000";
    if (L.masks.length || L.edit || opts.handles) this.ovDirty = true;
    for (const m of L.masks) {
      if (!mine(m)) continue;
      o.beginPath();
      m.points.forEach(([x, y], i) => (i ? o.lineTo(x * W, y * H) : o.moveTo(x * W, y * H)));
      o.closePath(); o.fill();
    }
    if (L.edit || opts.handles) this.drawHandles(opts);
  }

  // Which projector this page draws: the one asked for, if the layout has it, else the first.
  projectorId(want) {
    const ids = ((this.layout && this.layout.projectors) || [{ id: "main" }]).map(p => p.id);
    return ids.includes(want) ? want : ids[0];
  }

  // The live parameter values for this frame: the held values, with automation moved on top.
  // Once per frame and shared by every surface, so a layout with six of them costs the same.
  _genFrame(f, now) {
    const live = this.genLive, A = this.genAuto, S = this.genSpec;
    for (const id in this.genParams) live[id] = this.genParams[id];
    // The beat counter shifted so downbeats are multiples of 4, same as barBeat() in the
    // shaders, so "retrigger on bar" fires on the 1 and not wherever the track happened to start.
    const bb = f.beat - ((((Math.floor(f.beat) - (f.bwb - 1)) % 4) + 4) % 4);
    const inBar = bb - 4 * Math.floor(bb / 4);
    const t = now / 1000;
    // Freeze holds the clock the automation reads rather than switching it off, so every value
    // stays exactly where it was. Letting go goes back to the live beat, which can be a jump:
    // that keeps every page's answer a function of the beat alone (docs/visuals-live.md).
    if (this.genFreeze) { if (!this._frz) this._frz = { beat: f.beat, inBar, t }; }
    else this._frz = null;
    const F = this._frz;
    for (const id in A) {
      const a = A[id];
      if (!a || !a.on) continue;
      const s = S[id];
      let v = autoEval(a, F ? F.beat : f.beat, F ? F.inBar : inBar, F ? F.t : t);
      if (s) v = Math.max(s.min, Math.min(s.max, v));    // never outside what the sketch allows
      live[id] = v;
    }
  }

  drawHandles(opts = {}) {
    const L = this.layout, o = this.o, W = this.ov.width, H = this.ov.height;
    const P = this.projectorId(opts.projector), mine = x => (x.projector || "main") === P;
    const r = Math.max(8, Math.min(W, H) * 0.012);
    o.lineWidth = Math.max(2, r / 4);
    o.font = `600 ${Math.round(r * 1.6)}px system-ui, sans-serif`;
    for (const s of L.surfaces) {
      if (!mine(s)) continue;
      const sel = s.id === L.selected;
      o.strokeStyle = sel ? "#2fe6ff" : "rgba(255,255,255,0.6)";
      o.beginPath();
      s.corners.forEach(([x, y], i) => (i ? o.lineTo(x * W, y * H) : o.moveTo(x * W, y * H)));
      o.closePath(); o.stroke();
      s.corners.forEach(([x, y], i) => {
        o.fillStyle = ["#f33", "#3f3", "#39f", "#ff3"][i];
        o.beginPath(); o.arc(x * W, y * H, sel ? r * 1.3 : r, 0, Math.PI * 2); o.fill();
        if (sel) { o.strokeStyle = "#fff"; o.stroke(); }
      });
      const cx = s.corners.reduce((a, c) => a + c[0], 0) / 4 * W, cy = s.corners.reduce((a, c) => a + c[1], 0) / 4 * H;
      o.fillStyle = sel ? "#2fe6ff" : "#fff"; o.textAlign = "center";
      o.fillText(`${s.name || s.id} · ${s.content === "gen" && s.sketch ? s.sketch + (s.preset ? " · " + s.preset : "") : s.content}`, cx, cy);
    }
    for (const m of L.masks) {
      if (!mine(m)) continue;
      o.strokeStyle = m.id === L.selected ? "#ff2fd0" : "rgba(255,47,208,0.6)";
      o.setLineDash([r, r / 2]);
      o.beginPath();
      m.points.forEach(([x, y], i) => (i ? o.lineTo(x * W, y * H) : o.moveTo(x * W, y * H)));
      o.closePath(); o.stroke(); o.setLineDash([]);
      if (m.id === L.selected) m.points.forEach(([x, y]) => {
        o.fillStyle = "#ff2fd0"; o.beginPath(); o.arc(x * W, y * H, r * 0.8, 0, Math.PI * 2); o.fill();
      });
    }
    if (opts.draft && opts.draft.length) {
      o.strokeStyle = "#ff2fd0"; o.beginPath();
      opts.draft.forEach(([x, y], i) => (i ? o.lineTo(x * W, y * H) : o.moveTo(x * W, y * H)));
      o.stroke();
      opts.draft.forEach(([x, y]) => { o.fillStyle = "#ff2fd0"; o.beginPath(); o.arc(x * W, y * H, r * 0.7, 0, Math.PI * 2); o.fill(); });
    }
  }
}

// Connect to an event stream (the projector host's by default); calls the handlers as messages arrive.
// Each service says hello with a version of its page code; when that changes (a deploy),
// the page reloads itself so nobody has to hard-refresh the projector. reload: false opts out.
function connectEvents(renderer, { onLayout, onScreen, onScreens, onStatus, onSketch, onParams, onAuto, onText, onShuffle, url = "/api/events", state = true, reload = true } = {}) {
  let es, version = null;
  const open = () => {
    es = new EventSource(url);
    es.onopen = () => onStatus && onStatus(true);
    es.onerror = () => onStatus && onStatus(false);
    es.onmessage = e => {
      const m = JSON.parse(e.data);
      if (m.t === "state") { if (state) renderer.clock.update(m.s); }
      else if (m.t === "hello") {
        if (version && m.version !== version && reload) setTimeout(() => location.reload(), 300 + Math.random() * 700);
        version = m.version;
      }
      else if (m.t === "layout") onLayout ? onLayout(m.layout) : (renderer.layout = m.layout);
      else if (m.t === "screen" && onScreen) onScreen(m.screen);
      else if (m.t === "screens" && onScreens) onScreens(m.screens);
      else if (m.t === "sketch") { renderer.setSketch(m.sketch); onSketch && onSketch(m.sketch); }
      else if (m.t === "params") { renderer.genParams = m.params; onParams && onParams(m.params); }
      else if (m.t === "auto") {
        renderer.genAuto = m.auto || {};
        renderer.genFreeze = !!m.freeze;
        onAuto && onAuto(renderer.genAuto, renderer.genFreeze);
      }
      else if (m.t === "wave") renderer.setWave(m.wave);
      else if (m.t === "text") { renderer.setText(m.text); onText && onText(m.text); }
      else if (m.t === "shuffle") onShuffle && onShuffle(m.shuffle);
    };
  };
  open();
  return () => es && es.close();
}

// The visuals service's address: :8110 on the rig's network, /visuals through the dashboard's address
// (HTTPS / Tailscale). /s5auth.js knows; the projector output page doesn't load it, so work it out.
function visualsBase() {
  if (window.S5AUTH && S5AUTH.url) return S5AUTH.url(8110, "");
  if (location.protocol === "https:" || location.pathname.startsWith("/projection")) return location.origin + "/visuals";
  return `${location.protocol}//${location.hostname}:8110`;
}

// The visuals service (:8110, same host) feeds content "gen": its sketch and live params.
// The beat clock comes from the projector's own stream, so this one's state is ignored.
function connectVisuals(renderer, opts = {}) {
  // The visuals page's address comes from /s5auth.js (a port on the rig's network, /visuals over HTTPS).
  const url = visualsBase() + "/api/events";
  return connectEvents(renderer, { state: false, reload: false, ...opts, url });
}
