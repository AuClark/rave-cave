"""Scene looks, vectorised with numpy. Every function returns float RGB in 0..1.

Strips are 1-D (index 0 = bottom of the tube); the panel is 2-D (H x W).
`ctx` comes from Engine.decide(); `role` holds per-fixture variation:
  offset  beats to shift this fixture's clock (0.5 = off-beat partner)
  flip    swap the two-colour alternation in DROP / groove accents
  index   position in the fixture group (comet hand-off between tubes)
  group   number of fixtures sharing the hand-off
"""
import math

import numpy as np

rng = np.random.default_rng()


def hsv(h, s, v):
    """Vectorised HSV -> RGB. h, s, v broadcast; returns (..., 3)."""
    h = np.asarray(h, dtype=np.float32) % 1.0
    s = np.clip(np.asarray(s, dtype=np.float32), 0, 1)
    v = np.clip(np.asarray(v, dtype=np.float32), 0, 1)
    h, s, v = np.broadcast_arrays(h, s, v)
    i = np.floor(h * 6).astype(np.int32) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], axis=-1)


def lerp(a, b, t):
    t = np.asarray(t, dtype=np.float32)
    if t.ndim:
        t = t[..., None]
    return a + (b - a) * t


def clock(ctx, role):
    """(frac, bwb, beat) for this fixture, shifted by role offset in beats."""
    beat = ctx["beat"] + role.get("offset", 0.0)
    if ctx.get("bar", 0) == 0:            # no timeline: use beat-event phase
        frac = (ctx["frac"] + role.get("offset", 0.0)) % 1.0
        return frac, ctx["bwb"], beat
    return beat % 1.0, ((int(beat) - 1) % 4) + 1 if beat >= 1 else ctx["bwb"], beat


# ---------------------------------------------------------------- strips

