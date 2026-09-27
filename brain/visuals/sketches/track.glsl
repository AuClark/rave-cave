// Track: the waveform of the song that's actually playing. The visuals service follows the
// live deck and hands every page its rekordbox waveform, resampled per beat, so wave(beat)
// gives (height, bass, mids, highs) anywhere in the track (see render.js). Modes:
//   0 Terrain: Unknown Pleasures made of the song. Each ridge is a bar; the front ridge is the
//     bar playing now and the bars to come roll in from the distance, so you see drops coming
//   1 Scroll: the rekordbox-style colour waveform sliding past a playhead, bars ticked
//   2 Ring: the current stretch of the song wrapped round a circle, a hand sweeping round it
//   3 Meters: bass, mids and highs as three columns
// At home (no decks) it plays a captured sample or a demo track, looped.
// Params are p_* uniforms; ranges and defaults are in track.json.
uniform float p_mode, p_lines, p_window, p_play, p_amp, p_gamma, p_width, p_glow, p_past,
              p_colour, p_hue, p_sat, p_follow, p_beat;

#define TAU 6.2831853

float H(float beat) { return pow(wave(beat).x, p_gamma); }

// The track's own colour at a beat (red bass, green mids, blue highs), brightened.
vec3 trackCol(float beat) {
  vec3 c = wave(beat).yzw;
  return c / max(max(c.r, max(c.g, c.b)), 0.25);
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float A = u_aspect;
  float px = u_px;
  float w = max(p_width, px);
  vec3 tint = hsv(p_hue + (p_follow > 0.5 ? u_hue : 0.0), p_sat, 1.0);
  float amp = p_amp * (1.0 + 0.3 * k);
  vec3 col = vec3(0.0);

  if (p_mode < 0.5) {
    // Terrain: ridge j (0 = furthest) shows bar (now + N-1-j); all slide forward over each bar.
    float N = max(2.0, floor(p_lines));
    float barNow = floor((t - 1.0) / 4.0);
    float slide = fract((t - 1.0) / 4.0);
    float top = 0.12, bot = 0.92;
    float x0 = 0.18, x1 = 0.82;                             // the ridges span the middle
    float u = (uv.x - x0) / (x1 - x0);
    float inX = step(0.0, u) * step(u, 1.0);
    float e = 0.004;
    for (int jj = 0; jj < 64; jj++) {
      float j = float(jj);
      if (j > N) break;
      float base = mix(top, bot, (j + slide) / N);
      if (uv.y < base - amp * 1.05 - w) continue;
      if (base < uv.y - w - px) continue;
      float bar = barNow + (N - j);
      float bstart = bar * 4.0 + 1.0;
      float env = sin(3.1415927 * clamp(u, 0.0, 1.0));
      float hh = inX * H(bstart + 4.0 * u) * env * amp;
      float h2 = inX * H(bstart + 4.0 * (u + e)) * sin(3.1415927 * clamp(u + e, 0.0, 1.0)) * amp;
      float slope = (h2 - hh) / (e * (x1 - x0));
      float d = (uv.y - (base - hh)) / sqrt(1.0 + slope * slope);
      col *= 1.0 - smoothstep(-px, px, d);
      float line = 1.0 - smoothstep(w - px, w + px, abs(d));
      float near = 1.0 - (N - j) / N;                        // front ridges brighter
      vec3 lc = p_colour > 0.5 ? tint : mix(vec3(1.0), trackCol(bstart + 4.0 * u), 0.8);
      col = max(col, lc * line * (0.35 + 0.65 * near));
    }
  } else if (p_mode < 1.5) {
    // Scroll: x maps to beats around now; mirrored bars about the centre line.
    float b = t + (uv.x - p_play) * p_window;
    float hh = H(b) * amp * 2.5;
    float d = abs(uv.y - 0.5) - hh * 0.5;
    float fill = 1.0 - smoothstep(-px, px, d);
    vec3 c = p_colour > 0.5 ? tint * (0.4 + 0.6 * wave(b).x) : trackCol(b);
    float past = b < t ? p_past : 1.0;
    col = c * fill * past;
    col += c * p_glow * 0.25 * exp(-max(d, 0.0) * 40.0) * past;
    float barDist = abs(fract((b - 1.0) / 4.0 + 0.5) - 0.5) * 4.0 / p_window;   // to the nearest bar line, in uv.x
    float tick = 1.0 - smoothstep(0.0, 1.5 * px / A, barDist);
    col += vec3(0.25) * tick * step(abs(uv.y - 0.5), 0.47) * step(0.47, abs(uv.y - 0.5) + 0.03);
    col = mix(col, vec3(1.0), 1.0 - smoothstep(px, px * 2.5, abs(uv.x - p_play) * A));
  } else if (p_mode < 2.5) {
    // Ring: the current window of beats round a circle, starting at the top, clockwise.
    vec2 p = (uv - 0.5) * vec2(A, 1.0);
    float r = length(p);
    float a = fract(atan(p.x, -p.y) / TAU);                   // 0 at the top, clockwise
    float win = max(4.0, floor(p_window));
    float start = floor((t - 1.0) / win) * win + 1.0;
    float b = start + a * win;
    float hh = H(b) * amp * 1.5;
    float r0 = 0.25;
    float d = abs(r - r0) - hh * 0.5 - w;
    float fill = 1.0 - smoothstep(-px, px, d);
    vec3 c = p_colour > 0.5 ? tint : trackCol(b);
    float done = b <= t ? 1.0 : p_past;
    col = c * fill * done + c * p_glow * 0.2 * exp(-max(d, 0.0) * 30.0) * done;
    float ah = (t - start) / win;                             // the hand
    float dh = abs(fract(a - ah + 0.5) - 0.5) * TAU * r;
    col += vec3(1.0) * (1.0 - smoothstep(px, px * 2.5, dh)) * step(r, r0 + amp) * step(r0 - amp, r);
  } else {
    // Meters: bass, mids, highs.
    vec4 s = wave(t);
    float i = floor(uv.x * 3.0);
    float lvl = i < 0.5 ? s.y : i < 1.5 ? s.z : s.w;
    lvl = pow(lvl, p_gamma) * (0.7 + 0.3 * k) * p_amp * 4.0;
    float lx = fract(uv.x * 3.0);
    float bar = step(0.12, lx) * step(lx, 0.88) * step(1.0 - lvl, uv.y);
    float seg = step(0.2, fract(uv.y * 24.0));               // LED segments
    vec3 c = p_colour > 0.5 ? tint : (i < 0.5 ? vec3(1.0, 0.2, 0.15) : i < 1.5 ? vec3(0.2, 1.0, 0.3) : vec3(0.25, 0.5, 1.0));
    col = c * bar * seg;
  }
  return (1.0 - exp(-col * 1.6)) * (0.85 + 0.15 * k);
}
