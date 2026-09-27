// Sektor5 projection renderer: shared by the projector output (index.html) and the
// editor's live preview (edit.html).
//
// Each surface is a quad given by four corners in normalised screen coordinates
// (0..1, y down). Content is drawn per pixel through the inverse homography of that
// quad, so it lands with correct perspective on angled surfaces. Masks are black
// polygons drawn on top. All content is beat-locked to the show engine's state.
// Surfaces can have rounded corners and a border band drawn over their content.
// Content "gen" is the live generative sketch from the visuals service (:8110).
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
vec3 hsv(float h, float s, float v) {
  vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
  return v * mix(vec3(1.0), k, s);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float kick() { return exp(-6.0 * u_frac); }
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
    this.genError = null;
    this.wave = null;         // the live track's waveform (setWave)
    this.waveTex = gl.createTexture();
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

  // Compile the visuals service's sketch as content "gen". A broken sketch keeps the last good one.
  setSketch(sk) {
    try {
      const ids = sk.groups.flatMap(g => g.params.map(p => p.id));
      const prog = this._program(COMMON + sk.glsl, ids.map(id => "p_" + id));
      prog.ids = ids; prog.name = sk.name;
      this.progs.gen = prog; this.genError = null;
    } catch (e) {
      this.genError = String(e); console.error("sketch", sk.name, e);
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
                     "u_wave", "u_wv", "u_wloop", ...extra])
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
    this._updateTitle();
    gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    for (const s of L.surfaces) {
      const pr = this.progs[(L.test || opts.test) ? "test" : s.content] || this.progs.show;
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
      if (pr.ids) for (const id of pr.ids) gl.uniform1f(u["p_" + id], this.genParams[id] ?? 0);
      const wv = this.wave;
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, wv ? this.waveTex : this.tex); gl.uniform1i(u.u_wave, 1);
      gl.uniform4f(u.u_wv, wv ? wv.w : 1, wv ? wv.h : 1, wv ? wv.spb : 0, wv ? wv.beats : 0);
      gl.uniform1f(u.u_wloop, wv ? wv.loop : 0);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, this.tex); gl.uniform1i(u.u_tex, 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    // Masks (black) on the overlay, then edit handles.
    const o = this.o;
    o.fillStyle = "#000";
    if (L.masks.length || L.edit || opts.handles) this.ovDirty = true;
    for (const m of L.masks) {
      o.beginPath();
      m.points.forEach(([x, y], i) => (i ? o.lineTo(x * W, y * H) : o.moveTo(x * W, y * H)));
      o.closePath(); o.fill();
    }
    if (L.edit || opts.handles) this.drawHandles(opts);
  }

  drawHandles(opts = {}) {
    const L = this.layout, o = this.o, W = this.ov.width, H = this.ov.height;
    const r = Math.max(8, Math.min(W, H) * 0.012);
    o.lineWidth = Math.max(2, r / 4);
    o.font = `600 ${Math.round(r * 1.6)}px system-ui, sans-serif`;
    for (const s of L.surfaces) {
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
      o.fillText(`${s.name || s.id} · ${s.content}`, cx, cy);
    }
    for (const m of L.masks) {
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
function connectEvents(renderer, { onLayout, onScreen, onStatus, onSketch, onParams, url = "/api/events", state = true, reload = true } = {}) {
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
      else if (m.t === "sketch") { renderer.setSketch(m.sketch); onSketch && onSketch(m.sketch); }
      else if (m.t === "params") { renderer.genParams = m.params; onParams && onParams(m.params); }
      else if (m.t === "wave") renderer.setWave(m.wave);
    };
  };
  open();
  return () => es && es.close();
}

// The visuals service (:8110, same host) feeds content "gen": its sketch and live params.
// The beat clock comes from the projector's own stream, so this one's state is ignored.
function connectVisuals(renderer, opts = {}) {
  // Over Tailscale HTTPS the visuals service is on port + 10000 (18110).
  return connectEvents(renderer, { state: false, reload: false, ...opts, url: `${location.protocol}//${location.hostname}:${location.protocol === "https:" ? 18110 : 8110}/api/events` });
}
