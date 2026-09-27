import com.sun.net.httpserver.HttpExchange;

import javax.crypto.Mac;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HexFormat;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Admin PIN, same scheme as brain/common/s5auth.py: anyone can look, changing anything needs the
 * s5_admin cookie (HMAC-signed, 5 years). The PIN hash and key are in /srv/rave/auth.json; with no
 * file, auth is off and everyone is admin.
 */
public class Auth {
    static final Path FILE = Path.of(System.getProperty("authFile", "/srv/rave/auth.json"));
    static final String COOKIE = "s5_admin";
    static final long MAX_AGE = 5L * 365 * 86400;
    static final long FAIL_WINDOW = 600, LOCKOUT = 600;
    static final int FAIL_LIMIT = 8;

    static long mtime = -1;
    static String salt, pinHash, key;
    static int iterations;
    static long notBefore;
    static final Deque<Long> fails = new ArrayDeque<>();
    static long lockedUntil = 0;

    static synchronized boolean load() {
        try {
            long m = Files.getLastModifiedTime(FILE).toMillis();
            if (m != mtime) {
                String s = Files.readString(FILE);
                salt = field(s, "salt");
                pinHash = field(s, "pin_hash");
                key = field(s, "key");
                String it = field(s, "iterations"), nb = field(s, "not_before");
                iterations = it == null ? 200_000 : Integer.parseInt(it);
                notBefore = nb == null ? 0 : Long.parseLong(nb);
                mtime = m;
            }
            return pinHash != null && key != null && salt != null;
        } catch (IOException | NumberFormatException e) {
            mtime = -1;
            pinHash = key = salt = null;
            return false;
        }
    }

    static String field(String json, String name) {
        Matcher m = Pattern.compile("\"" + name + "\"\\s*:\\s*(\"([^\"]*)\"|(-?\\d+))").matcher(json);
        return m.find() ? (m.group(2) != null ? m.group(2) : m.group(3)) : null;
    }

    static boolean enabled() {
        return load();
    }

    static String sign(String msg) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(HexFormat.of().parseHex(key), "HmacSHA256"));
        return HexFormat.of().formatHex(mac.doFinal(msg.getBytes(StandardCharsets.UTF_8)));
    }

    static String makeToken() throws Exception {
        long ts = System.currentTimeMillis() / 1000;
        return "v1." + ts + "." + sign("v1." + ts);
    }

    static boolean validToken(String tok) {
        if (tok == null || !load()) return false;
        String[] p = tok.split("\\.");
        if (p.length != 3 || !"v1".equals(p[0])) return false;
        try {
            long ts = Long.parseLong(p[1]), now = System.currentTimeMillis() / 1000;
            if (!MessageDigest.isEqual(p[2].getBytes(), sign("v1." + ts).getBytes())) return false;
            return ts >= notBefore && ts <= now + 60 && now - ts < MAX_AGE;
        } catch (Exception e) {
            return false;
        }
    }

    static boolean checkPin(String pin) {
        try {
            PBEKeySpec spec = new PBEKeySpec(pin.toCharArray(), HexFormat.of().parseHex(salt), iterations, 256);
            byte[] h = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            return MessageDigest.isEqual(HexFormat.of().formatHex(h).getBytes(), pinHash.getBytes());
        } catch (Exception e) {
            return false;
        }
    }

    static String cookie(HttpExchange ex) {
        String h = ex.getRequestHeaders().getFirst("Cookie");
        if (h == null) return null;
        for (String part : h.split(";")) {
            String[] kv = part.trim().split("=", 2);
            if (kv.length == 2 && kv[0].equals(COOKIE)) return kv[1];
        }
        return null;
    }

    static boolean isAdmin(HttpExchange ex) {
        return !enabled() || validToken(cookie(ex));
    }

    /** For mutating handlers: true if allowed; otherwise replies 401 and returns false. */
    static boolean require(HttpExchange ex) throws IOException {
        if (isAdmin(ex)) return true;
        DeckDash.send(ex, 401, "application/json", "{\"error\":\"admin PIN required\",\"view_only\":true}".getBytes());
        return false;
    }

    static String cookieHeader(HttpExchange ex, String value, long maxAge) {
        String proto = ex.getRequestHeaders().getFirst("X-Forwarded-Proto");
        return COOKIE + "=" + value + "; Path=/; Max-Age=" + maxAge + "; HttpOnly; SameSite=Lax"
                + ("https".equalsIgnoreCase(proto) ? "; Secure" : "");
    }

    /** GET /api/auth, POST /api/auth {"pin"}, POST /api/auth/logout. */
    static void handle(HttpExchange ex) throws IOException {
        String path = ex.getRequestURI().getPath(), method = ex.getRequestMethod();
        ex.getResponseHeaders().add("Cache-Control", "no-store");
        if ("GET".equals(method) && path.equals("/api/auth")) {
            DeckDash.send(ex, 200, "application/json", ("{\"enabled\":" + enabled() + ",\"admin\":" + isAdmin(ex) + "}").getBytes());
            return;
        }
        if (!"POST".equals(method)) {
            DeckDash.send(ex, 405, "application/json", "{\"error\":\"POST only\"}".getBytes());
            return;
        }
        if (path.equals("/api/auth/logout")) {
            ex.getResponseHeaders().add("Set-Cookie", cookieHeader(ex, "", 0));
            DeckDash.send(ex, 200, "application/json", ("{\"ok\":true,\"admin\":" + !enabled() + "}").getBytes());
            return;
        }
        if (!enabled()) {
            DeckDash.send(ex, 200, "application/json", "{\"ok\":true,\"enabled\":false,\"admin\":true}".getBytes());
            return;
        }
        long now = System.currentTimeMillis() / 1000;
        synchronized (Auth.class) {
            while (!fails.isEmpty() && now - fails.peekFirst() >= FAIL_WINDOW) fails.pollFirst();
            if (now < lockedUntil) {
                DeckDash.send(ex, 429, "application/json", ("{\"error\":\"too many attempts\",\"retry_s\":" + (lockedUntil - now) + "}").getBytes());
                return;
            }
        }
        String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        Matcher m = Pattern.compile("\"pin\"\\s*:\\s*\"([^\"]*)\"").matcher(body);
        String pin = m.find() ? m.group(1) : "";
        if (!pin.isEmpty() && checkPin(pin)) {
            synchronized (Auth.class) { fails.clear(); }
            try {
                ex.getResponseHeaders().add("Set-Cookie", cookieHeader(ex, makeToken(), MAX_AGE));
            } catch (Exception e) {
                DeckDash.send(ex, 500, "application/json", "{\"error\":\"signing failed\"}".getBytes());
                return;
            }
            DeckDash.send(ex, 200, "application/json", "{\"ok\":true,\"admin\":true}".getBytes());
            return;
        }
        synchronized (Auth.class) {
            fails.addLast(now);
            if (fails.size() >= FAIL_LIMIT) lockedUntil = now + LOCKOUT;
        }
        try { Thread.sleep(500); } catch (InterruptedException ignored) { }
        DeckDash.send(ex, 401, "application/json", "{\"error\":\"wrong PIN\"}".getBytes());
    }
}
