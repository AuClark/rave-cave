import java.io.File;
import java.io.IOException;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Brain health for the dashboard's System panel (/api/system). A background thread samples every
 * 2 s so the endpoint just returns the latest snapshot. Everything comes from /proc, /sys, systemd
 * and vcgencmd; nothing here changes any state.
 */
public class SystemInfo {
    static final String[] SERVICES = {"deckdash", "showbrain", "mixer", "projector", "visuals"};
    static final Map<Integer, String> PORTS = new LinkedHashMap<>(Map.of(
            8080, "dashboard", 8090, "commander", 8100, "projector", 8110, "visuals"));
    static final long PERIOD_MS = 2000;

    static volatile String snapshot = "{\"ready\":false}";
    static long[] prevCpuTotal, prevCpuIdle;
    static final Map<String, long[]> prevNet = new HashMap<>();       // iface -> {rx, tx, t}
    static final Map<String, long[]> prevSvcCpu = new HashMap<>();    // unit -> {cpuNs, t}
    static String throttled = null;
    static long throttledAt = 0;

    static void start() {
        Thread t = new Thread(() -> {
            while (true) {
                try {
                    snapshot = sample();
                } catch (Throwable e) {
                    DeckDash.log("system sample failed: " + e);
                }
                try {
                    Thread.sleep(PERIOD_MS);
                } catch (InterruptedException e) {
                    return;
                }
            }
        }, "system-info");
        t.setDaemon(true);
        t.start();
    }

    static String json() {
        return snapshot;
    }

    // ---------------------------------------------------------------- sampling

