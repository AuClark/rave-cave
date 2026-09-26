import org.deepsymmetry.beatlink.data.*;

import java.awt.Color;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Track timeline analyser: reads ahead through a loaded track's detailed colour
 * waveform and beat grid to label intro / groove / breakdown / build / drop /
 * outro, and to predict drops (on phrase boundaries, when bass returns after a
 * low-bass stretch). Results are cached per track (DataReference).
 *
 * Colour waveform: red ~ bass, green ~ mids, blue ~ highs; 150 frames per second.
 */
public class Timeline {
    static final Map<String, String> cache = new ConcurrentHashMap<>();

    static final double LOW_BASS = 0.30;      // normalised bass below this = "no bass"
    static final double HIGH_BASS = 0.50;     // at or above = bass is in
    static final double DROP_LIFT = 1.6;      // bass after / bass before
    static final double DROP_MIN = 0.60;      // bass after must reach this
    static final int BUILD_BARS = 8;
    static final int DROP_BARS = 16;

    static String forPlayer(int player) {
        BeatGrid g = BeatGridFinder.getInstance().isRunning() ? BeatGridFinder.getInstance().getLatestBeatGridFor(player) : null;
        WaveformDetail wd = WaveformFinder.getInstance().isRunning() ? WaveformFinder.getInstance().getLatestDetailFor(player) : null;
        TrackMetadata md = MetadataFinder.getInstance().isRunning() ? MetadataFinder.getInstance().getLatestMetadataFor(player) : null;
        if (g == null || wd == null || !g.dataReference.equals(wd.dataReference)) return null;
        String key = String.valueOf(wd.dataReference);
        return cache.computeIfAbsent(key, k -> {
            try {
                return compute(g, wd, md);
            } catch (Exception e) {
                DeckDash.log("timeline failed for " + k + ": " + e);
                return "{\"error\":\"" + e + "\"}";
            }
        });
    }

