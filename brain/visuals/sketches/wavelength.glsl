// Wavelength: lines made of waves. Modes:
//   0 Ridgeline: stacked waveforms, each hiding the ones behind (Unknown Pleasures)
//   1 Spectrum: flowing sine lines, coloured by the wavelengths of visible light
//   2 Scope: a glowing oscilloscope trace with harmonics on a grid
// Everything moves in cycles per beat and swells on the kick.
// Params are p_* uniforms; ranges and defaults are in wavelength.json.
uniform float p_mode, p_lines, p_amp, p_freq, p_speed, p_phase, p_detail, p_spread, p_width, p_glow,
              p_spectrum, p_hue, p_sat, p_follow, p_beat;

#define TAU 6.2831853

float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Visible light, 0 = violet (380 nm) .. 1 = red (700 nm), roughly as the eye sees it.
vec3 spectral(float s) {
  float l = mix(380.0, 700.0, clamp(s, 0.0, 1.0));
  vec3 c = l < 440.0 ? vec3((440.0 - l) / 60.0, 0.0, 1.0)
         : l < 490.0 ? vec3(0.0, (l - 440.0) / 50.0, 1.0)
         : l < 510.0 ? vec3(0.0, 1.0, (510.0 - l) / 20.0)
         : l < 580.0 ? vec3((l - 510.0) / 70.0, 1.0, 0.0)
         : l < 645.0 ? vec3(1.0, (645.0 - l) / 65.0, 0.0)
         :             vec3(1.0, 0.0, 0.0);
  float edge = l < 420.0 ? 0.3 + 0.7 * (l - 380.0) / 40.0 : l > 680.0 ? 0.3 + 0.7 * (700.0 - l) / 20.0 : 1.0;
  return c * edge;
}

// Ridge i's height at x: a bump in the middle, jagged by noise, rolling in time.
float ridge(float x, float i, float t) {
  float env = exp(-pow((x - 0.5) / max(p_spread, 0.02), 2.0));
  float n = vnoise(vec2(x * p_freq, i * 3.1 + t * p_speed)) * 0.7
          + vnoise(vec2(x * p_freq * 2.7, i * 5.3 - t * p_speed * 1.3)) * 0.3 * p_detail;
  return env * n;
}

vec3 content(vec2 uv) {
  float t = u_beat;
  float k = kick() * p_beat;
  float A = u_aspect;
  float px = u_px;
  float w = max(p_width, px);
  vec3 tint = hsv(p_hue + (p_follow > 0.5 ? u_hue : 0.0), p_sat, 1.0);
  float amp = p_amp * (1.0 + 0.5 * k);
  float N = max(1.0, floor(p_lines));
  vec3 col = vec3(0.0);

  if (p_mode < 0.5) {
    // Ridgeline: back (top) to front (bottom); each ridge's black fill hides what's behind.
    float x = uv.x, y = uv.y;
    float top = 0.18, bot = 0.85;
    float e = 0.002;
    for (int j = 0; j < 80; j++) {
      float i = float(j);
      if (i >= N) break;
      float base = mix(top, bot, i / max(N - 1.0, 1.0));
      if (y < base - amp * 1.05 - w) continue;             // pixel is above this ridge's highest point
      if (base < y - w - px) continue;                      // ridge wholly above: it only blacks the pixel out,
                                                            // which the default black already is
      float h = ridge(x, i, t) * amp;
      float curve = base - h;
      float slope = (ridge(x + e, i, t) - ridge(x, i, t)) * amp / e;
      float d = (y - curve) / sqrt(1.0 + slope * slope);
      float fill = smoothstep(-px, px, d);                  // below the line: this ridge's black body
      col *= 1.0 - fill;
      float line = 1.0 - smoothstep(w - px, w + px, abs(d));
      vec3 lc = p_spectrum > 0.5 ? spectral(i / N) : tint;
      col = max(col, lc * line);
    }
  } else if (p_mode < 1.5) {
    // Spectrum: parallel sine lines, each shifted in phase, travelling at Speed.
    float y = uv.y;
    float gap = 1.0 / (N + 1.0);
    float fi = floor(y / gap - 0.5);
    for (int j = -2; j <= 2; j++) {                          // only nearby lines can reach this pixel
      float i = fi + float(j);
      if (i < 0.0 || i >= N) continue;
      float base = (i + 1.0) * gap;
      float ph = i * p_phase + t * p_speed * TAU;
      float a = amp * gap * 3.0;
      float xx = uv.x * A * p_freq;
      float f = a * (sin(xx + ph) + p_detail * 0.35 * sin(xx * 2.3 - ph * 1.7));
      float df = a * p_freq * A * (cos(xx + ph) + p_detail * 0.35 * 2.3 * cos(xx * 2.3 - ph * 1.7)) / A;
      float d = abs(y - base - f) / sqrt(1.0 + df * df);
      float line = 1.0 - smoothstep(w - px, w + px, d);
      float glow = p_glow * w * w / (d * d + w * w) * 0.5;
      vec3 lc = p_spectrum > 0.5 ? spectral(i / max(N - 1.0, 1.0)) : tint;
      col += lc * (line + glow);
    }
  } else {
    // Scope: a phosphor trace (fundamental plus harmonics) over a grid.
    vec2 g = abs(fract(vec2(uv.x * A * 8.0 / A, uv.y * 8.0)) - 0.5);
    float grid = 1.0 - smoothstep(0.0, px * 8.0 * 1.5, 0.5 - max(g.x, g.y));
    col = tint * grid * 0.12;
    col += tint * (1.0 - smoothstep(px, px * 3.0, abs(uv.y - 0.5))) * 0.15;
    for (int j = 0; j < 4; j++) {
      float i = float(j);
      if (i >= N) break;
      float ph = t * p_speed * TAU * (1.0 + i * 0.5) + i * p_phase;
      float xx = uv.x * TAU * p_freq * 0.25;
      float f = 0.0, df = 0.0;
      for (int h = 1; h <= 4; h++) {
        float fh = float(h);
        float ah = pow(p_detail, fh - 1.0) / fh;
        f += ah * sin(xx * fh + ph * fh);
        df += ah * fh * cos(xx * fh + ph * fh);
      }
      f *= amp * 0.3; df *= amp * 0.3 * TAU * p_freq * 0.25;
      float d = abs(uv.y - 0.5 - f) / sqrt(1.0 + df * df);
      float line = 1.0 - smoothstep(w - px, w + px, d);
      float glow = p_glow * w * w / (d * d + w * w);
      vec3 lc = p_spectrum > 0.5 ? spectral(i / max(N - 1.0, 1.0)) : tint;
      col += lc * (line + glow * 0.6) * (1.0 - 0.2 * i);
    }
  }
  return (1.0 - exp(-col * 1.5)) * (0.85 + 0.15 * k);
}
