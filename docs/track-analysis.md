# Track analysis and drop detection

**Status: not done.** The show engine needs to know, ahead of time, where each track's breakdowns, builds and drops are. What we have works on some tracks and is wrong on others, and it has only been checked by eye on a handful. This page says what exists, where it fails, and how we'll get it right, measured rather than assumed.

## Why it matters

The lights build suspense into a drop and hit it on the beat ([show-engine.md](show-engine.md#scene-flow-state-machine)). A drop called too early fires the big look while the track is still building (and then there's nothing left for the real drop); a missed drop just plays as a groove. Wrong is worse than missed.

## What exists today

There are three separate pieces, and they don't share logic yet.

| Where | Used for | How | Reads rekordbox phrases? |
|---|---|---|---|
| `brain/deckdash/Timeline.java` | **The real decks** (live shows) | Waveform only: bass and energy per bar from the player's detailed waveform. A breakdown is 4+ bars with normalised bass under 0.30. A drop is a 4- or 8-bar phrase boundary (counted from the beat-in) where the next 4 bars carry ≥1.6× the bass of the previous 8 (2.24× off the 8-bar grid), refined to the beat where bass returns. A hot cue or memory point within a bar raises its confidence. | **No.** [show-engine.md](show-engine.md#track-timeline-computed-when-a-track-loads) describes phrases as the first source; that's the design, not the code. |
| `brain/showbrain/showbrain.py` (Commander) | Fixing individual tracks live | **Mark drop here** / **skip drop** in the Commander, saved per track in `overrides.json` and used next time. | n/a |
| `brain/sim/realtracks.py` | **Simulation** with the DJ's own tracks | rekordbox phrases (PSSI) when the track has them; otherwise a crude 8-bar rule on the 3-band waveform's bass. | **Yes**, when present. |

## Evidence so far

Checked by eye only. No systematic test has been run.

| Track | Method | Result |
|---|---|---|
| Dennis Cruz – Five (Original Mix) | Timeline.java | Drop at bar 105 correct (2026-09-26) |
| Sonique, Matt Sassari, Hugel – It Feels So Good (Extended Mix) | Timeline.java | Drops at 57 and 113 correct |
| Patrick Topping – Be Sharp Say Nowt | rekordbox phrases (sim) | Correct: build 5–20, drop 21, breakdown 69–84, build 85–100, drop 101 |
| FISHER, Kita Alexander – Atmosphere | rekordbox phrases (sim) | Not checked yet |
| **Dombresky – Simple Hit** | bass rule (sim) | **Wrong:** marked a drop while the track was still building (2026-09-29) |
| Mark Knight, James Hurr – You Take Me Higher | bass rule (sim) | Not checked yet |

Two correct tracks from the live analyser and one clear failure from the fallback is not evidence that either works.

## Where the waveform approach goes wrong

Expected failure modes (the first is the one we've seen):

- **Builds that keep the bass**: risers, snare rolls and filtered basslines carry low end, so "bass came back" can fire inside the build. That's the Dombresky case.
- **Drops without a bass change**: in tech house the drop is often the same groove with the bass line or percussion arriving, not bass returning from nothing.
- **Tracks whose intro has bass**: no low-bass stretch before the first drop, so no drop is found, or the beat-in is taken as the drop.
- **Many candidates**: psytrance and minimal have bass nearly throughout; bass dips give false drops.
- **Off-grid phrasing**: drops not on 4/8-bar boundaries from the beat-in, or a wrong beat grid, put the drop a bar or more out.
- **The fallback in the sim** works on 8-bar blocks from the first downbeat with fixed thresholds, so it can't place a drop inside a block and misreads builds.

## What rekordbox already gives us

On the DJ's USB (JC-A, 1,033 tracks, 2026-09-29):

- **459 tracks (44%) have phrase analysis** (PSSI: Intro / Up / Down / Chorus / Outro at exact beats, for "high mood" tracks). 458 of them have a chorus, i.e. a drop. rekordbox 6 masks this data; `realtracks.py` unmasks it.
- **1,032 have the 3-band waveform** (PWV7: low / mid / high per 1/150 s), much better input than the single-band waveform the live analyser uses.
- Turning on phrase analysis in rekordbox (**Preferences → Analysis → Track Analysis Setting → Phrase**, then re-analyse and re-export) would label the other 56%.

## Plan

1. **Test set.** Take the 459 phrase-analysed tracks as labelled data: rekordbox's drops, builds and breakdowns are the reference. Spot-check a sample by ear, since rekordbox is also sometimes wrong. Keep the labels and analysis files private (outside git, like the sim tracks); commit only the evaluation code.
2. **Measure.** An offline harness runs each analyser over the test set's analysis files (no decks needed) and reports, per method: drops found within ±1 bar (recall), drops that aren't drops (false drops), and section accuracy. Results go in this page, per change, so we can see if a change helps.
3. **Use phrases on the real decks.** When the loaded track has phrases, Timeline.java uses them first (beat-link can fetch the PSSI tag from the player), with the waveform as the fallback. Then the doc claim becomes true.
4. **A better fallback for the rest.** Rebuild the waveform analyser on the 3-band waveform, with the thresholds fitted on the test set, not guessed. Share one implementation between the live decks and the sim.
5. **Learn from the Commander.** Every "mark drop" / "skip drop" is a labelled mistake: log them with the track and feed them into the test set.
6. **Done means measured.** For example: at least 90% of drops within a bar, and under 10% false drops, on the test set, for tracks without phrases. Until a number like that is met and written here, this page's status stays "not done".

Related: [show-engine.md](show-engine.md) (how the show uses the timeline), [sim.md](sim.md#your-own-tracks) (real tracks in the simulation).
