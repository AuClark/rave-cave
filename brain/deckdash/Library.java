import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.deepsymmetry.beatlink.*;
import org.deepsymmetry.beatlink.data.*;
import org.deepsymmetry.cratedigger.Database;
import org.deepsymmetry.cratedigger.pdb.RekordboxPdb;

import java.io.IOException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Library browser (Serato-style): the rekordbox export on every USB/SD in the players, read
 * through CrateDigger, plus deck commands (load track, play/stop, sync, master).
 *
 *   GET  /api/library                          media with a readable database
 *   GET  /api/library/tree?src=P:SLOT          playlist folders and playlists
 *   GET  /api/library/tracks?src=P:SLOT[&playlist=ID]   tracks (all, or one playlist in order)
 *   POST /api/deck  {"deck":N, "action":"load", "src":"P:SLOT", "id":ID, "force":false}
 *   POST /api/deck  {"deck":N, "action":"play"|"stop"|"sync_on"|"sync_off"|"master"}
 *
 * Search, filters and sorting run in the browser; a whole library is a few hundred kB of JSON.
 */
public class Library {
    static final Map<String, String> cache = new ConcurrentHashMap<>();

    static void register(HttpServer http) {
        http.createContext("/api/library/tree", ex -> safe(ex, () -> tree(query(ex))));
        http.createContext("/api/library/tracks", ex -> safe(ex, () -> tracks(query(ex))));
        http.createContext("/api/library", ex -> safe(ex, Library::sources));
        http.createContext("/api/deck", Library::deck);
        CrateDigger.getInstance().addDatabaseListener(new DatabaseListener() {
            public void databaseMounted(SlotReference slot, Database db) {
                DeckDash.log("library: database ready for " + slot + " (" + db.trackIndex.size() + " tracks)");
            }
            public void databaseUnmounted(SlotReference slot, Database db) {
                cache.keySet().removeIf(k -> k.startsWith(src(slot) + "/"));
            }
        });
    }

    // ---------- reading the database ----------

    static String src(SlotReference s) { return s.player + ":" + s.slot; }

    static SlotReference slotFor(String src) {
        if (src == null || !src.contains(":")) throw new IllegalArgumentException("src must be PLAYER:SLOT");
        String[] p = src.split(":", 2);
        return SlotReference.getSlotReference(Integer.parseInt(p[0]), CdjStatus.TrackSourceSlot.valueOf(p[1]));
    }

    static Database db(String src) {
        Database db = CrateDigger.getInstance().isRunning() ? CrateDigger.getInstance().findDatabase(slotFor(src)) : null;
        if (db == null) throw new IllegalStateException("no rekordbox database for " + src + " (yet)");
        return db;
    }

    static String sources() {
        DeckDash.Json j = new DeckDash.Json().obj().key("sources").arr();
        if (MetadataFinder.getInstance().isRunning()) {
            for (MediaDetails m : MetadataFinder.getInstance().getMountedMediaDetails()) {
                Database db = CrateDigger.getInstance().isRunning() ? CrateDigger.getInstance().findDatabase(m.slotReference) : null;
                j.obj().str("src", src(m.slotReference)).num("player", m.slotReference.player)
                        .str("slot", String.valueOf(m.slotReference.slot)).str("name", m.name)
                        .num("tracks", db == null ? m.trackCount : db.trackIndex.size())
                        .num("playlists", m.playlistCount).bool("ready", db != null).end();
            }
        }
        j.end().key("decks").arr();
        for (DeviceAnnouncement d : DeviceFinder.getInstance().getCurrentDevices()) {
            if (VirtualCdj.getInstance().getLatestStatusFor(d.getDeviceNumber()) instanceof CdjStatus) j.item(d.getDeviceNumber());
        }
        return j.end().end().toString();
    }

    static String tree(Map<String, String> q) {
        String src = q.get("src");
        return cache.computeIfAbsent(src + "/tree", k -> {
            Database db = db(src);
            DeckDash.Json j = new DeckDash.Json().obj().key("items");
            folder(j, db, 0L, 0);
            return j.end().toString();
        });
    }

    static void folder(DeckDash.Json j, Database db, long id, int depth) {
        j.arr();
        List<Database.PlaylistFolderEntry> entries = db.playlistFolderIndex.get(id);
        if (entries != null && depth < 16) {
            for (Database.PlaylistFolderEntry e : entries) {
                j.obj().num("id", e.id).str("name", e.name).bool("folder", e.isFolder);
                if (e.isFolder) {
                    j.key("children");
                    folder(j, db, e.id, depth + 1);
                } else {
                    List<Long> ids = db.playlistIndex.get(e.id);
                    j.num("count", ids == null ? 0 : ids.size());
                }
                j.end();
            }
        }
        j.end();
    }