    static String compute(BeatGrid g, WaveformDetail wd, TrackMetadata md) {
        int beats = g.beatCount;
        int bars = g.getBarNumber(beats);
        int[] firstBeat = new int[bars + 2];
        for (int b = 1; b <= beats; b++) {
            int bar = g.getBarNumber(b);
            if (bar >= 1 && bar <= bars && firstBeat[bar] == 0) firstBeat[bar] = b;
        }

        // Per-bar energy and bass share from the detailed waveform.
        double[] energy = new double[bars + 2], bass = new double[bars + 2];
        int[] cnt = new int[bars + 2];
        double[] beatBass = new double[beats + 2];
        int[] beatCnt = new int[beats + 2];
        int frames = wd.getFrameCount();
        for (int f = 0; f < frames; f++) {
            int beat = g.findBeatAtTime(f * 1000L / 150);
            if (beat < 1) continue;
            int bar = g.getBarNumber(beat);
            if (bar < 1 || bar > bars) continue;
            int h = wd.segmentHeight(f, 1);
            Color c = wd.segmentColor(f, 1);
            double sum = c.getRed() + c.getGreen() + c.getBlue() + 1;
            energy[bar] += h;
            bass[bar] += h * c.getRed() / sum;
            cnt[bar]++;
            beatBass[beat] += h * c.getRed() / sum;
            beatCnt[beat]++;
        }
        double maxE = 1e-9, maxB = 1e-9;
        for (int b = 1; b <= bars; b++) {
            if (cnt[b] > 0) { energy[b] /= cnt[b]; bass[b] /= cnt[b]; }
            maxE = Math.max(maxE, energy[b]);
            maxB = Math.max(maxB, bass[b]);
        }
        for (int b = 1; b <= bars; b++) { energy[b] /= maxE; bass[b] /= maxB; }
        for (int b = 1; b <= beats; b++) beatBass[b] = beatCnt[b] > 0 ? beatBass[b] / beatCnt[b] / maxB : 0;

        // Beat-in: first bar where bass is in for 2 bars running. Outro: after the last bass bar.
        int beatIn = 1;
        for (int b = 1; b < bars; b++) if (bass[b] >= HIGH_BASS && bass[b + 1] >= HIGH_BASS) { beatIn = b; break; }
        int lastHigh = bars;
        for (int b = bars; b >= 1; b--) if (bass[b] >= HIGH_BASS) { lastHigh = b; break; }

        // Drop candidates on phrase boundaries relative to the beat-in bar.
        List<double[]> cands = new ArrayList<>();   // {bar, lift}
        for (int b = beatIn + 4; b <= Math.min(lastHigh, bars - 3); b++) {
            int rel = b - beatIn;
            boolean phrase8 = rel % 8 == 0, phrase4 = rel % 4 == 0;
            if (!phrase4) continue;
            double before = 0, after = 0;
            int nb = 0;
            for (int k = Math.max(1, b - 8); k < b; k++) { before += bass[k]; nb++; }
            for (int k = b; k < b + 4; k++) after += bass[k];
            before /= Math.max(1, nb);
            after /= 4;
            double lift = after / Math.max(1e-6, before);
            if (after >= DROP_MIN && lift >= (phrase8 ? DROP_LIFT : DROP_LIFT * 1.4)) cands.add(new double[]{b, lift});
        }
        Map<Integer, Integer> refined = new HashMap<>();   // phrase-grid bar -> refined bar
        // Keep the strongest candidate within any 16-bar window.
        List<double[]> drops = new ArrayList<>();
        for (double[] c : cands) {
            double[] last = drops.isEmpty() ? null : drops.get(drops.size() - 1);
            if (last != null && c[0] - last[0] < 16) { if (c[1] > last[1]) drops.set(drops.size() - 1, c); }
            else drops.add(c);
        }

        // Refine each drop to the beat where bass actually returns. Candidates only sit on the phrase
        // grid, so a grid misaligned by a bar or two always lands late; step back up to 8 bars to the
        // start of the continuous full-bass run that carries into the drop, then snap to a bar line.
        for (double[] d : drops) {
            int db = (int) d[0];
            int b0 = firstBeat[db];
            double level = 0;
            int nl = 0;
            for (int k = b0; k < Math.min(beats, b0 + 16); k++) { level += beatBass[k]; nl++; }
            level /= Math.max(1, nl);
            double thr = 0.7 * level;
            int limit = firstBeat[Math.max(beatIn, db - 8)];
            int onset = b0;
            while (onset - 1 >= limit && (beatBass[onset - 1] + beatBass[Math.max(1, onset - 2)]) / 2 >= thr) onset--;
            // Also allow the bass to arrive slightly after the grid bar (grid ahead of the music).
            if (onset == b0 && beatBass[b0] < thr) {
                int k = b0;
                while (k < Math.min(beats, b0 + 8) && beatBass[k] < thr) k++;
                onset = k;
            }
            int bar = Math.max(1, Math.min(bars, g.getBarNumber(Math.max(1, onset))));
            int snapped = (bar + 1 <= bars && firstBeat[bar + 1] - onset < onset - firstBeat[bar]) ? bar + 1 : bar;
            refined.put(db, snapped);
        }
        for (double[] d : drops) d[0] = refined.getOrDefault((int) d[0], (int) d[0]);

        // Label every bar.
        String[] label = new String[bars + 2];
        for (int b = 1; b <= bars; b++) label[b] = b < beatIn ? "intro" : b > lastHigh ? "outro" : "groove";
        for (int b = beatIn; b <= lastHigh; b++) {           // breakdowns: 4+ low-bass bars
            if (bass[b] >= LOW_BASS) continue;
            int e = b;
            while (e + 1 <= lastHigh && bass[e + 1] < LOW_BASS) e++;
            if (e - b + 1 >= 4) for (int k = b; k <= e; k++) label[k] = "breakdown";
            b = e;
        }
        List<int[]> buildRanges = new ArrayList<>();
        for (double[] d : drops) {
            int db = (int) d[0];
            int start = Math.max(beatIn, db - BUILD_BARS);
            // Short breakdowns: build over the whole low stretch instead.
            int lowStart = db;
            while (lowStart - 1 >= beatIn && "breakdown".equals(label[lowStart - 1])) lowStart--;
            if (lowStart < db && db - lowStart < BUILD_BARS) start = Math.max(start, lowStart);
            if (lowStart == db) start = Math.max(beatIn, db - 4);   // no breakdown: short build
            for (int k = start; k < db; k++) label[k] = "build";
            buildRanges.add(new int[]{start, db - 1});
            for (int k = db; k < Math.min(bars + 1, db + DROP_BARS); k++) {
                if ("breakdown".equals(label[k]) || "outro".equals(label[k])) break;
                label[k] = "drop";
            }
        }

        // Cue hints: a hot cue / memory point within a bar of a drop raises confidence.
        List<Long> cueMs = new ArrayList<>();
        if (md != null && md.getCueList() != null) for (CueList.Entry e : md.getCueList().entries) cueMs.add(e.cueTime);

        DeckDash.Json j = new DeckDash.Json().obj();
        j.str("ref", String.valueOf(g.dataReference)).str("title", md == null ? null : md.getTitle())
                .num("bars", bars).num("beats", beats).num("beatInBar", beatIn).num("beatInBeat", firstBeat[beatIn])
                .num("outroBar", lastHigh + 1);
        j.key("drops").arr();
        for (int i = 0; i < drops.size(); i++) {
            int db = (int) drops.get(i)[0];
            double lift = drops.get(i)[1];
            int beat = firstBeat[db];
            long ms = g.getTimeWithinTrack(beat);
            long barMs = g.getTimeWithinTrack(Math.min(beats, beat + 4)) - ms;
            boolean cue = cueMs.stream().anyMatch(c -> Math.abs(c - ms) <= barMs);
            double conf = Math.min(0.95, 0.5 + (lift - DROP_LIFT) / 4 + (cue ? 0.2 : 0));
            int[] br = buildRanges.get(i);
            int gridBar = refined.entrySet().stream().filter(e -> e.getValue() == db).map(Map.Entry::getKey).findFirst().orElse(db);
            j.obj().num("bar", db).num("gridBar", gridBar).num("beat", beat).num("ms", ms).num("lift", DeckDash.round(lift, 2))
                    .num("confidence", DeckDash.round(conf, 2)).bool("cue", cue)
                    .num("buildStartBar", br[0]).num("buildStartBeat", firstBeat[br[0]]).end();
        }
        j.end();
        j.key("sections").arr();
        for (int b = 1; b <= bars; ) {
            int e = b;
            while (e + 1 <= bars && label[e + 1].equals(label[b])) e++;
            int endBeat = e + 1 <= bars ? firstBeat[e + 1] - 1 : beats;
            j.obj().str("type", label[b]).num("startBar", b).num("endBar", e)
                    .num("startBeat", firstBeat[b]).num("endBeat", endBeat).end();
            b = e + 1;
        }
        j.end();
        StringJoiner je = new StringJoiner(",", "[", "]"), jb = new StringJoiner(",", "[", "]"),
                jf = new StringJoiner(",", "[", "]"), jm = new StringJoiner(",", "[", "]");
        for (int b = 1; b <= bars; b++) {
            je.add(String.valueOf(Math.round(energy[b] * 100)));
            jb.add(String.valueOf(Math.round(bass[b] * 100)));
            jf.add(String.valueOf(firstBeat[b]));
        }
        for (int b = 1; b <= beats; b++) jm.add(String.valueOf(g.getTimeWithinTrack(b)));
        j.raw("energy", je.toString()).raw("bass", jb.toString()).raw("barFirstBeat", jf.toString()).raw("beatMs", jm.toString());
        return j.end().toString();
    }
}
