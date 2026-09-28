// Sektor5 simulation audio: a small house-music synth in the browser, played in time with the show.
//
// The synthetic rig (simulation mode) has no audio, only structure: tempo, beats, sections, drops.
// This plays music that follows it, driven by showbrain's /api/state (beat, bpm, scene, beats to the
// drop), so what you hear lines up with the lights: kick, hats, clap and bassline in grooves and
// drops; the kick drops out and a pad plays in breakdowns; a filter sweep, riser and snare roll in
// builds; a beat of silence before the drop. Nothing is recorded or licensed: it's all synthesised.
//
// Real tracks: when the simulated decks play the DJ's own tracks (brain/sim/realtracks.py), their
// actual audio plays instead of the synth, one player per deck, following its position, pitch,
// fader and bass EQ (the sim's mix) from the dashboard's /api/state.
//
// Loaded on demand by s5system.js (Sound in the SIM panel). window.S5AUDIO.
(() => {
  "use strict";
  if (window.S5AUDIO) return;
  const STATE = window.S5AUTH && S5AUTH.url ? S5AUTH.url(8090, "/api/state") : "/api/state";
  let ctx = null, master = null, music = null, musicLP = null, noiseBuf = null, pollTimer = null, schedTimer = null;
  let clock = null;          // { a0: audio time, b0: beat at a0, bpm }
  let show = { scene: "GROOVE", bpm: 126, beats_to_drop: 999, energy: 0.6, section: "groove" };
  let nextStep = null;                                          // next 16th to schedule, in beats (multiples of 0.25)
  let vol = +(localStorage.getItem("s5simVol") || 0.8);
  const LOOKAHEAD = 0.15, STEP = 0.25;
  const KEY = 55;            // A1: bassline root (A minor)
  const BASS = [0, 0, 12, 0, 7, 0, 10, 12];   // semitones, one per 8th note of the bar
  const PAD = [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 55, 59]];   // Am, F, G, Em (MIDI), one per bar

  const hz = m => 440 * Math.pow(2, (m - 69) / 12);

  function build() {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.ratio.value = 4; comp.attack.value = 0.003; comp.release.value = 0.2;
    master = ctx.createGain(); master.gain.value = vol;
    master.connect(comp).connect(ctx.destination);
    musicLP = ctx.createBiquadFilter(); musicLP.type = "lowpass"; musicLP.frequency.value = 18000; musicLP.Q.value = 0.8;
    music = ctx.createGain(); music.gain.value = 1;
    music.connect(musicLP).connect(master);
    deckBus = ctx.createGain(); deckBus.gain.value = vol; deckBus.connect(ctx.destination);   // real tracks skip the synth's compressor
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }

  // ---------------------------------------------------------------- voices
  function kick(t, vel = 1) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.setValueAtTime(160, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.12);
    g.gain.setValueAtTime(vel, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.38);
    o.connect(g).connect(master); o.start(t); o.stop(t + 0.4);
  }
  function noise(t, dur, type, freq, vel, q = 1, dest = music) {
    const s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = noiseBuf; f.type = type; f.frequency.value = freq; f.Q.value = q;
    g.gain.setValueAtTime(vel, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    s.connect(f).connect(g).connect(dest); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
  }
  const hat = (t, vel = 0.18) => noise(t, 0.05, "highpass", 8000, vel);
  const openHat = (t, vel = 0.14) => noise(t, 0.22, "highpass", 7000, vel);
  const clap = (t, vel = 0.35) => { noise(t, 0.16, "bandpass", 1500, vel, 0.8); noise(t + 0.012, 0.12, "bandpass", 1800, vel * 0.7, 0.8); };
  const snare = (t, vel) => noise(t, 0.09, "bandpass", 2200, vel, 0.7, master);
  function bass(t, midiOffset, dur, vel = 0.32) {
    const o = ctx.createOscillator(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    o.type = "sawtooth"; o.frequency.value = KEY * Math.pow(2, midiOffset / 12);
    f.type = "lowpass"; f.frequency.setValueAtTime(900, t); f.frequency.exponentialRampToValueAtTime(180, t + dur); f.Q.value = 6;
    g.gain.setValueAtTime(vel, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(f).connect(g).connect(music); o.start(t); o.stop(t + dur + 0.02);
  }
  function pad(t, chord, dur, vel = 0.07) {
    for (const m of chord) for (const det of [-6, 6]) {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = "sawtooth"; o.frequency.value = hz(m); o.detune.value = det;
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vel, t + dur * 0.3);
      g.gain.linearRampToValueAtTime(0.0001, t + dur);
      o.connect(g).connect(music); o.start(t); o.stop(t + dur + 0.05);
    }
  }
  function riser(t, dur, vel = 0.16) {
    const s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = noiseBuf; s.loop = true; f.type = "bandpass"; f.Q.value = 2;
    f.frequency.setValueAtTime(400, t); f.frequency.exponentialRampToValueAtTime(9000, t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vel, t + dur);
    s.connect(f).connect(g).connect(master); s.start(t); s.stop(t + dur);
  }

  // ---------------------------------------------------------------- one 16th step
  const timeOf = beat => clock.a0 + (beat - clock.b0) * 60 / clock.bpm;
  let riserUntil = 0;
  function step(beat, t) {
    // beat 1 is the downbeat: pos is 0-4 within the bar, s16 the 16th step (0-15)
    const sc = show.scene, pos = (((beat - 1) % 4) + 4) % 4, s16 = Math.round(pos * 4) % 16, onBeat = s16 % 4 === 0, spb = 60 / clock.bpm;
    const toDrop = show.beats_to_drop - (beat - show._beat);   // beats to the drop at this step
    const e = Math.max(0.3, Math.min(1, show.energy || 0.6));
    // Filter: open in grooves and drops, dark in breakdowns, sweeping open through a build.
    let cut = 18000;
    if (sc === "BREAKDOWN" || sc === "INTRO" || sc === "OUTRO") cut = sc === "BREAKDOWN" ? 700 : 3500;
    if (sc === "BUILD" || sc === "HOLD") cut = 500 + 12000 * Math.pow(Math.max(0, 1 - toDrop / 32), 2);
    musicLP.frequency.setTargetAtTime(cut, t, 0.08);
    if (sc === "PAUSED" || sc === "IDLE") return;
    if (sc === "PREDROP") return;                                // the beat of silence before the drop
    const drop = sc === "DROP";
    const kickOn = sc === "GROOVE" || drop || sc === "OUTRO" || (sc === "INTRO" && e > 0.35) || sc === "HOLD";
    if (onBeat && kickOn) kick(t, drop ? 1 : 0.85);
    if (sc === "BUILD" || sc === "HOLD") {
      // Snare roll: quarters, then 8ths, then 16ths into the drop; a riser over the last 16 beats.
      const every = toDrop > 16 ? 4 : toDrop > 8 ? 2 : 1;
      if (s16 % every === 0) snare(t, 0.12 + 0.3 * Math.max(0, 1 - toDrop / 32));
      if (toDrop <= 16 && toDrop > 1 && t > riserUntil) { const dur = (toDrop - 1) * spb; riser(t, dur); riserUntil = t + dur; }
      if (onBeat && toDrop > 8) kick(t, 0.6);
    }
    const groove = sc === "GROOVE" || drop || sc === "OUTRO";
    if (groove || sc === "INTRO") {
      if (s16 % 4 === 2) openHat(t, drop ? 0.16 : 0.12);           // offbeat open hat: the house "tss"
      else if (s16 % 2 === 1 && e > 0.5) hat(t, 0.08);
    }
    if (groove && (s16 === 4 || s16 === 12)) clap(t, drop ? 0.4 : 0.3);
    if ((groove || sc === "BUILD") && s16 % 2 === 0 && s16 % 4 !== 0) {   // offbeat 8th bassline
      bass(t, BASS[(s16 / 2) | 0], spb * 0.45, drop ? 0.36 : 0.28);
    }
    if ((sc === "BREAKDOWN" || sc === "INTRO") && s16 === 0) {
      pad(t, PAD[Math.floor((beat - 1) / 4) % 4], spb * 4, sc === "BREAKDOWN" ? 0.07 : 0.04);
    }
  }

  // ---------------------------------------------------------------- clock and scheduler
  async function poll() {
    const sent = ctx.currentTime;
    try {
      const r = await fetch(STATE, { cache: "no-store" });
      const d = await r.json();
      const now = ctx.currentTime, at = (sent + now) / 2;            // best guess at when it was sampled
      const bpm = d.bpm > 0 ? d.bpm : 126, beat = d.beat || 0;
      show = { ...d, _beat: beat };
      if (!clock || Math.abs(bpm - clock.bpm) > 0.01) {
        clock = { a0: at, b0: beat, bpm };
        nextStep = Math.ceil((beat + (now - at) * bpm / 60) / STEP) * STEP;
      } else {
        const predicted = clock.b0 + (at - clock.a0) * bpm / 60, err = beat - predicted;
        if (Math.abs(err) > 0.5) {                                      // a jump (seek, new track): resync
          clock = { a0: at, b0: beat, bpm };
          nextStep = Math.ceil((beat + (now - at) * bpm / 60) / STEP) * STEP;
        } else {
          clock.b0 += err * 0.15;                                       // nudge gently: no audible jumps
        }
      }
    } catch (e) { /* showbrain unreachable: keep the last clock */ }
  }
  // ---------------------------------------------------------------- real tracks (per deck)
  const DECKS = window.S5AUTH && S5AUTH.url ? S5AUTH.url(8080, "/api/state") : "/api/state";
  const AUDIO = path => (window.S5AUTH && S5AUTH.url ? S5AUTH.url(8080, path) : path);
  const decks = {};          // deck number -> { el, src, low, gain, url, ready }
  let real = false, deckTimer = null, deckBus = null;
  function deck(n) {
    if (decks[n]) return decks[n];
    const el = new Audio(); el.preload = "auto"; el.preservesPitch = false; el.mozPreservesPitch = false; el.webkitPreservesPitch = false;
    const src = ctx.createMediaElementSource(el), low = ctx.createBiquadFilter(), gain = ctx.createGain();
    low.type = "lowshelf"; low.frequency.value = 200; gain.gain.value = 0;
    src.connect(low).connect(gain).connect(deckBus);
    return (decks[n] = { el, low, gain, url: null, ready: false });
  }
  async function loadDeck(d, url) {
    d.url = url; d.ready = false; d.el.pause();
    try {
      const blob = await (await fetch(AUDIO(url))).blob();            // whole file: seeking then needs no range requests
      if (d.url !== url) return;
      if (d.el.src) URL.revokeObjectURL(d.el.src);
      d.el.src = URL.createObjectURL(blob);
      await new Promise(ok => { d.el.oncanplay = ok; d.el.onerror = ok; });
      d.ready = true;
    } catch (e) { d.url = null; }
  }
  async function deckPoll() {
    let st;
    const t0 = performance.now();
    try { st = await (await fetch(DECKS, { cache: "no-store" })).json(); } catch (e) { return; }
    const lag = (performance.now() - t0) / 2000;                     // seconds since the position was sampled
    let any = false;
    for (const p of st.players || []) {
      const url = p.track && p.track.audio;
      if (!url) { if (decks[p.number]) { decks[p.number].el.pause(); decks[p.number].gain.gain.value = 0; } continue; }
      any = true;
      const d = deck(p.number);
      if (d.url !== url) { loadDeck(d, url); continue; }
      if (!d.ready || !p.position) continue;
      const rate = 1 + (p.status.pitchPct || 0) / 100, want = p.position.ms / 1000 + (p.status.playing ? lag * rate : 0);
      const fader = p.sim ? p.sim.fader : p.status.onAir ? 1 : 0, bass = p.sim ? p.sim.bass : 1;
      d.gain.gain.setTargetAtTime(fader, ctx.currentTime, 0.08);
      d.low.gain.setTargetAtTime(-26 * (1 - bass), ctx.currentTime, 0.15);   // the sim's bass swap
      if (!p.status.playing) { if (!d.el.paused) d.el.pause(); continue; }
      // Drift, smoothed over a few readings (each one has network jitter in it). Within 40 ms: play at the
      // deck's exact pitch; beyond: nudge the speed by at most 0.5% (inaudible); over 200 ms: jump back.
      const drift = d.el.currentTime - want;
      d.drift = d.drift === undefined ? drift : d.drift * 0.7 + drift * 0.3;
      if (d.el.paused || Math.abs(drift) > 0.2) {
        d.el.currentTime = Math.max(0, want); d.el.playbackRate = rate; d.drift = 0;
        if (d.el.paused) d.el.play().catch(() => {});
      } else if (Math.abs(d.drift) > 0.04) d.el.playbackRate = rate * (1 - Math.max(-0.005, Math.min(0.005, d.drift * 0.1)));
      else d.el.playbackRate = rate;
    }
    real = any;
    music.gain.setTargetAtTime(real ? 0 : 1, ctx.currentTime, 0.1);     // the synth steps aside for real tracks
  }

  function schedule() {
    if (!clock || real) return;
    const until = ctx.currentTime + LOOKAHEAD;
    for (let guard = 0; guard < 64; guard++) {
      const t = timeOf(nextStep);
      if (t > until) break;
      if (t >= ctx.currentTime - 0.01) step(nextStep, Math.max(t, ctx.currentTime));
      nextStep += STEP;
    }
  }

  async function start() {
    if (!ctx) build();
    await ctx.resume();
    // Unlock both decks' players inside this tap (phones only let media start from a user gesture).
    for (const n of [1, 2]) { const d = deck(n); d.el.muted = true; d.el.play().catch(() => {}); d.el.pause(); d.el.muted = false; }
    master.gain.setTargetAtTime(vol, ctx.currentTime, 0.05);
    deckBus.gain.setTargetAtTime(vol, ctx.currentTime, 0.05);
    await poll(); await deckPoll();
    clearInterval(pollTimer); clearInterval(schedTimer); clearInterval(deckTimer);
    pollTimer = setInterval(poll, 250);
    schedTimer = setInterval(schedule, 25);
    deckTimer = setInterval(deckPoll, 250);
  }
  function stop() {
    clearInterval(pollTimer); clearInterval(schedTimer); clearInterval(deckTimer); pollTimer = schedTimer = deckTimer = null;
    for (const d of Object.values(decks)) d.el.pause();
    if (ctx) { master.gain.setTargetAtTime(0, ctx.currentTime, 0.05); deckBus.gain.setTargetAtTime(0, ctx.currentTime, 0.05); setTimeout(() => ctx && ctx.suspend(), 300); }
    clock = null;
  }
  function volume(v) {
    vol = Math.max(0, Math.min(1, v));
    if (ctx && schedTimer) { master.gain.setTargetAtTime(vol, ctx.currentTime, 0.05); deckBus.gain.setTargetAtTime(vol, ctx.currentTime, 0.05); }
  }
  // For checking sync: each deck player's position, rate and volume.
  const decksInfo = () => Object.fromEntries(Object.entries(decks).map(([n, d]) => [n, { t: +d.el.currentTime.toFixed(3), paused: d.el.paused,
    rate: +d.el.playbackRate.toFixed(4), vol: +d.gain.gain.value.toFixed(2), ready: d.ready }]));
  window.S5AUDIO = { start, stop, volume, get real() { return real; }, get decks() { return decksInfo(); }, get playing() { return !!(ctx && ctx.state === "running" && schedTimer); } };
})();