    static String tracks(Map<String, String> q) {
        String src = q.get("src");
        long playlist = Long.parseLong(q.getOrDefault("playlist", "0"));
        return cache.computeIfAbsent(src + "/tracks/" + playlist, k -> {
            Database db = db(src);
            Collection<Long> ids = playlist == 0 ? db.trackIndex.keySet() : db.playlistIndex.getOrDefault(playlist, List.of());
            DeckDash.Json j = new DeckDash.Json().obj().str("src", src).num("playlist", playlist).key("tracks").arr();
            int pos = 0;
            for (Long id : ids) {
                RekordboxPdb.TrackRow t = db.trackIndex.get(id);
                if (t == null) continue;
                j.obj().num("n", ++pos).num("id", t.id())
                        .str("title", Database.getText(t.title()))
                        .str("artist", name(db, db.artistIndex, t.artistId()))
                        .str("album", name(db, db.albumIndex, t.albumId()))
                        .str("genre", name(db, db.genreIndex, t.genreId()))
                        .str("label", name(db, db.labelIndex, t.labelId()))
                        .str("remixer", name(db, db.artistIndex, t.remixerId()))
                        .str("key", name(db, db.musicalKeyIndex, t.keyId()))
                        .str("color", name(db, db.colorIndex, (long) t.colorId()))
                        .num("bpm", t.tempo() / 100.0).num("dur", t.duration()).num("rating", t.rating())
                        .num("year", t.year()).num("bitrate", t.bitrate()).num("plays", t.playCount())
                        .str("added", Database.getText(t.dateAdded()))
                        .str("comment", Database.getText(t.comment())).end();
            }
            return j.end().end().toString();
        });
    }

    /** Name of the row with this id in an Artist/Album/Genre/Label/Key/Color index, or null. */
    static String name(Database db, Map<Long, ?> index, long id) {
        if (id == 0) return null;
        Object row = index.get(id);
        RekordboxPdb.DeviceSqlString s;
        if (row instanceof RekordboxPdb.ArtistRow r) s = r.name();
        else if (row instanceof RekordboxPdb.AlbumRow r) s = r.name();
        else if (row instanceof RekordboxPdb.GenreRow r) s = r.name();
        else if (row instanceof RekordboxPdb.LabelRow r) s = r.name();
        else if (row instanceof RekordboxPdb.KeyRow r) s = r.name();
        else if (row instanceof RekordboxPdb.ColorRow r) s = r.name();
        else return null;
        String v = Database.getText(s);
        return v == null || v.isEmpty() ? null : v;
    }

    // ---------- deck commands ----------

    static void deck(HttpExchange ex) throws IOException {
        if (!"POST".equals(ex.getRequestMethod())) { DeckDash.send(ex, 405, "text/plain", "POST only".getBytes()); return; }
        if (!Auth.require(ex)) return;
        Map<String, String> b = flatJson(new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
        try {
            int deck = Integer.parseInt(b.getOrDefault("deck", "0"));
            String action = b.getOrDefault("action", "");
            VirtualCdj v = VirtualCdj.getInstance();
            DeviceUpdate u = v.getLatestStatusFor(deck);
            if (!(u instanceof CdjStatus s)) throw new IllegalArgumentException("no player " + deck + " on the link");
            switch (action) {
                case "load" -> {
                    // Never swap the track under a playing deck unless explicitly forced.
                    if (s.isPlaying() && !"true".equals(b.get("force")))
                        throw new IllegalStateException("deck " + deck + " is playing; stop it first (or force)");
                    SlotReference slot = slotFor(b.get("src"));
                    int id = Integer.parseInt(b.get("id"));
                    v.sendLoadTrackCommand(deck, id, slot.player, slot.slot, CdjStatus.TrackType.REKORDBOX);
                }
                case "play" -> v.sendFaderStartCommand(Set.of(deck), Set.of());
                case "stop" -> v.sendFaderStartCommand(Set.of(), Set.of(deck));
                case "sync_on" -> v.sendSyncModeCommand(deck, true);
                case "sync_off" -> v.sendSyncModeCommand(deck, false);
                case "master" -> v.appointTempoMaster(deck);
                default -> throw new IllegalArgumentException("unknown action " + action);
            }
            DeckDash.log("deck " + deck + ": " + action + (b.containsKey("id") ? " track " + b.get("id") + " from " + b.get("src") : ""));
            json(ex, "{\"ok\":true}");
        } catch (Exception e) {
            DeckDash.send(ex, 400, "application/json", new DeckDash.Json().obj().bool("ok", false)
                    .str("error", String.valueOf(e.getMessage())).end().toString().getBytes(StandardCharsets.UTF_8));
        }
    }

    // ---------- helpers ----------

    static void safe(HttpExchange ex, java.util.function.Supplier<String> body) throws IOException {
        String out;
        try {
            out = body.get();
        } catch (Exception e) {
            DeckDash.send(ex, 404, "application/json", new DeckDash.Json().obj().str("error", String.valueOf(e.getMessage()))
                    .end().toString().getBytes(StandardCharsets.UTF_8));
            return;
        }
        json(ex, out);
    }

    static void json(HttpExchange ex, String body) throws IOException {
        DeckDash.send(ex, 200, "application/json", body.getBytes(StandardCharsets.UTF_8));
    }

    static Map<String, String> query(HttpExchange ex) {
        Map<String, String> m = new HashMap<>();
        String q = ex.getRequestURI().getRawQuery();
        if (q != null) for (String kv : q.split("&")) {
            int i = kv.indexOf('=');
            if (i > 0) m.put(URLDecoder.decode(kv.substring(0, i), StandardCharsets.UTF_8), URLDecoder.decode(kv.substring(i + 1), StandardCharsets.UTF_8));
        }
        return m;
    }

    /** Parse a flat JSON object of strings, numbers and booleans (all the deck commands need). */
    static Map<String, String> flatJson(String s) {
        Map<String, String> m = new HashMap<>();
        java.util.regex.Matcher r = java.util.regex.Pattern
                .compile("\"(\\w+)\"\\s*:\\s*(?:\"((?:[^\"\\\\]|\\\\.)*)\"|([-\\w.]+))").matcher(s);
        while (r.find()) m.put(r.group(1), r.group(2) != null ? r.group(2) : r.group(3));
        return m;
    }
}
