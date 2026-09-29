# Playing the visuals live

A short guide to the Visuals page (`http://sektor5.local:8110/`) as an instrument. It is built to
be used on a tablet propped by the decks, with one hand, in the dark. For what the sketches
themselves do see [visuals.md](visuals.md); for how they react to the track see
[reactive.md](reactive.md).

There are two pages. **The Launchpad** (`/pad.html`) is the one to play from a phone: big pads,
nothing to aim at. **The full controls** (`/`) are for setting a look up and fencing it in. They
share the same state, so you can rig on one and play on the other, at the same time, on two devices.

---

# The Launchpad

`http://sektor5.local:8110/pad.html`. A phone-sized page of pads and a small preview. Sections
from the top:

| Section | |
|---|---|
| **Energy** | Calm / Groove / Drop — a whole new look at that energy. The fastest way to change everything. |
| **Effects** | Played on one parameter (named in the section heading, chosen under **MORE**). |
| **Hold** | Hit / Move / Change — pushes the track's grip on the picture to its maximum while held. |
| **Presets** | Tap to launch. The one playing is outlined. |
| **Desk** | ÷2 and ×2 halve and double every speed at once; Chase steps through the presets on its own; Panic goes back to the preset you launched. |

Each pad says what kind of thing it is:

- **HOLD** — it happens while your thumb is down and undoes itself when you let go.
- **TAP** — one shot.
- **LATCH** — on until you tap it again.

## The effects

All six act on the **one parameter** named in the Effects heading. Change which one under
**MORE → Effects act on**. By default it picks the sketch's own speed if it has one.

| Pad | |
|---|---|
| **Sweep ↑** / **Sweep ↓** | Hold and the value travels smoothly to the top (or bottom) of its range over the **sweep time**. Let go and it glides back where it came from. A fader move you can do with a thumb. |
| **Strobe** | Hold and the value chops between the ends of its range at the **strobe rate**, locked to the beat. |
| **Flash** | One shot: straight to the top, falling off over a beat. A bump. |
| **Flip** | Mirrors the value inside its range. Instant change of direction. |
| **Auto** | Latches ordinary automation on for that parameter — a sine at one bar. |

Sweeps and flashes run in beat time, so they take the same number of beats whatever the tempo. The
strobe is handed to the projector to work out per frame, because at 1/16 there are sixteen edges a
second and no amount of network traffic would keep that clean.

## Launch on: now, or on the beat

The **1 BAR** button in the top strip (also **MORE → Launch on**) decides *when* a pad takes
effect: **now**, or on the next **beat**, **bar**, **2 bars** or **4 bars**. With it on a bar, hit a
preset pad whenever you like during the bar and it lands on the 1. A queued pad fills up with
orange as the bar comes round — tap it again to cancel.

Effects and Hold pads ignore this and always act at once. They are played, not launched: a strobe
that waits for the bar is not a strobe.

## Behind MORE

