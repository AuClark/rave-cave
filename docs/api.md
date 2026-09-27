# Dashboard API (deckdash, port 8080)

The data the brain exposes for the dashboard front end. Served by `deckdash` on the brain: `http://ravecave.local:8080`. Every response sends `Access-Control-Allow-Origin: *`, so a page on any origin (a laptop, `/preview/`) can use it.

Ownership: the **front end** (the page) is Richard's. The **data behind it** (these endpoints, the fixtures, the services) is maintained by the rig side. If you need something that isn't here, ask for it in an issue or PR. Fields are only ever added, not renamed or removed, without warning.

## Endpoints

| Endpoint | Returns |
|---|---|
| `GET /api/state` | Full snapshot (JSON), described below |
| `GET /api/events` | Server-Sent Events: the same snapshot pushed about 10× per second as `data: {...}` lines. Use `new EventSource(url)`. |
| `GET /api/timeline/N` | Read-ahead timeline for player N's loaded track: sections, predicted drops, per-bar energy and bass, beat times. `404` until analysed. |
| `GET /api/wavedetail/N` | Detailed colour waveform for player N as binary: 150 frames/s, 4 bytes per frame (height 0-31, r, g, b). Header `X-Wave-Key` identifies the track. |
| `GET /api/waveform/N` | Waveform preview (1200 segments) as JSON: `heights`, `colors`, `maxHeight` |
| `GET /api/art/N` | Album art for player N (JPEG), `404` if none |
| `GET /` | The live page (`/srv/rave/deckdash-web/index.html`) |
| `GET /preview/…` | The preview page and any files beside it (`/srv/rave/deckdash-preview/`) |

## `/api/state`

Top level: `now` (ms epoch), `uptimeSec`, `self`, `master`, `devices`, `media`, `mixer`, `show`, `players`.

### `self`, `master`, `devices`, `media`

| Field | Meaning |
|---|---|
| `self.deviceNumber`, `self.name`, `self.address` | The brain on the DJ Link network (virtual player 7) |
| `master.player`, `master.name`, `master.bpm` | The current tempo master and its BPM |
| `devices[]` | Every DJ Link device: `number`, `name`, `address`, `mac`, `seenMsAgo` |
| `media[]` | Mounted rekordbox media: `player`, `slot`, `name`, `created`, `tracks`, `playlists`, `totalBytes`, `freeBytes`, `type` |

### `players[]` (one per deck)

| Field | Meaning |
|---|---|
| `number`, `name`, `address`, `firmware` | Deck identity |
| `status.playing`, `paused`, `cued`, `looping`, `searching`, `atEnd`, `reverse` | Play state flags |
| `status.tempoMaster`, `synced`, `bpmSynced`, `onAir` | Sync state. `onAir` needs a DJ Link mixer, so it's always false here. |
| `status.trackBpm`, `pitchPct`, `effectiveBpm` | Track BPM, pitch fader %, the resulting live BPM |
| `status.beatWithinBar` (1-4), `beatNumber` | Beat position |
| `status.playState1/2/3`, `cueCountdown`, `loopBeats` | Raw player state |
| `status.rekordboxId`, `trackSourcePlayer`, `trackSourceSlot`, `trackType` | Where the loaded track comes from |
| `beat.msSinceLast`, `beat.count` | Time since this deck's last beat packet (flash on < 120 ms), beats seen |
| `position.ms`, `definitive`, `precise` | Playhead position in the track |
| `track.title`, `artist`, `album`, `genre`, `key` (Camelot), `label`, `remixer`, `comment`, `durationSec`, `bpm`, `rating`, `year`, `bitRate`, `dateAdded`, `color`, `colorHex`, `ref` | rekordbox metadata (`track` is absent until loaded) |
| `track.cues[]` | Hot cues and memory points: `hotCue` (0 = memory point, 1 = A…), `loop`, `ms`, `loopMs`, `comment`, `color` |
| `grid.beats`, `grid.bar`, `grid.bars` | Beat grid: total beats, current bar, total bars |
| `hasArt`, `waveformKey`, `timelineKey` | Whether art is available; keys that change when the track changes (use them to refetch waveform or timeline) |

### `mixer` (DJM-450 over USB)

From the `mixer` service. `connected: false` when the mixer isn't plugged in.

| Field | Meaning |
|---|---|
| `connected`, `model`, `ts` | Status, model, message time (ms epoch) |
| `channels.ch1`, `channels.ch2` | **Post-fader** audio level for each mixer channel, which moves with the channel fader: `rms_db`, `peak_db`, `peak_hold_db` (dBFS; around -70 or lower = silent), `active` |
| `channels.master` | The master mix (Rec Out), same fields |
| `share.ch1`, `share.ch2` | Each channel's share of the mix right now (0-1, sums to 1 when anything is playing): which deck is actually audible |
| `midi.count`, `midi.recent[]` | MIDI from the mixer (`{t, hex}`). The DJM-450 sends none in standalone use so far. |

Mixer channel 1 is fed by deck 1 and channel 2 by deck 2.

### `show` (scene engine)

From `showbrain`. `null` if the show engine isn't running.

| Field | Meaning |
|---|---|
| `scene` | `IDLE`, `INTRO`, `GROOVE`, `BREAKDOWN`, `BUILD`, `HOLD`, `PREDROP`, `DROP`, `OUTRO`, `PAUSED` |
| `live` | The deck the lights are following. `follow` is 0 for auto, or a locked deck number. |
| `title`, `bpm`, `hue` (0-1, from the track's key) | Live deck's track, tempo and colour |
| `bar`, `bwb` (beat in bar), `beat` (fractional), `frac` (0-1 phase within the beat) | Beat clock |
| `section`, `section_progress` (0-1), `energy` (0-1 for this bar) | Where the live track is |
| `beats_to_drop`, `next_drop_bar`, `drops[]` (`{bar, manual}`) | Upcoming drops (`manual` = marked in the Commander) |
| `progress` (0-1), `since_drop` (beats) | Build progress; beats since the drop |
| `mode`, `hold`, `strobe`, `forced`, `intensity` (0-1), `lead_ms` | Commander state |
| `fixtures[]`, `dmx` | Active fixtures and DMX adapter status |
| `fps`, `phase_err_ms`, `calibration` | Engine health: frame rate, beat-clock error vs the decks, drop-prediction calibration |

## `/api/timeline/N`

```json
{ "ref": "...", "title": "...", "bars": 183, "beats": 732, "beatInBar": 1, "outroBar": 177,
  "drops":    [{ "bar": 97, "gridBar": 97, "beat": 385, "ms": 185000, "lift": 4.0, "confidence": 0.95,
                 "cue": false, "buildStartBar": 93, "buildStartBeat": 369 }],
  "sections": [{ "type": "groove", "startBar": 1, "endBar": 92, "startBeat": 1, "endBeat": 368 }],
  "energy": [0-100 per bar], "bass": [0-100 per bar],
  "barFirstBeat": [beat number of each bar's first beat], "beatMs": [time of every beat in ms] }
```

Section types: `intro`, `groove`, `breakdown`, `build`, `drop`, `outro`. To place anything on the timeline, convert beats to time with `beatMs[beat - 1]`.

## Example

```js
const API = "http://ravecave.local:8080";
const es = new EventSource(`${API}/api/events`);
es.onmessage = e => {
  const st = JSON.parse(e.data);
  const live = st.players.find(p => p.number === st.show?.live);
  console.log(st.show?.scene, live?.track?.title, st.mixer?.share);
};
```