def strip(ctx, n, role, state):
    s, hue = ctx["scene"], ctx["hue"]
    x = np.linspace(0, 1, n, dtype=np.float32)
    frac, bwb, beat = clock(ctx, role)
    kick = math.exp(-6 * frac)
    flip = 0.5 if role.get("flip") else 0.0

    if s == "INTRO":
        v = 0.08 + 0.12 * (0.5 + 0.5 * math.sin(2 * math.pi * beat / 8))
        return hsv(hue + x * 0.1, 0.8, v)

    if s in ("GROOVE", "OUTRO", "PAUSED"):
        fade = {"OUTRO": 0.5, "PAUSED": 0.3}.get(s, 1.0)
        accent = 0.35 if (bwb == 1) != bool(role.get("flip")) and bwb in (1, 3) else 0.0
        base = hsv(hue + 0.03 * (ctx["bar"] % 4) + x * 0.05, 1.0, (0.12 + 0.7 * kick) * fade)
        out = lerp(base, np.full_like(base, (0.12 + 0.7 * kick) * fade), accent * kick)
        # Comet climbs the tubes once per bar, handed from one tube to the next.
        g = max(1, role.get("group", 1))
        bar_phase = ((bwb - 1) + frac) / 4
        local = bar_phase * g - role.get("index", 0)
        if 0 <= local <= 1.2:
            d = local * (n + 10) - np.arange(n)
            tail = np.where((d >= 0) & (d < 10), np.exp(-d / 3), 0)
            out = lerp(out, hsv(hue + 0.5, 0.6, fade)[None, :].repeat(n, 0), tail)
        return out

    if s == "BREAKDOWN":
        return strip_breakdown(ctx, n, role, state, x, beat)

    if s in ("BUILD", "HOLD"):
        p = ctx["progress"]
        rate = 1 if p < 0.5 else 2 if p < 0.75 else 4 if p < 0.9 else 8
        on = ((beat * rate) % 1.0) < 0.45
        fill = x <= (0.2 + 0.8 * p)
        col = lerp(hsv(hue, 1, 1), np.ones(3, np.float32), p * 0.8)
        v = (0.3 + 0.7 * p) if on else 0.04
        return np.where(fill[:, None], col * v, 0.0).astype(np.float32)

    if s == "PREDROP":
        return np.zeros((n, 3), np.float32)

    if s == "DROP":
        sd = ctx["since_drop"]
        if sd < 0.25:
            return np.ones((n, 3), np.float32)
        strobe = sd < 4 and ((sd * 2) % 1.0) > 0.5
        v = 0.0 if strobe else 0.35 + 0.65 * kick
        blocks = ((np.arange(n) // 6) + int(sd) + (1 if role.get("flip") else 0)) % 2
        return hsv(hue + 0.5 * blocks + flip * 0, 1.0, v)

    return np.zeros((n, 3), np.float32)


# ---------------------------------------------------------------- panel

def panel(ctx, w, h, role, state):
    s, hue = ctx["scene"], ctx["hue"]
    X, Y = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    frac, bwb, beat = clock(ctx, role)
    kick = math.exp(-6 * frac)

    if s == "INTRO":
        v = 0.06 + 0.1 * (0.5 + 0.5 * math.sin(2 * math.pi * beat / 8))
        return hsv(hue + X / w * 0.2, 0.8, v)

    if s in ("GROOVE", "OUTRO", "PAUSED"):
        fade = {"OUTRO": 0.5, "PAUSED": 0.3}.get(s, 1.0)
        v = (0.08 + 0.6 * kick * (1 - np.abs(Y - (h - 1) / 2) / (h * 0.62))) * fade
        out = hsv(hue + X / w * 0.15, 1.0, v)
        head = ((bwb - 1 + frac) / 4) * (w + 24)
        d = head - X
        comet = np.where((d >= 0) & (d < 24), np.exp(-d / 8), 0)
        return lerp(out, hsv(hue + 0.5, 0.5, fade) * np.ones_like(out), comet)

    if s == "BREAKDOWN":
        return panel_breakdown(ctx, w, h, role, state, X, Y, beat)

    if s in ("BUILD", "HOLD"):
        p = ctx["progress"]
        rate = 1 if p < 0.5 else 2 if p < 0.75 else 4 if p < 0.9 else 8
        on = ((beat * rate) % 1.0) < 0.45
        # Fill closes in from both ends toward the centre.
        reach = (0.15 + 0.85 * p) * w / 2
        mask = np.abs(X - (w - 1) / 2) >= (w / 2 - reach)
        col = lerp(hsv(hue, 1, 1), np.ones(3, np.float32), p * 0.8)
        v = (0.3 + 0.7 * p) if on else 0.03
        return np.where(mask[..., None], col * v, 0.0).astype(np.float32)

    if s == "PREDROP":
        return np.zeros((h, w, 3), np.float32)

    if s == "DROP":
        sd = ctx["since_drop"]
        if sd < 0.25:
            return np.ones((h, w, 3), np.float32)
        radius = (sd % 1.0) * w * 0.6
        ring = np.exp(-np.abs(np.abs(X - w / 2) - radius) / 4)
        base = hsv(hue + (0.5 if int(sd) % 2 else 0), 1.0, (0.3 + 0.7 * kick) * 0.5) * np.ones((h, w, 1), np.float32)
        return lerp(base, np.ones(3, np.float32), ring * 0.8)

    return np.zeros((h, w, 3), np.float32)


# ---------------------------------------------------------------- par can (single DMX fixture)

def par(ctx, role, state):
    """One RGB(W/A/UV) wash light. Returns dict of 0..1 values: dimmer, r, g, b, w, a, uv.
    W/A/UV are only used when the fixture config says those channels are verified."""
    s, hue = ctx["scene"], ctx["hue"]
    frac, bwb, beat = clock(ctx, role)
    kick = math.exp(-6 * frac)
    out = dict(dimmer=1.0, r=0.0, g=0.0, b=0.0, w=0.0, a=0.0, uv=0.0)

    def colour(h, s_=1.0, v=1.0):
        r, g, b = hsv(h, s_, v).tolist()
        out.update(r=r, g=g, b=b)

    if s == "IDLE":
        colour(ctx["t"] * 0.01, 0.9, 0.15)            # slow dim colour drift
    elif s == "INTRO":
        colour(hue, 0.8, 0.10 + 0.15 * (0.5 + 0.5 * math.sin(2 * math.pi * beat / 8)))
    elif s in ("GROOVE", "OUTRO", "PAUSED"):
        fade = {"OUTRO": 0.5, "PAUSED": 0.25}.get(s, 1.0)
        v = (0.18 + 0.82 * kick) * fade
        colour(hue + 0.03 * (ctx["bar"] % 4), 1.0, v)
        if bwb == 1:                                  # bar accent: push toward white
            out["w"] = 0.6 * kick * fade
            for k in ("r", "g", "b"):
                out[k] = min(1.0, out[k] + 0.35 * kick * fade)
    elif s == "BREAKDOWN":
        sp, en = ctx.get("section_progress", 0.0), ctx.get("energy", 0.5)
        mixc = 0.5 - 0.5 * math.cos(2 * math.pi * beat / 8)         # key -> complement over 2 bars
        half = 0.5 + 0.5 * math.cos(math.pi * (beat % 2))           # half-time breathe (peaks on 1 and 3)
        v = (0.10 + 0.25 * en + 0.2 * sp) * (0.45 + 0.55 * half)
        colour(hue + 0.5 * mixc, 0.55 + 0.4 * sp, v)
        out["uv"] = 0.4 + 0.3 * half
    elif s in ("BUILD", "HOLD"):
        p = ctx["progress"]
        rate = 1 if p < 0.5 else 2 if p < 0.75 else 4 if p < 0.9 else 8
        on = ((beat * rate) % 1.0) < 0.45
        v = (0.3 + 0.7 * p) if on else 0.0
        colour(hue, 1.0 - 0.85 * p, v)                # desaturates toward white as it builds
        out["w"] = p * v
    elif s == "PREDROP":
        pass                                          # blackout, the inhale
    elif s == "DROP":
        sd = ctx["since_drop"]
        if sd < 0.25:
            out.update(r=1.0, g=1.0, b=1.0, w=1.0)
        else:
            strobe = sd < 4 and ((sd * 2) % 1.0) > 0.5
            v = 0.0 if strobe else 0.35 + 0.65 * kick
            colour(hue + (0.5 if int(sd) % 2 else 0.0), 1.0, v)
            out["uv"] = 0.3
    return out


# ---------------------------------------------------------------- breakdown looks

def _eighth_ticks(state, beat):
    """Number of eighth-note boundaries crossed since the last frame (0, 1, occasionally 2)."""
    e = int(beat * 2)
    last = state.get("eighth")
    state["eighth"] = e
    return 0 if last is None or e < last or e - last > 4 else e - last


def strip_breakdown(ctx, n, role, state, x, beat):
    """Less is more (the tube diffuser makes a few LEDs glow): near-dark base, sparkles locked to
    the eighth notes (brighter on the beat), and one slow droplet per bar. Density and brightness
    rise with section progress so the breakdown leans into the build."""
    hue, sp, en = ctx["hue"], ctx.get("section_progress", 0.0), ctx.get("energy", 0.5)
    flip = 0.5 if role.get("flip") else 0.0
    half = 0.5 + 0.5 * math.cos(math.pi * (beat % 2))
    # Faint ember: a single soft glow near the bottom, breathing in half-time.
    ember = np.exp(-x * 6) * (0.03 + 0.05 * en + 0.04 * sp) * (0.4 + 0.6 * half)
    out = hsv(hue - 0.06 + flip * 0.25, 0.7, 1.0)[None, :] * ember[:, None]

    # Sparkles spawned exactly on eighth-note boundaries; decay measured in beats.
    sparks = state.setdefault("sparks", [])              # [pixel, spawn beat, strength]
    e = int(beat * 2)
    last = state.get("eighth")
    if last is not None and 0 < e - last <= 2:
        on_beat = e % 2 == 0
        count = (1 + int(2 * sp)) * (2 if on_beat else 1)
        strength = (0.9 if on_beat else 0.55) * (0.6 + 0.4 * en)
        for px in rng.integers(0, n, size=count):
            sparks.append([int(px), e / 2.0, strength])
    state["eighth"] = e
    sparks[:] = [sk for sk in sparks if beat - sk[1] < 0.5]
    for px, b0, st in sparks:
        v = st * math.exp(-(beat - b0) * 9)
        c = hsv(hue + 0.5 * ((px * 7) % 3 == 0) + flip * 0.2, 0.25, v)
        out[px] = np.maximum(out[px], c)

    # One droplet per bar, launched on the downbeat, falling over about 2 beats.
    bar_start = int((beat - 1) // 4)
    if state.get("drop_bar") != bar_start:
        state["drop_bar"] = bar_start
        state.setdefault("drops", []).append([bar_start * 4 + 1 + role.get("index", 0) * 0.5, hue + 0.5 + flip * 0.2])
    idx = np.arange(n, dtype=np.float32) / max(1, n - 1)
    keep = []
    for b0, dh in state.get("drops", []):
        pos = 1.05 - (beat - b0) * (0.5 + 0.3 * sp)
        if beat < b0:
            keep.append([b0, dh]); continue
        if pos < -0.3:
            continue
        keep.append([b0, dh])
        dist = idx - pos
        tail = np.exp(-np.abs(dist) * np.where(dist >= 0, 22.0, 80.0)) * (0.4 + 0.4 * sp)
        out = np.maximum(out, hsv(dh, 0.4, 1.0)[None, :] * tail[:, None])
    state["drops"] = keep
    return out


def panel_breakdown(ctx, w, h, role, state, X, Y, beat):
    """Two-colour plasma breathing in half-time, slanted rain streaks spawned on eighth notes,
    and a bright sweep across the panel every 2 bars."""
    hue, sp, en = ctx["hue"], ctx.get("section_progress", 0.0), ctx.get("energy", 0.5)
    half = 0.5 + 0.5 * math.cos(math.pi * (beat % 2))
    t = beat / 4
    plasma = 0.5 + 0.25 * np.sin(X / 11 + t * 1.3) + 0.25 * np.sin((X + Y * 3) / 17 - t * 0.9)
    level = (0.06 + 0.14 * en + 0.10 * sp) * (0.55 + 0.45 * half)
    out = hsv(hue - 0.05 + 0.5 * plasma * (0.35 + 0.3 * sp), 0.5 + 0.35 * sp, level * (0.5 + 0.8 * plasma))

    streaks = state.setdefault("streaks", [])           # [x, y, speed rows/beat, hue]
    for _ in range(_eighth_ticks(state, beat)):
        for _k in range(1 + int(3 * sp)):
            streaks.append([rng.random() * w, -2.0, 10 + 8 * rng.random() + 10 * sp, hue + 0.2 * rng.random()])
    dt = max(0.0, min(0.2, beat - state.get("last_beat", beat))) or 0.02
    state["last_beat"] = beat
    for st in streaks:
        st[1] += st[2] * dt
        st[0] += st[2] * dt * 0.35                       # slant
    streaks[:] = [st for st in streaks if st[1] < h + 6]
    for sx, sy, _, sh in streaks:
        d = sy - Y                                       # trail above the head
        across = np.abs(X - (sx - d * 0.35))
        m = np.where((d >= 0) & (d < 6) & (across < 0.8), np.exp(-d / 2.2), 0.0) * (0.45 + 0.4 * sp)
        out = np.maximum(out, hsv(sh, 0.3, 1.0) * m[..., None])
    # Sweep every 2 bars.
    ph = (beat / 8) % 1.0
    band = np.exp(-np.abs(X - ph * (w + 40) + 20) / 5) * (0.25 + 0.35 * sp)
    out = np.maximum(out, hsv(hue + 0.5, 0.4, 1.0) * band[..., None])
    return out