Sketch, Launch on, which parameter the effects act on, strobe rate, sweep time, chase length,
**Macros** (the sketch's parameters as big sliders, one group at a time, showing their ranges), and
a switch for the preview if you would rather have the pads full height.

## From a laptop

The pad takes keys too: **Q W E** energy, **Z** sweep up, **X** sweep down, **C** strobe, **V**
flash, **B** flip, **1**–**8** presets, **space** freeze, **esc** panic. Hold the key for the held
ones.

---

# The full controls

## The three things you need to know

**1. Pick a look.** The **Sketch** menu chooses what is drawn. **Load** puts a preset up. The
arrow keys step through presets, and **1**–**9** jump straight to the first nine.

**Words.** The **Words** field (on the full controls, and in the pad's drawer) sets the text that
sketches which draw type will use — `wormhole` puts it round the rings of its tunnel. Separate up
to eight words with `|`, for example `ALL GLORY|TO THE|HYPNOTOAD`. It is saved with the preset.

**2. Q, W, E.** These are the same dice thrown at three energies, and they are the fastest way to
get somewhere good:

| Key | Button | What it gives you |
|---|---|---|
| **Q** | Calm | Slow, sparse, barely reacting. Something you can leave up through a breakdown. |
| **W** | Groove | A middle setting. Moving, not hectic. |
| **E** | Drop | Fast, dense, reacting hard. For when the track goes off. |

They never go outside the range you set on each slider (below), so once you have fenced a look in,
Q/W/E stay inside the fence. Anything the sketch marks as a frame-rate knob is left alone, and so
is anything it marks as identity — Hypnotoad's collar, Wormhole's Two tone — because a dice roll on
those does not give you a different look, it gives you a broken one.

Which means the dice are only as safe as the sketch's own ranges, and that is where the safety
actually lives. Where a sketch has something to protect, its sliders are scaled so that the *whole*
of every range is usable rather than just the middle: `wormhole` is the clearest case — travel tops
out at a ring a bar, spin at a turn every two bars, the type cannot be subdivided past four words to
a ring however the wedges divide it, and the smearing effects stop at a smear. So **E** on Wormhole
gives you a different tunnel, not an unreadable one, and there is no setting you have to remember to
avoid mid-set.

**3. One slider, three things.** Every parameter looks like this:

```
  Hue                                    0.580   [A]
  ────────────█──────▓▓▓▓▓▓▓▓▓▓▓▓▓──────────────
              ^          ^      ▲      ▲
           the value   the range, and its two arrows
```

- **The upright line** is the value. Drag anywhere along the top of the track to move it.
- **The orange band** is how far that value is allowed to go. Drag the small **▲ arrows** under
  the line to set its ends. Randomise, Q/W/E and automation all stay inside it.
- **The square outline** appears when the parameter is automating, and shows where it has got to.

Handling:

| Do this | Get that |
|---|---|
| Drag the upper part of the track | Set the value |
| Drag an ▲ arrow (lower part) | Set one end of the range |
| **Shift**-drag | Fine adjustment |
| Double-click | Back to the sketch's default |
| Scroll wheel | Nudge one step (Shift for a fraction of one) |

## Making things move on their own

Press **A** (or the **A** button on the row) and that parameter starts moving between the two ends
of its orange band, by itself, locked to the beat. The selected row shows its controls:

| Control | What it does |
|---|---|
| **rate** | How long one trip takes, in note values. **1/4** is one beat, **1/1** is a bar, **4/1** is four bars. **·** is dotted (half again as long), **T** is a triplet. |
| shape | sine, triangle, saw up, saw down, square, step (a new random each cycle), smooth (random, eased) |
| phase | Where in the cycle it starts. Offset two parameters and they move against each other. |
| **bar** | Restart the shape on every bar, so it always lands on the 1. |
| **Hz** | Free-run in Hz instead of following the beat. Useful for slow drifts that should not lock to the music. |
| **full** | Set the range back to the whole parameter. |

**Space** freezes every automation where it stands, and unfreezes it. The values hold, and carry
on from there — nothing jumps.

The movement is worked out on the projector itself, from the beat, so it stays exactly in time and
does not depend on the tablet keeping up or the Wi-Fi behaving.

## Keys

| Key | |
|---|---|
| **Q** / **W** / **E** | New look: calm / groove / full on |
| **←** / **→** | Previous / next preset |
| **1**–**9** | Preset slot |
| **↑** / **↓** | Select the parameter above / below |
| **[** / **]** | Nudge the selected parameter (Shift for fine) |
| **R** | Randomise inside every range. **Shift+R** puts it back. |
| **A** | Automation on/off for the selected parameter |
| **Space** | Freeze / unfreeze all automation |
| **M** (hold) | Selected parameter to its maximum while held, like a momentary effect button |
| **Esc** | Panic: back to the preset you loaded |
| **?** | The list, on screen |

Keys are ignored while you are typing in the preset name box.

## A way to work

1. Load a preset you like, or press **W**.
2. Find the two or three parameters that matter for that sketch and **fence them in**: drag the
   arrows so the band only covers values you are happy with on the big screen.
3. Press **Q**, **W**, **E** through the set. Because of the fences, all three stay usable.
4. Put automation on one slow thing (a hue, a spin) at **4/1** or **8/1** so the picture never
   sits still, and one fast thing at **1/4** if the track wants it.
5. **Save** the whole thing as a preset — the values, the ranges and the automation all go in.
6. If it gets away from you, **Esc**.

## Saving

**Save** writes the values, every range and every automation setting into the preset. Presets made
before automation existed still load; they come up with automation off and ranges wide open.

## If it looks wrong

- **Nothing moving:** check **Freeze** in the top bar is not lit, and that the beat dots are
  ticking. Without the show engine running there is a 120 BPM idle clock, so things still move.
- **Too much going on:** press **Q**, then narrow the bands on whatever is still too much.
- **Stuttering on the projector:** `cathedral` and `inkwell` cost several times what the flat
  sketches do. Their Steps and Detail are marked as frame-rate knobs and the randomisers leave
  them alone, so turn them down by hand — see [visuals.md](visuals.md#what-cathedral-and-inkwell-cost).
