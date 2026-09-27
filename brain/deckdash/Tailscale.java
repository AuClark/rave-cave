import com.sun.net.httpserver.HttpExchange;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Tailscale status and controls for the System panel. deckdash runs as pi, which is the Tailscale
 * operator (`sudo tailscale set --operator=pi`), so no sudo is needed.
 *
 * The public link is Funnel on 443 (the dashboard only). Turning it off keeps the dashboard on 443
 * for the tailnet. The other pages are served over HTTPS on their own ports, tailnet only.
 */
public class Tailscale {
    static final long PERIOD_MS = 10_000;
    static volatile String snapshot = "{\"installed\":false}";
    static long sampledAt = 0;

    /** Latest status as a JSON object; refreshed at most every 10 s (the tailscale CLI is slowish). */
    static String json() {
        long now = System.currentTimeMillis();
        if (now - sampledAt >= PERIOD_MS) {
            sampledAt = now;
            snapshot = sample();
        }
        return snapshot;
    }

    static String sample() {
        String st = SystemInfo.exec(5, "tailscale", "status", "--json");
        DeckDash.Json j = new DeckDash.Json().obj();
        String state = field(st, "BackendState");
        if (state == null) return j.bool("installed", false).end().toString();
        String dns = field(st, "DNSName");
        dns = dns == null ? "" : dns.replaceAll("\\.$", "");
        Matcher ips = Pattern.compile("\"TailscaleIPs\"\\s*:\\s*\\[([^\\]]*)\\]").matcher(st);
        // One block per node, Self first. Funnel's ingress relays show up as peers too: skip them.
        int peers = 0, online = 0;
        String[] nodes = st.split("\"PublicKey\"");
        for (int i = 2; i < nodes.length; i++) {
            if ("funnel-ingress-node".equals(field(nodes[i], "HostName"))) continue;
            peers++;
            if (nodes[i].matches("(?s).*\"Online\"\\s*:\\s*true.*")) online++;
        }
        String serve = SystemInfo.exec(5, "tailscale", "serve", "status", "--json");
        boolean funnel = serve.matches("(?s).*\"AllowFunnel\"\\s*:\\s*\\{[^}]*:443\"\\s*:\\s*true.*");
        StringBuilder ports = new StringBuilder("[");
        Matcher pm = Pattern.compile("\"(\\d+)\"\\s*:\\s*\\{\\s*\"HTTPS\"\\s*:\\s*true").matcher(serve);
        while (pm.find()) ports.append(ports.length() > 1 ? "," : "").append(pm.group(1));
        Matcher tn = Pattern.compile("\"CurrentTailnet\"\\s*:\\s*\\{[^}]*?\"Name\"\\s*:\\s*\"([^\"]*)\"").matcher(st);
        j.bool("installed", true).str("state", state).str("version", field(st, "Version"))
                .str("dns_name", dns).raw("ips", ips.find() ? "[" + ips.group(1).replaceAll("\\s+", "") + "]" : "[]")
                .str("tailnet", tn.find() ? tn.group(1) : null)
                .num("peers", peers).num("peers_online", online)
                .str("auth_url", field(st, "AuthURL"))
                .bool("funnel", funnel).str("public_url", funnel && !dns.isEmpty() ? "https://" + dns + "/" : null)
                .raw("https_ports", ports.append("]").toString());
        return j.end().toString();
    }

    /** POST /api/system/tailscale {"funnel": true|false} or {"up": true|false}. Admin only. */
    static void handle(HttpExchange ex) throws IOException {
        if (!"POST".equals(ex.getRequestMethod())) {
            DeckDash.send(ex, 200, "application/json", json().getBytes(StandardCharsets.UTF_8));
            return;
        }
        if (!Auth.require(ex)) return;
        String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        String out;
        if (body.matches("(?s).*\"funnel\"\\s*:\\s*true.*")) {
            out = SystemInfo.exec(15, "tailscale", "funnel", "--bg", "--https=443", "http://127.0.0.1:8080");
        } else if (body.matches("(?s).*\"funnel\"\\s*:\\s*false.*")) {
            // Funnel off drops 443 entirely; put the dashboard back for the tailnet.
            out = SystemInfo.exec(15, "tailscale", "funnel", "--https=443", "off")
                    + SystemInfo.exec(15, "tailscale", "serve", "--bg", "--https=443", "http://127.0.0.1:8080");
        } else if (body.matches("(?s).*\"up\"\\s*:\\s*true.*")) {
            out = SystemInfo.exec(30, "tailscale", "up");
        } else if (body.matches("(?s).*\"up\"\\s*:\\s*false.*")) {
            out = SystemInfo.exec(15, "tailscale", "down");
        } else {
            DeckDash.send(ex, 400, "application/json", "{\"error\":\"send {\\\"funnel\\\":bool} or {\\\"up\\\":bool}\"}".getBytes(StandardCharsets.UTF_8));
            return;
        }
        DeckDash.log("tailscale: " + body.trim() + " -> " + out.trim().replace('\n', ' '));
        sampledAt = System.currentTimeMillis();
        snapshot = sample();
        DeckDash.send(ex, 200, "application/json", snapshot.getBytes(StandardCharsets.UTF_8));
    }

    static String field(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : null;
    }
}
