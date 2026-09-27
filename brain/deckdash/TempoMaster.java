import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.deepsymmetry.beatlink.*;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * The Pi as tempo master, so it can glide the tempo of every deck that has SYNC on (a deck that is
 * master can't be retimed remotely: nothing can move its pitch fader). Off unless deckdash runs with
 * -Dtempo=on, which also makes it join as a standard player number (1-4) and send status packets.
 *
 * Taking master never jolts the playing track: it waits for the current master's next beat, starts
 * its own beat clock on that beat at that tempo and bar position, then takes master.
 *
 *   GET  /api/tempo                                        state (also in /api/state as "tempo")
 *   POST /api/tempo {"action":"take"}                      line up with the current master and take over
 *   POST /api/tempo {"action":"ramp","to":128,"beats":64}  glide to a BPM (the Pi must be master)
 *   POST /api/tempo {"action":"reset","deck":1,"beats":64} glide back to deck 1's original track BPM
 *   POST /api/tempo {"action":"hold"}                      stop a glide where it is
 *   POST /api/tempo {"action":"release","deck":1}          hand master to deck 1
 */
public class TempoMaster {
    static final boolean ENABLED = "on".equals(System.getProperty("tempo", "off"));

    static volatile Integer lineUpWith = null;      // deck whose next beat we start on
    static volatile long lineUpAsked = 0;
    static volatile boolean ramping = false;
    static volatile double rampFrom, rampTo, rampBeats, rampDone;
    static volatile long lastTick = 0;

    /** Before VirtualCdj.start(): sending status (and so being master) needs a standard player number. */
    static void configure(VirtualCdj v) {
        if (ENABLED) v.setUseStandardPlayerNumber(true);
    }

    static void start(HttpServer http) {
        http.createContext("/api/tempo", TempoMaster::handle);
        if (!ENABLED) return;
        VirtualCdj v = VirtualCdj.getInstance();
        try {
            v.setSendingStatus(true);
            DeckDash.log("tempo: sending status as player " + v.getDeviceNumber());
        } catch (Exception e) {
            DeckDash.log("tempo: can't send status, so can't be master: " + e);
        }
        BeatFinder.getInstance().addBeatListener(TempoMaster::onBeat);
        ScheduledExecutorService ex = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "tempo-ramp");
            t.setDaemon(true);
            return t;
        });
        ex.scheduleAtFixedRate(() -> {
            try { tick(); } catch (Throwable t) { DeckDash.logOnce("tempo ramp", t); }
        }, 0, 50, TimeUnit.MILLISECONDS);
    }

    /** On the deck's beat: same tempo, same beat in the bar, starting now; then take master. */
    static void onBeat(Beat beat) {
        Integer from = lineUpWith;
        if (from == null || beat.getDeviceNumber() != from) return;
        lineUpWith = null;
        if (System.currentTimeMillis() - lineUpAsked > 5000) return;       // stale request
        try {
            VirtualCdj v = VirtualCdj.getInstance();
            v.setTempo(beat.getEffectiveTempo());
            v.setPlaying(true);
            v.jumpToBeat(beat.isBeatWithinBarMeaningful() ? beat.getBeatWithinBar() : 1);
            v.becomeTempoMaster();
            DeckDash.log("tempo: took master from deck " + from + " at " + DeckDash.round(beat.getEffectiveTempo(), 2) + " BPM");
        } catch (Exception e) {
            DeckDash.log("tempo: couldn't take master: " + e);
        }
    }

    static void tick() {
        long now = System.nanoTime();
        long dtNs = lastTick == 0 ? 0 : now - lastTick;
        lastTick = now;
        if (!ramping) return;
        VirtualCdj v = VirtualCdj.getInstance();
        if (!v.isTempoMaster()) { ramping = false; return; }
        rampDone += v.getTempo() / 60.0 * (dtNs / 1e9);                    // beats played since the last tick
        double f = Math.min(1.0, rampDone / rampBeats), e = f * f * (3 - 2 * f);   // ease in and out
        v.setTempo(rampFrom + (rampTo - rampFrom) * e);
        if (f >= 1.0) {
            ramping = false;
            DeckDash.log("tempo: glide done at " + DeckDash.round(rampTo, 2) + " BPM");
        }
    }

    static void glide(double to, double beats) {
        VirtualCdj v = VirtualCdj.getInstance();
        if (!v.isTempoMaster()) throw new IllegalStateException("the Pi isn't tempo master yet (take it first)");
        if (!(to >= 60 && to <= 200)) throw new IllegalArgumentException("BPM must be between 60 and 200");
        rampFrom = v.getTempo();
        rampTo = to;
        rampBeats = Math.max(1, beats);
        rampDone = 0;
        ramping = true;
        DeckDash.log("tempo: glide " + DeckDash.round(rampFrom, 2) + " -> " + DeckDash.round(to, 2) + " BPM over " + (int) rampBeats + " beats");
    }

    static void handle(HttpExchange ex) throws IOException {
        ex.getResponseHeaders().add("Access-Control-Allow-Origin", "*");
        if (!"POST".equals(ex.getRequestMethod())) {
            DeckDash.send(ex, 200, "application/json", json().getBytes(StandardCharsets.UTF_8));
            return;
        }
        Map<String, String> b = Library.flatJson(new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
        try {
            if (!ENABLED) throw new IllegalStateException("tempo master is off (deckdash needs -Dtempo=on)");
            VirtualCdj v = VirtualCdj.getInstance();
            if (!v.isSendingStatus()) throw new IllegalStateException("the Pi isn't sending status, so it can't be master");
            String action = b.getOrDefault("action", "");
            double beats = Double.parseDouble(b.getOrDefault("beats", "64"));
            switch (action) {
                case "take" -> {
                    if (!v.isTempoMaster()) {
                        DeviceUpdate m = v.getTempoMaster();
                        if (m == null) throw new IllegalStateException("no deck is tempo master to line up with");
                        lineUpAsked = System.currentTimeMillis();
                        lineUpWith = m.getDeviceNumber();
                    }
                }
                case "ramp" -> glide(Double.parseDouble(b.get("to")), beats);
                case "reset" -> {
                    int deck = Integer.parseInt(b.getOrDefault("deck", "0"));
                    if (!(v.getLatestStatusFor(deck) instanceof CdjStatus s) || s.getBpm() == 0xffff || s.getBpm() == 0)
                        throw new IllegalArgumentException("deck " + deck + " has no track BPM");
                    glide(s.getBpm() / 100.0, beats);                          // the track's original tempo
                }
                case "hold" -> ramping = false;
                case "release" -> {
                    ramping = false;
                    v.appointTempoMaster(Integer.parseInt(b.getOrDefault("deck", "0")));
                }
                default -> throw new IllegalArgumentException("unknown action " + action);
            }
            DeckDash.send(ex, 200, "application/json", json().getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            DeckDash.send(ex, 400, "application/json", new DeckDash.Json().obj().bool("ok", false)
                    .str("error", String.valueOf(e.getMessage())).end().toString().getBytes(StandardCharsets.UTF_8));
        }
    }

    static String json() {
        DeckDash.Json j = new DeckDash.Json().obj().bool("ok", true).bool("enabled", ENABLED);
        if (ENABLED) {
            VirtualCdj v = VirtualCdj.getInstance();
            j.bool("sending", v.isSendingStatus()).num("player", v.getDeviceNumber()).bool("master", v.isTempoMaster())
                    .num("bpm", DeckDash.round(v.getTempo(), 2)).bool("liningUp", lineUpWith != null);
            if (ramping) {
                j.key("ramp").obj().num("from", DeckDash.round(rampFrom, 2)).num("to", DeckDash.round(rampTo, 2))
                        .num("beats", rampBeats).num("done", DeckDash.round(rampDone, 1)).end();
            }
        }
        return j.end().toString();
    }
}
