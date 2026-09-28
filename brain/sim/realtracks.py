"""Real tracks for the synthetic rig: the DJ's own tracks with their rekordbox analysis.

Each track is a folder (see docs/sim.md): track.mp3, track.json (title, artist, bpm, key…) and the
rekordbox analysis files from the USB export (ANLZ0000.DAT / .EXT / .2EX). From those:
  - the beat grid (PQTZ): where every beat is, so the sim's decks run on the track's real grid;
  - phrases (PSSI, if rekordbox analysed them): intro / up / down / chorus / outro, the song's
    real structure. Without them, breakdowns and drops come from the bass (3-band waveform, PWV7):
    a drop is the bass coming back after a stretch without it, like the real analyser;
  - the colour detail waveform (PWV5), for the dashboard.

The folders are private (the DJ's music): they live on the brain in /srv/rave/sim/tracks, never in git.
"""
import json
import struct
from pathlib import Path

MASK = bytes([0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3, 0xE8, 0xE9, 0xF4, 0xE1])
PHRASE_KINDS = {1: {1: "intro", 2: "up", 3: "down", 5: "chorus", 6: "outro"},
                2: {1: "intro", 8: "bridge", 9: "chorus", 10: "outro", **{k: "verse" for k in range(2, 8)}},
                3: {1: "intro", 8: "bridge", 9: "chorus", 10: "outro", **{k: "verse" for k in range(2, 8)}}}
CAMELOT = {"C": "8B", "Am": "8A", "G": "9B", "Em": "9A", "D": "10B", "Bm": "10A", "A": "11B", "F#m": "11A", "Gbm": "11A",
           "E": "12B", "C#m": "12A", "Dbm": "12A", "B": "1B", "G#m": "1A", "Abm": "1A", "F#": "2B", "Gb": "2B", "D#m": "2A",
           "Ebm": "2A", "C#": "3B", "Db": "3B", "A#m": "3A", "Bbm": "3A", "G#": "4B", "Ab": "4B", "Fm": "4A", "D#": "5B",
           "Eb": "5B", "Cm": "5A", "A#": "6B", "Bb": "6B", "Gm": "6A", "F": "7B", "Dm": "7A"}


def tags(path):
    """The tagged sections of a rekordbox ANLZ file: {fourcc: bytes of the whole section}."""
    b = Path(path).read_bytes()
    off, out = struct.unpack(">I", b[4:8])[0], {}
    while off + 12 <= len(b):
        tag = b[off:off + 4].decode("latin1")
        length = struct.unpack(">I", b[off + 8:off + 12])[0]
        if length <= 0:
            break
        out[tag] = b[off:off + length]
        off += length
    return out


def beat_grid(tag):
    """PQTZ -> [(beat in bar 1-4, time ms)]."""
    n = struct.unpack(">I", tag[20:24])[0]
    return [(struct.unpack(">H", tag[24 + i * 8:26 + i * 8])[0], struct.unpack(">I", tag[28 + i * 8:32 + i * 8])[0]) for i in range(n)]


def phrases(tag):
    """PSSI -> [(grid beat number, kind)] (rekordbox 6+ masks the body)."""
    n = struct.unpack(">H", tag[16:18])[0]
    body = bytearray(tag[18:])
    if struct.unpack(">H", body[0:2])[0] > 20:
        m = bytes((x + n) & 0xFF for x in MASK)
        for i in range(len(body)):
            body[i] ^= m[i % len(m)]
    mood = struct.unpack(">H", body[0:2])[0]
    data, head = bytes(tag[:18]) + bytes(body), struct.unpack(">I", tag[4:8])[0]
    out = []
    for i in range(n):
        e = data[head + i * 24:head + (i + 1) * 24]
        beat, kind = struct.unpack(">HH", e[2:6])
        out.append((beat, PHRASE_KINDS.get(mood, {}).get(kind, "verse")))
    return out


def detail_rgbh(tag):
    """PWV5 (2 bytes per 1/150 s: rrr ggg bbb hhhhh xx) -> the sim's detail format: (height 0-31, r, g, b) x N."""
    head = struct.unpack(">I", tag[4:8])[0]
    n = struct.unpack(">I", tag[16:20])[0]
    out = bytearray(n * 4)
    for i in range(n):
        v = struct.unpack(">H", tag[head + i * 2:head + i * 2 + 2])[0]
        r, g, b, h = (v >> 13) & 7, (v >> 10) & 7, (v >> 7) & 7, (v >> 2) & 31
        out[i * 4:i * 4 + 4] = bytes((h, r * 36, g * 36, b * 36))
    return bytes(out)


def bands(tag):
    """PWV7 (3 bytes per 1/150 s: mid, high, low) -> (low, total) lists."""
    head = struct.unpack(">I", tag[4:8])[0]
    n = struct.unpack(">I", tag[16:20])[0]
    lo, tot = [], []
    for i in range(n):
        mid, high, low = tag[head + i * 3:head + i * 3 + 3]
        lo.append(low)
        tot.append(low + mid + high)
    return lo, tot


def per_bar(values, bar_start_ms, bars, bar_ms):
    out = []
    for b in range(bars):
        a, z = int((bar_start_ms + b * bar_ms) * 0.15), int((bar_start_ms + (b + 1) * bar_ms) * 0.15)
        seg = values[a:z] or [0]
        out.append(sum(seg) / len(seg))
    return out


