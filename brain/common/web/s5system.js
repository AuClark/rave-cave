// Sektor5 System view: brain health, opened by clicking the logo on any control page.
//
// Served by deckdash (/s5system.js) and loaded by /s5auth.js on every page, so there's one copy.
// Data comes from the dashboard's /api/system (sampled every 2 s by deckdash). It also puts a health
// dot beside the logo. The view's top bar is the page's own bar (.s5bar), so the logo doesn't move.
(() => {
  "use strict";
  if (window.S5SYS) return;
  const API = window.S5AUTH && S5AUTH.url ? S5AUTH.url(8080, "").replace(/\/$/, "") : "";
  const css = `
  #sys { position: fixed; inset: 0; z-index: 9990; background: var(--bg); overflow: auto; display: none; color: var(--text);
    font: 400 14px/1.45 var(--font); letter-spacing: .01em; text-align: left;
    --bg: #242424; --panel: #2b2b2b; --line: #3e3e3e; --line2: #555; --text: #f2f2f2; --dim: #9a9a9a; --accent: #ff5a1f; --accent2: #ff5a1f;
    --good: #7ccf8a; --warn: #f2b84b; --bad: #ef5b5b; --well: #1f1f1f;
    --font: "Montserrat", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; }
  #sys *, #sys *::before { box-sizing: border-box; }
  #sys.open { animation: s5in .25s ease both; }
  #sys.open { display: block; }
    #sys .sys-title { animation: s5in .3s ease both; font-weight: 500; font-size: 13px; letter-spacing: .16em; text-transform: uppercase; color: var(--text);
                    padding-left: 20px; border-left: 1px solid var(--line); line-height: 28px; }
  #sys .sys-top .sp { flex: 1; }
  #sys .sys-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); border-left: 1px solid var(--line);
                   max-width: 1680px; margin: 0 auto; }
  #sys .card { border-right: 1px solid var(--line); border-bottom: 1px solid var(--line); padding: 22px 28px; min-height: 160px; }
  #sys .card h2 { margin: 0 0 16px; font-weight: 500; font-size: 12px; letter-spacing: .16em; text-transform: uppercase; color: var(--dim); }
  #sys .card h2 i { font-style: normal; color: var(--accent); margin-right: 6px; }
  #sys .big { font-weight: 300; font-size: 44px; line-height: 1; font-variant-numeric: tabular-nums; }
  #sys .big small { font-size: 16px; color: var(--dim); margin-left: 4px; }
  #sys .kv { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; border-bottom: 1px solid var(--line); font-size: 13px; }
  #sys .kv:last-child { border-bottom: 0; }
  #sys .kv span { color: var(--dim); } #sys .kv b { font-weight: 500; text-align: right; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
  #sys .bar { height: 6px; background: var(--well); margin: 10px 0 14px; position: relative; }
  #sys .bar div { position: absolute; left: 0; top: 0; bottom: 0; background: var(--good); transition: width .4s; }
  #sys .cores { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-bottom: 12px; }
  #sys .cores div { background: var(--well); height: 42px; position: relative; }
  #sys .cores div i { position: absolute; left: 0; right: 0; bottom: 0; background: var(--accent); opacity: .8; transition: height .4s; }
  #sys .cores div span { position: absolute; left: 6px; top: 4px; font-size: 11px; color: var(--dim); }
  #sys .ok { color: var(--good); } #sys .warn { color: var(--warn); } #sys .bad { color: var(--bad); }
  #sys table { width: 100%; border-collapse: collapse; font-size: 13px; }
  #sys th { text-align: left; font-weight: 500; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: var(--dim);
            padding: 0 6px 8px 0; border-bottom: 1px solid var(--line); }
  #sys td { padding: 7px 6px 7px 0; border-bottom: 1px solid var(--line); font-variant-numeric: tabular-nums; vertical-align: top; }
  #sys td:nth-child(n+3) { white-space: nowrap; }
  #sys .flags { display: flex; flex-wrap: wrap; gap: 6px; }
  #sys .flag { font-size: 11px; font-weight: 600; letter-spacing: .08em; padding: 3px 8px; border: 1px solid var(--line2); color: var(--dim); }
  #sys .flag.bad { border-color: var(--bad); color: var(--bad); } #sys .flag.warn { border-color: var(--warn); color: var(--warn); }
  #sys .flag.ok { border-color: var(--good); color: var(--good); }
  #sys .muted { color: var(--dim); font-size: 12px; }
  #sys .acts { display: flex; gap: 8px; margin-top: 16px; }
  #sys .acts button { flex: 1; font: 600 11px/1 var(--font); letter-spacing: .14em; text-transform: uppercase; padding: 11px 8px; cursor: pointer;
    background: transparent; color: var(--text); border: 1px solid var(--line2); }
  #sys .acts button:hover { border-color: var(--accent); }
  #sys .acts button:disabled { opacity: .4; cursor: wait; }
  #sys a { color: var(--accent2); }
  .s5home .hdot { position: absolute; left: 88px; top: 50%; width: 7px; height: 7px; margin-top: -3.5px; border-radius: 50%; background: #555;
    opacity: 0; transition: opacity .4s, background .4s; }
  .s5home .hdot.ok, .s5home .hdot.warn, .s5home .hdot.bad { opacity: 1; }
  .s5home .hdot.ok { background: #7ccf8a; } .s5home .hdot.warn { background: #f2b84b; } .s5home .hdot.bad { background: #ef5b5b; box-shadow: 0 0 8px #ef5b5b; }`;
  const style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  const home = document.querySelector(".s5bar .s5home");
  const sysEl = document.createElement("div");
  sysEl.id = "sys";
  sysEl.setAttribute("aria-hidden", "true");
  sysEl.innerHTML = `<div class="s5bar sys-top"><div class="s5home" id="sysLogo" title="Back to the app"></div><span class="sys-title">System</span>` +
    `<span class="muted" id="sysHost"></span><span class="sp"></span><span class="muted" id="sysAge"></span></div><div class="sys-grid" id="sysGrid"></div>`;
  document.body.appendChild(sysEl);
  let dot = null;
  if (home) {
    dot = document.createElement("span");
    dot.className = "hdot";
    home.appendChild(dot);
    home.title = "System";
    home.addEventListener("click", () => sysOpen(!sysEl.classList.contains("open")));
    // Same logo, same place: the System bar reuses the page's own.
    const logo = home.querySelector(".s5logo");
    if (logo) sysEl.querySelector("#sysLogo").appendChild(logo.cloneNode(true));
  }
  sysEl.querySelector("#sysLogo").addEventListener("click", () => sysOpen(false));

  let sysTimer = null, sysLast = null;
  const fmtUp = s => { const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"; };
  const lvl = (v, warn, bad, higherIsWorse = true) => higherIsWorse ? (v >= bad ? "bad" : v >= warn ? "warn" : "ok")
                                                                     : (v <= bad ? "bad" : v <= warn ? "warn" : "ok");
  const kvs = rows => rows.filter(Boolean).map(([k, v, c]) => `<div class="kv"><span>${k}</span><b class="${c || ""}">${v}</b></div>`).join("");
  function sysHealth(d) {
    const t = d.throttle || {}, worst = [];
    if (d.cpu.temp_c >= 80 || t.under_voltage_now || t.throttled_now || d.disk.free_gb < 1 ||
        (d.services || []).some(s => s.state !== "active")) worst.push("bad");
    if (d.cpu.temp_c >= 70 || t.under_voltage_since_boot || t.throttled_since_boot || t.soft_temp_limit_now ||
        d.disk.free_gb < 3 || d.memory.used_mb / d.memory.total_mb > 0.85 || (d.network.wifi.signal_dbm && d.network.wifi.signal_dbm < -75) ||
        (d.services || []).some(s => s.restarts > 0)) worst.push("warn");
    return worst.includes("bad") ? "bad" : worst.includes("warn") ? "warn" : "ok";
  }
  function sysRender(d) {
    document.getElementById("sysHost").textContent = d.host;
    const u = d.cpu.usage || [0], t = d.throttle, m = d.memory, memPct = m.used_mb / m.total_mb * 100;
    const tempC = lvl(d.cpu.temp_c, 70, 80), cpuC = lvl(u[0], 75, 90), memC = lvl(memPct, 75, 90), diskC = lvl(d.disk.free_gb, 3, 1, false);
    const flag = (on, since, label) => `<span class="flag ${on ? "bad" : since ? "warn" : "ok"}">${label}${on ? " NOW" : since ? " SINCE BOOT" : ""}</span>`;
    const wifi = d.network.wifi, sig = wifi.signal_dbm, sigC = sig ? lvl(sig, -70, -80, false) : "";
    const card = (n, title, body) => `<section class="card"><h2><i>${String(n).padStart(2, "0")}</i>— ${title}</h2>${body}</section>`;
    const svcRows = (d.services || []).map(s => `<tr><td>${s.name}</td><td class="${s.state === "active" ? "ok" : "bad"}">${s.state === "active" ? s.sub : s.state}</td>
      <td>${s.cpu_pct >= 0 ? s.cpu_pct.toFixed(1) + "%" : "–"}</td><td>${s.mem_mb >= 0 ? Math.round(s.mem_mb) + " MB" : "–"}</td>
      <td class="${s.restarts ? "warn" : ""}">${s.restarts}</td></tr>`).join("");
    const cl = d.clients || { ports: [] };
    const clRows = cl.ports.map(p => `<tr><td>${p.page}<div class="muted">:${p.port}</div></td><td>${p.devices}</td>
      <td class="muted">${p.addresses.length ? p.addresses.map(a => a.startsWith("fe80") ? "IPv6 link-local" : a).join("<br>") : "–"}</td></tr>`).join("");
    document.getElementById("sysGrid").innerHTML = [
      card(1, "Temperature", `<div class="big ${tempC}">${d.cpu.temp_c.toFixed(1)}<small>°C</small></div>
        <div class="bar"><div style="width:${Math.min(100, d.cpu.temp_c / 85 * 100)}%;background:var(--${tempC === "ok" ? "good" : tempC})"></div></div>
        <div class="flags">${flag(t.under_voltage_now, t.under_voltage_since_boot, "UNDER-VOLTAGE")}${flag(t.throttled_now, t.throttled_since_boot, "THROTTLED")}
        ${flag(t.freq_capped_now, t.freq_capped_since_boot, "FREQ CAP")}${flag(t.soft_temp_limit_now, t.soft_temp_limit_since_boot, "TEMP LIMIT")}</div>`),
      card(2, "CPU", `<div class="big ${cpuC}">${u[0].toFixed(0)}<small>%</small></div><div class="bar"><div style="width:${u[0]}%"></div></div>
        <div class="cores">${u.slice(1).map((c, i) => `<div><i style="height:${c}%"></i><span>${i} · ${c.toFixed(0)}%</span></div>`).join("")}</div>
        ${kvs([["Load (1/5/15 min)", d.cpu.load.split(" ").slice(0, 3).join(" · ")], ["Clock", d.cpu.mhz + " MHz"], ["Uptime", fmtUp(d.uptime_s)]])}`),
      card(3, "Memory", `<div class="big ${memC}">${Math.round(memPct)}<small>%</small></div><div class="bar"><div style="width:${memPct}%"></div></div>
        ${kvs([["Used", `${m.used_mb} / ${m.total_mb} MB`], ["Available", m.available_mb + " MB"], ["Swap used", `${m.swap_used_mb} / ${m.swap_total_mb} MB`, m.swap_used_mb > 100 ? "warn" : ""],
               ["deckdash heap", `${d.deckdash_jvm.heap_used_mb} / ${d.deckdash_jvm.heap_max_mb} MB`]])}`),
      card(4, "Storage", `<div class="big ${diskC}">${d.disk.free_gb}<small>GB free</small></div>
        <div class="bar"><div style="width:${(1 - d.disk.free_gb / d.disk.total_gb) * 100}%"></div></div>
        ${kvs([["Total", d.disk.total_gb + " GB"], ["Set recordings", `${d.disk.recordings_gb} GB · ${d.disk.recordings_files} files`]])}`),
      card(5, "Network", kvs([
        ["Wi-Fi signal", sig ? `${sig} dBm · ${wifi.quality_pct}%` : "–", sigC],
        ...d.network.interfaces.map(i => [i.name === "wlan0" ? "Wi-Fi (fixtures)" : "Ethernet (decks)",
          `${i.up ? "" : "DOWN · "}${i.addresses || "no address"}<div class="muted">↓ ${i.rx_kbps >= 1000 ? (i.rx_kbps / 1000).toFixed(1) + " Mb/s" : i.rx_kbps + " kb/s"} · ↑ ${i.tx_kbps >= 1000 ? (i.tx_kbps / 1000).toFixed(1) + " Mb/s" : i.tx_kbps + " kb/s"}</div>`,
          i.up ? "" : "bad"])])),
      card(6, "Services", `<table><tr><th>Service</th><th>State</th><th>CPU</th><th>Mem</th><th>Restarts</th></tr>${svcRows}</table>`),
      card(7, "Clients", `<div class="big">${cl.devices}<small>devices</small></div>
        <p class="muted">${cl.dashboard_streams} live dashboard stream${cl.dashboard_streams === 1 ? "" : "s"}</p>
        <table><tr><th>Page</th><th>Devices</th><th>From</th></tr>${clRows}</table>`),
      card(8, "Hardware", kvs([
        ["DJ Link devices", d.djlink_devices],
        ...(d.usb || []).map(x => [x.name, `<span class="muted">${x.id}</span>`]),
        !(d.usb || []).some(x => x.id === "2b73:0013") && ["DJM-450", "not connected", "warn"],
        !(d.usb || []).some(x => x.id === "16c0:05dc") && ["uDMX (par can)", "not connected", "warn"]])),
      card(9, "Tailscale", tsCard(d.tailscale || {})),
    ].join("");
  }
  // Tailscale: the public link (Funnel, dashboard only) and remote access for the team.
  function tsCard(ts) {
    if (!ts.installed) return `<div class="big warn">Not installed</div>`;
    const on = ts.state === "Running", label = { Running: "Connected", Stopped: "Off", NeedsLogin: "Needs login", Starting: "Starting" }[ts.state] || ts.state;
    return `<div class="big ${on ? "ok" : "warn"}">${label}</div>
      ${kvs([
        ["Name", ts.dns_name || "–"],
        ["Address", (ts.ips || [])[0] || "–"],
        ["Tailnet", ts.tailnet || "–"],
        ["Devices online", on ? `${ts.peers_online} of ${ts.peers}` : "–"],
        ["Public link", ts.funnel ? `<a href="${ts.public_url}" target="_blank" rel="noopener">${ts.public_url.replace(/^https:\/\/|\/$/g, "")}</a>` : "off", ts.funnel ? "ok" : ""],
        ["Tailnet-only HTTPS", (ts.https_ports || []).filter(p => p !== 443).map(p => ":" + p).join(" ") || "–"],
        ts.auth_url && ["Log in", `<a href="${ts.auth_url}" target="_blank" rel="noopener">approve this device</a>`, "warn"],
        ["Version", (ts.version || "").split("-")[0]],
      ])}
      <div class="acts">
        ${on ? `<button data-ts='{"funnel":${!ts.funnel}}'>${ts.funnel ? "Turn off public link" : "Turn on public link"}</button>` : ""}
        <button data-ts='{"up":${!on}}'>${on ? "Turn off Tailscale" : "Turn on Tailscale"}</button>
      </div>`;
  }
  document.getElementById("sysGrid").addEventListener("click", async e => {
    const b = e.target.closest("button[data-ts]");
    if (!b) return;
    const req = JSON.parse(b.dataset.ts), viaTs = /\.ts\.net$|^100\./.test(location.hostname);
    if (req.funnel === false && !confirm("Turn off the public link? The dashboard stays available on the tailnet.")) return;
    if (req.up === false && !confirm(viaTs
        ? "You're connected through Tailscale. Turning it off cuts this page off, and the public link goes too. Turn it back on from the rig's Wi-Fi. Continue?"
        : "Turn off Tailscale? Remote access and the public link stop until it's turned back on.")) return;
    b.disabled = true; b.textContent = "Working…";
    try {
      const r = await fetch(API + "/api/system/tailscale", { method: "POST", credentials: "include", headers: { "Content-Type": "text/plain" }, body: JSON.stringify(req) });
      if (r.ok && sysLast) { sysLast.tailscale = await r.json(); sysRender(sysLast); }
    } catch (e2) { /* lost the connection (e.g. Tailscale off while using it) */ }
    sysPoll();
  });
  async function sysPoll() {
    try {
      const d = await (await fetch(API + "/api/system", { cache: "no-store" })).json();
      if (!d.ready) return;
      sysLast = d;
      const h = sysHealth(d);
      if (dot) dot.className = "hdot " + h;
      if (dot) dot.title = h === "ok" ? "System healthy" : h === "warn" ? "System: needs a look" : "System: problem";
      if (sysEl.classList.contains("open")) { sysRender(d); document.getElementById("sysAge").textContent = "updated " + new Date(d.ts).toLocaleTimeString(); }
    } catch (e) { if (dot) { dot.className = "hdot bad"; dot.title = "Can't reach the dashboard"; } }
  }
  function sysOpen(on) {
    sysEl.classList.toggle("open", on); sysEl.setAttribute("aria-hidden", on ? "false" : "true");
    clearInterval(sysTimer);
    sysTimer = setInterval(sysPoll, on ? 2000 : 10000);
    if (on) { if (sysLast) sysRender(sysLast); sysPoll(); }
  }
  addEventListener("keydown", e => { if (e.key === "Escape" && sysEl.classList.contains("open")) sysOpen(false); });
  window.S5SYS = { open: () => sysOpen(true), close: () => sysOpen(false) };
  sysOpen(false); sysPoll();
})();
