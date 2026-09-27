import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

/**
 * Every control page through the dashboard's own address: /lighting/ → showbrain (:8090),
 * /projection/ → projector (:8100, Stage at /projection/stage.html), /visuals/ → visuals (:8110).
 *
 * Tailscale Funnel can only publish one port (the dashboard, on 443), so this is how the public
 * link reaches the other pages. Pages learn their prefix from /s5auth.js, which sends their
 * /api/... requests and event streams through it. Changes still need the admin PIN: each service
 * checks the cookie itself, and it's passed through.
 */
public class Proxy {
    static final Map<String, Integer> ROUTES = Map.of("/lighting", 8090, "/projection", 8100, "/visuals", 8110);
    static final List<String> REQUEST_HEADERS = List.of("Cookie", "Content-Type", "Accept", "Last-Event-ID", "X-Forwarded-Proto");
    static final List<String> RESPONSE_HEADERS = List.of("Content-Type", "Cache-Control", "Set-Cookie", "Last-Modified");

    static void register(HttpServer http) {
        ROUTES.forEach((prefix, port) -> http.createContext(prefix, ex -> {
            String path = ex.getRequestURI().getRawPath();
            if (path.equals(prefix)) {                      // /lighting → /lighting/
                ex.getResponseHeaders().add("Location", prefix + "/");
                ex.sendResponseHeaders(301, -1);
                ex.close();
                return;
            }
            String q = ex.getRequestURI().getRawQuery();
            forward(ex, port, path.substring(prefix.length()) + (q == null ? "" : "?" + q), prefix);
        }));
    }

    /** Pass a request to a service on this machine. Event streams are copied as they arrive. */
    static void forward(HttpExchange ex, int port, String pathAndQuery, String prefix) throws IOException {
        HttpURLConnection c;
        try {
            c = (HttpURLConnection) URI.create("http://127.0.0.1:" + port + pathAndQuery).toURL().openConnection();
            c.setRequestMethod(ex.getRequestMethod());
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(2000);
            c.setReadTimeout(0);                            // event streams stay open
            for (String h : REQUEST_HEADERS) {
                String v = ex.getRequestHeaders().getFirst(h);
                if (v != null) c.setRequestProperty(h, v);
            }
            if ("POST".equals(ex.getRequestMethod())) {
                c.setDoOutput(true);
                try (OutputStream o = c.getOutputStream()) {
                    ex.getRequestBody().transferTo(o);
                }
            }
            int code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            DeckDash.cors(ex);
            for (String h : RESPONSE_HEADERS) {
                List<String> vs = c.getHeaderFields().get(h);
                if (vs != null) for (String v : vs) ex.getResponseHeaders().add(h, v);
            }
            String loc = c.getHeaderField("Location");
            if (loc != null) ex.getResponseHeaders().add("Location", loc.startsWith("/") && prefix != null ? prefix + loc : loc);
            String type = c.getContentType() == null ? "" : c.getContentType();
            boolean stream = type.startsWith("text/event-stream");
            if (!stream) {
                byte[] body = in == null ? new byte[0] : in.readAllBytes();
                ex.sendResponseHeaders(code, body.length == 0 ? -1 : body.length);
                if (body.length > 0) try (OutputStream out = ex.getResponseBody()) { out.write(body); }
                ex.close();
                return;
            }
            ex.sendResponseHeaders(code, 0);
            try (OutputStream out = ex.getResponseBody(); InputStream src = in) {
                byte[] buf = new byte[16384];
                for (int n; src != null && (n = src.read(buf)) > 0; ) {
                    out.write(buf, 0, n);
                    out.flush();
                }
            } catch (IOException closed) {
                // the browser went away, or the service restarted
            } finally {
                c.disconnect();
            }
        } catch (IOException e) {
            DeckDash.send(ex, 502, "application/json", ("{\"error\":\"service on :" + port + " not responding\"}").getBytes(StandardCharsets.UTF_8));
        }
    }
}