def sections_from_phrases(ph, d0, bars):
    """rekordbox phrases -> the sim's sections [(type, start bar, end bar)]. A chorus straight after an
    'up' (the build) is a drop (its first 16 bars); other choruses and verses are grooves."""
    marks = []
    for beat, kind in ph:
        bar = max(1, (beat - 1 - d0) // 4 + 1)
        if marks and marks[-1][1] >= bar:
            continue
        marks.append((kind, bar))
    out, prev = [], None
    for i, (kind, s) in enumerate(marks):
        e = (marks[i + 1][1] - 1) if i + 1 < len(marks) else bars
        if e < s:
            continue
        typ = {"intro": "intro", "up": "build", "down": "breakdown", "bridge": "breakdown", "outro": "outro"}.get(kind, "groove")
        if kind == "chorus" and prev in ("up", "down"):
            out.append(("drop", s, min(e, s + 15)))
            if e > s + 15:
                out.append(("groove", s + 16, e))
        elif out and out[-1][0] == typ == "groove":
            out[-1] = ("groove", out[-1][1], e)          # one groove, not one per phrase
        else:
            out.append((typ, s, e))
        prev = kind
    return out


def sections_from_bass(bass, energy):
    """No phrases: 8-bar phrases from the first downbeat; low bass = breakdown, the phrase before bass
    returns = build, bass back after a breakdown = drop, the quiet start and end = intro and outro."""
    bars = len(bass)
    top = max(bass) or 1
    ph = [(s, min(bars, s + 7)) for s in range(1, bars + 1, 8)]
    lvl = [sum(bass[s - 1:e]) / max(1, e - s + 1) / top for s, e in ph]
    typ = ["groove" if v >= 0.55 else "breakdown" for v in lvl]
    for i in range(1, len(ph)):
        if typ[i] == "groove" and typ[i - 1] == "breakdown":
            typ[i] = "drop"
            typ[i - 1] = "build" if i >= 2 and typ[i - 2] == "breakdown" else typ[i - 1]
    i = 0
    while i < len(typ) and typ[i] != "drop" and i < 4 and lvl[i] < 0.8:
        typ[i] = "intro"; i += 1
    j = len(typ) - 1
    while j > 0 and typ[j] != "drop" and len(typ) - j <= 2:
        typ[j] = "outro"; j -= 1
    out = []
    for (s, e), t in zip(ph, typ):
        if out and out[-1][0] == t and t != "drop":
            out[-1] = (t, out[-1][1], e)
        else:
            out.append((t, s, e))
    return out


def load(folder, tid):
    """A track folder -> a track dict shaped like the synthetic ones (plus audio, offset and real waveforms)."""
    folder = Path(folder)
    meta = json.loads((folder / "track.json").read_text())
    dat, ext = tags(folder / "ANLZ0000.DAT"), tags(folder / "ANLZ0000.EXT")
    two = tags(folder / "ANLZ0000.2EX") if (folder / "ANLZ0000.2EX").is_file() else {}
    grid = beat_grid(dat["PQTZ"])
    d0 = next(i for i, (b, _) in enumerate(grid) if b == 1)          # first downbeat
    beat_ms = (grid[-1][1] - grid[d0][1]) / max(1, len(grid) - 1 - d0)
    bpm = round(60000 / beat_ms, 2)
    beats = (len(grid) - d0) // 4 * 4
    bars, offset, bar_ms = beats // 4, grid[d0][1], 4 * beat_ms
    lo, tot = bands(two["PWV7"]) if "PWV7" in two else ([], [])
    bass = per_bar(lo, offset, bars, bar_ms) if lo else [1.0] * bars
    energy = per_bar(tot, offset, bars, bar_ms) if tot else [1.0] * bars
    if "PSSI" in ext:
        sections, how = sections_from_phrases(phrases(ext["PSSI"]), d0, bars), "rekordbox phrases"
    else:
        sections, how = sections_from_bass(bass, energy), "bass"
    drops = [(s, sections[k - 1][1] if k and sections[k - 1][0] in ("build", "breakdown") else max(1, s - 8))
             for k, (typ, s, e) in enumerate(sections) if typ == "drop"]
    if not drops:                                                     # the show engine wants one: the loudest phrase
        s = max(range(1, bars + 1, 8), key=lambda b: sum(energy[b - 1:b + 7]))
        drops = [(s, max(1, s - 8))]
    outro = next((s for typ, s, e in sections if typ == "outro"), max(1, bars - 15))
    emax, bmax = max(energy) or 1, max(bass) or 1
    return {"id": tid, "title": meta["title"], "artist": meta["artist"], "genre": meta.get("genre", ""),
            "key": CAMELOT.get(meta.get("key", ""), meta.get("key", "")), "bpm": bpm, "plan": [],
            "label": meta.get("source", "USB"), "year": 0, "rating": 0, "color": None,
            "bars": bars, "beats": beats, "sections": sections, "beat_ms": beat_ms, "offset_ms": offset,
            "dur": int(meta.get("duration") or (offset + beats * beat_ms) / 1000) + 1,
            "drops": drops, "outro_bar": outro, "real": True, "structure": how,
            "energy_bars": [round(e / emax * 100) for e in energy], "bass_bars": [round(b / bmax * 100) for b in bass],
            "detail_bytes": detail_rgbh(ext["PWV5"]) if "PWV5" in ext else None,
            "audio": folder / meta.get("files", {}).get("audio", "track.mp3")}


def load_all(root, first_id=1001):
    root, out = Path(root), []
    if not root.is_dir():
        return out
    for i, folder in enumerate(sorted(p for p in root.iterdir() if (p / "track.json").is_file())):
        try:
            out.append(load(folder, first_id + i))
        except Exception as e:        # a bad folder shouldn't stop the rig
            print(f"real track {folder.name}: {e}", flush=True)
    return out