    static String sample() {
        long now = System.currentTimeMillis();
        DeckDash.Json j = new DeckDash.Json().obj();
        j.bool("ready", true).num("ts", now).str("host", hostname());

        // CPU temperature, clock, throttling
        double temp = readNum("/sys/class/thermal/thermal_zone0/temp", -1000) / 1000.0;
        double mhz = readNum("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", 0) / 1000.0;
        if (throttled == null || now - throttledAt > 10_000) {
            throttled = exec(2, "vcgencmd", "get_throttled");
            throttledAt = now;
        }
        long thr = parseThrottled(throttled);
        j.key("cpu").obj().num("temp_c", DeckDash.round(temp, 1)).num("mhz", Math.round(mhz))
                .raw("usage", cpuUsage()).str("load", read("/proc/loadavg").trim())
                .num("cores", Runtime.getRuntime().availableProcessors()).end();
        j.key("throttle").obj().num("raw", thr < 0 ? -1 : thr)
                .bool("under_voltage_now", (thr & 0x1) != 0).bool("freq_capped_now", (thr & 0x2) != 0)
                .bool("throttled_now", (thr & 0x4) != 0).bool("soft_temp_limit_now", (thr & 0x8) != 0)
                .bool("under_voltage_since_boot", (thr & 0x10000) != 0).bool("freq_capped_since_boot", (thr & 0x20000) != 0)
                .bool("throttled_since_boot", (thr & 0x40000) != 0).bool("soft_temp_limit_since_boot", (thr & 0x80000) != 0)
                .end();

        // Memory
        Map<String, Long> mem = meminfo();
        long memTotal = mem.getOrDefault("MemTotal", 0L), memAvail = mem.getOrDefault("MemAvailable", 0L);
        long swapTotal = mem.getOrDefault("SwapTotal", 0L), swapFree = mem.getOrDefault("SwapFree", 0L);
        j.key("memory").obj().num("total_mb", memTotal / 1024).num("used_mb", (memTotal - memAvail) / 1024)
                .num("available_mb", memAvail / 1024).num("swap_total_mb", swapTotal / 1024)
                .num("swap_used_mb", (swapTotal - swapFree) / 1024).end();

        // Uptime
        double up = readNum("/proc/uptime", 0);
        j.num("uptime_s", Math.round(up));

        // Storage
        File root = new File("/");
        long recBytes = 0, recFiles = 0;
        File[] recs = new File("/srv/rave/recordings").listFiles();
        if (recs != null) for (File f : recs) if (f.isFile()) { recBytes += f.length(); recFiles++; }
        j.key("disk").obj().num("total_gb", DeckDash.round(root.getTotalSpace() / 1e9, 1))
                .num("free_gb", DeckDash.round(root.getUsableSpace() / 1e9, 1))
                .num("recordings_gb", DeckDash.round(recBytes / 1e9, 2)).num("recordings_files", recFiles).end();

        // Network
        j.key("network").obj();
        j.key("interfaces").arr();
        Map<String, long[]> dev = netDev();
        for (String iface : List.of("wlan0", "eth0")) {
            long[] c = dev.get(iface);
            if (c == null) continue;
            long[] p = prevNet.get(iface);
            double rx = 0, tx = 0;
            if (p != null && now > p[2]) {
                double dt = (now - p[2]) / 1000.0;
                rx = (c[0] - p[0]) / dt;
                tx = (c[1] - p[1]) / dt;
            }
            prevNet.put(iface, new long[]{c[0], c[1], now});
            j.obj().str("name", iface).str("addresses", addresses(iface))
                    .num("rx_kbps", DeckDash.round(rx * 8 / 1000, 1)).num("tx_kbps", DeckDash.round(tx * 8 / 1000, 1))
                    .bool("up", "up".equals(read("/sys/class/net/" + iface + "/operstate").trim())).end();
        }
        j.end();
        double[] wifi = wireless();
        j.key("wifi").obj().num("quality_pct", wifi == null ? -1 : Math.round(wifi[0] / 70.0 * 100))
                .num("signal_dbm", wifi == null ? 0 : wifi[1]).end();
        j.end();

        // Services
        j.key("services").arr();
        for (Map<String, String> s : services(now)) {
            j.obj().str("name", s.get("name")).str("state", s.get("state")).str("sub", s.get("sub"))
                    .num("pid", Long.parseLong(s.getOrDefault("pid", "0")))
                    .num("restarts", Long.parseLong(s.getOrDefault("restarts", "0")))
                    .num("mem_mb", Double.parseDouble(s.getOrDefault("mem_mb", "-1")))
                    .num("cpu_pct", Double.parseDouble(s.getOrDefault("cpu_pct", "-1")))
                    .str("since", s.get("since")).end();
        }
        j.end();

        // Clients: established TCP connections to each rig page (from other machines).
        j.key("clients").obj();
        Map<Integer, Map<String, Integer>> conns = connections();
        int total = 0;
        j.key("ports").arr();
        for (Map.Entry<Integer, String> e : PORTS.entrySet()) {
            Map<String, Integer> byIp = conns.getOrDefault(e.getKey(), Map.of());
            int n = byIp.values().stream().mapToInt(Integer::intValue).sum();
            total += byIp.size();
            StringJoiner ips = new StringJoiner(",", "[", "]");
            byIp.keySet().stream().sorted().forEach(ip -> ips.add("\"" + ip + "\""));
            j.obj().num("port", e.getKey()).str("page", e.getValue()).num("connections", n)
                    .num("devices", byIp.size()).raw("addresses", ips.toString()).end();
        }
        j.end();
        Set<String> uniq = new TreeSet<>();
        conns.values().forEach(m -> uniq.addAll(m.keySet()));
        j.num("devices", uniq.size()).num("dashboard_streams", DeckDash.sseClients.size());
        j.end();

        // Hardware
        j.key("usb").arr();
        for (String[] u : usbDevices()) j.obj().str("id", u[0]).str("name", u[1]).end();
        j.end();
        j.num("djlink_devices", org.deepsymmetry.beatlink.DeviceFinder.getInstance().isRunning()
                ? org.deepsymmetry.beatlink.DeviceFinder.getInstance().getCurrentDevices().size() : 0);

        Runtime rt = Runtime.getRuntime();
        j.key("deckdash_jvm").obj().num("heap_used_mb", (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024))
                .num("heap_max_mb", rt.maxMemory() / (1024 * 1024)).end();
        return j.end().toString();
    }

    // ---------------------------------------------------------------- helpers

    static String read(String path) {
        try {
            return Files.readString(Path.of(path), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }

    static double readNum(String path, double dflt) {
        try {
            return Double.parseDouble(read(path).trim().split("\\s+")[0]);
        } catch (NumberFormatException | ArrayIndexOutOfBoundsException e) {
            return dflt;
        }
    }

    static String exec(int timeoutS, String... cmd) {
        try {
            Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
            if (!p.waitFor(timeoutS, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                return "";
            }
            return new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException | InterruptedException e) {
            return "";
        }
    }

    static String hostname() {
        String h = read("/etc/hostname").trim();
        return h.isEmpty() ? "unknown" : h;
    }

    static long parseThrottled(String s) {
        if (s == null) return -1;
        int i = s.indexOf("0x");
        if (i < 0) return -1;
        try {
            return Long.parseLong(s.substring(i + 2).trim(), 16);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** Per-core and total CPU usage (%) since the previous sample, from /proc/stat. */
    static String cpuUsage() {
        List<long[]> rows = new ArrayList<>();
        for (String line : read("/proc/stat").split("\n")) {
            if (!line.startsWith("cpu")) break;
            String[] f = line.trim().split("\\s+");
            long total = 0;
            for (int i = 1; i < f.length; i++) total += Long.parseLong(f[i]);
            long idle = Long.parseLong(f[4]) + (f.length > 5 ? Long.parseLong(f[5]) : 0);
            rows.add(new long[]{total, idle});
        }
        StringJoiner out = new StringJoiner(",", "[", "]");
        long[] pt = prevCpuTotal, pi = prevCpuIdle;
        long[] nt = new long[rows.size()], ni = new long[rows.size()];
        for (int i = 0; i < rows.size(); i++) {
            nt[i] = rows.get(i)[0];
            ni[i] = rows.get(i)[1];
            double pct = 0;
            if (pt != null && i < pt.length && nt[i] > pt[i]) pct = 100.0 * (1 - (double) (ni[i] - pi[i]) / (nt[i] - pt[i]));
            out.add(String.valueOf(DeckDash.round(Math.max(0, pct), 1)));
        }
        prevCpuTotal = nt;
        prevCpuIdle = ni;
        return out.toString();        // [total, core0, core1, ...]
    }

    static Map<String, Long> meminfo() {
        Map<String, Long> m = new HashMap<>();
        for (String line : read("/proc/meminfo").split("\n")) {
            String[] f = line.split(":\\s+");
            if (f.length == 2) {
                try {
                    m.put(f[0], Long.parseLong(f[1].replace(" kB", "").trim()));
                } catch (NumberFormatException ignored) {
                }
            }
        }
        return m;
    }

    static Map<String, long[]> netDev() {
        Map<String, long[]> m = new HashMap<>();
        for (String line : read("/proc/net/dev").split("\n")) {
            int c = line.indexOf(':');
            if (c < 0) continue;
            String[] f = line.substring(c + 1).trim().split("\\s+");
            if (f.length >= 9) m.put(line.substring(0, c).trim(), new long[]{Long.parseLong(f[0]), Long.parseLong(f[8])});
        }
        return m;
    }

    /** {link quality (of 70), signal dBm} for wlan0, or null. */
    static double[] wireless() {
        for (String line : read("/proc/net/wireless").split("\n")) {
            if (!line.trim().startsWith("wlan0:")) continue;
            String[] f = line.trim().split("\\s+");
            try {
                return new double[]{Double.parseDouble(f[2].replace(".", "")), Double.parseDouble(f[3].replace(".", ""))};
            } catch (NumberFormatException | ArrayIndexOutOfBoundsException e) {
                return null;
            }
        }
        return null;
    }

    static String addresses(String iface) {
        try {
            NetworkInterface ni = NetworkInterface.getByName(iface);
            if (ni == null) return "";
            StringJoiner s = new StringJoiner(" ");
            for (InetAddress a : Collections.list(ni.getInetAddresses())) if (a instanceof Inet4Address) s.add(a.getHostAddress());
            return s.toString();
        } catch (Exception e) {
            return "";
        }
    }

    static List<Map<String, String>> services(long now) {
        List<String> cmd = new ArrayList<>(List.of("systemctl", "show", "-p",
                "Id,ActiveState,SubState,MainPID,NRestarts,MemoryCurrent,CPUUsageNSec,ActiveEnterTimestamp"));
        for (String s : SERVICES) cmd.add(s + ".service");
        String out = exec(3, cmd.toArray(new String[0]));
        List<Map<String, String>> list = new ArrayList<>();
        for (String block : out.split("\n\n")) {
            Map<String, String> kv = new HashMap<>();
            for (String line : block.split("\n")) {
                int e = line.indexOf('=');
                if (e > 0) kv.put(line.substring(0, e), line.substring(e + 1));
            }
            String id = kv.getOrDefault("Id", "");
            if (id.isEmpty()) continue;
            String name = id.replace(".service", "");
            Map<String, String> r = new HashMap<>();
            r.put("name", name);
            r.put("state", kv.getOrDefault("ActiveState", "unknown"));
            r.put("sub", kv.getOrDefault("SubState", ""));
            r.put("pid", kv.getOrDefault("MainPID", "0"));
            r.put("restarts", kv.getOrDefault("NRestarts", "0"));
            r.put("since", kv.getOrDefault("ActiveEnterTimestamp", ""));
            try {
                long m = Long.parseLong(kv.getOrDefault("MemoryCurrent", ""));
                r.put("mem_mb", String.valueOf(DeckDash.round(m / 1048576.0, 1)));
            } catch (NumberFormatException e) {
                // Memory cgroups are disabled on the Pi (cgroup_disable=memory): use the main process's RSS.
                for (String line : read("/proc/" + r.get("pid") + "/status").split("\n"))
                    if (line.startsWith("VmRSS:")) {
                        long kb = Long.parseLong(line.replaceAll("[^0-9]", ""));
                        r.put("mem_mb", String.valueOf(DeckDash.round(kb / 1024.0, 1)));
                    }
            }
            try {
                long ns = Long.parseLong(kv.getOrDefault("CPUUsageNSec", ""));
                long[] p = prevSvcCpu.get(name);
                if (p != null && now > p[1]) r.put("cpu_pct", String.valueOf(DeckDash.round((ns - p[0]) / 1e6 / (now - p[1]) * 100, 1)));
                prevSvcCpu.put(name, new long[]{ns, now});
            } catch (NumberFormatException ignored) {
            }
            list.add(r);
        }
        return list;
    }

    /** port -> (remote IP -> connection count) for established TCP connections from other hosts. */
    static Map<Integer, Map<String, Integer>> connections() {
        Map<Integer, Map<String, Integer>> m = new HashMap<>();
        for (String file : List.of("/proc/net/tcp", "/proc/net/tcp6")) {
            String[] lines = read(file).split("\n");
            for (int i = 1; i < lines.length; i++) {
                String[] f = lines[i].trim().split("\\s+");
                if (f.length < 4 || !"01".equals(f[3])) continue;                 // 01 = ESTABLISHED
                int port = Integer.parseInt(f[1].substring(f[1].indexOf(':') + 1), 16);
                if (!PORTS.containsKey(port)) continue;
                String ip = hexIp(f[2].substring(0, f[2].indexOf(':')));
                if (ip == null || ip.startsWith("127.") || ip.equals("::1")) continue;  // local proxies/polls
                m.computeIfAbsent(port, k -> new HashMap<>()).merge(ip, 1, Integer::sum);
            }
        }
        return m;
    }

    /** /proc/net/tcp{,6} address hex (little-endian 32-bit words) -> dotted IPv4 or compact IPv6. */
    static String hexIp(String h) {
        try {
            if (h.length() == 8) {
                long v = Long.parseLong(h, 16);
                return (v & 0xff) + "." + ((v >> 8) & 0xff) + "." + ((v >> 16) & 0xff) + "." + ((v >> 24) & 0xff);
            }
            if (h.length() == 32) {
                byte[] b = new byte[16];
                for (int w = 0; w < 4; w++)
                    for (int k = 0; k < 4; k++)
                        b[w * 4 + k] = (byte) Integer.parseInt(h.substring(w * 8 + (3 - k) * 2, w * 8 + (3 - k) * 2 + 2), 16);
                boolean mapped = true;
                for (int k = 0; k < 10; k++) if (b[k] != 0) mapped = false;
                if (mapped && b[10] == (byte) 0xff && b[11] == (byte) 0xff)
                    return (b[12] & 0xff) + "." + (b[13] & 0xff) + "." + (b[14] & 0xff) + "." + (b[15] & 0xff);
                return InetAddress.getByAddress(b).getHostAddress().replaceAll("%.*", "");
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    static List<String[]> usbDevices() {
        List<String[]> out = new ArrayList<>();
        File[] devs = new File("/sys/bus/usb/devices").listFiles();
        if (devs == null) return out;
        Arrays.sort(devs);
        for (File d : devs) {
            if (d.getName().contains(":") || d.getName().startsWith("usb")) continue;   // interfaces and root hubs
            String vid = read(d + "/idVendor").trim(), pid = read(d + "/idProduct").trim();
            if (vid.isEmpty()) continue;
            String name = read(d + "/product").trim();
            if (name.isEmpty()) name = vid + ":" + pid;
            out.add(new String[]{vid + ":" + pid, name});
        }
        return out;
    }
}
