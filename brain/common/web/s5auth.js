// Sektor5 admin PIN: shared by every control page (include with <script src="/s5auth.js">).
//
// Anyone can look. Changing anything is admin-only, enforced by each service (a POST without the
// admin cookie gets 401). This script shows VIEW ONLY / ADMIN, asks for the PIN when a change is
// refused, and retries the change once unlocked. The cookie lasts 5 years, per browser and host.
//
// It also sets up the shared top bar (.s5bar, logo in .s5home, which opens the System view from
// /s5system.js) and wires links to the other control pages (<a data-port="8090" data-path="/">, e.g. the top
// bar): greyed out for viewers, and for admins greyed out only if that page can't be reached from
// here (the public link publishes just the dashboard; the rest need the LAN or Tailscale).
(() => {
  "use strict";
  // Start from the last known state so the page draws right first time (no re-greying after load).
  let last = {};
  try { last = JSON.parse(localStorage.getItem("s5auth") || "{}"); } catch (e) { /* private mode */ }
  const S5 = (window.S5AUTH = { enabled: !!last.enabled, admin: last.admin !== false, ready: false });
  const rawFetch = window.fetch.bind(window);

  // The top bar (.s5bar) is identical on every page: same height, logo and page links in the same
  // place, nothing wraps. Page-specific bits in the bar, and the page below it, fade in. Added here,
  // in <head>, so it applies before the first paint.
  const FONT = `"Montserrat", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif`;
  const barCss = `
  html { scrollbar-gutter: stable; }
  .s5bar { box-sizing: border-box; position: sticky; top: 0; z-index: 40; display: flex; flex-wrap: nowrap; align-items: center; gap: 20px;
    height: 64px; min-height: 64px; max-height: 64px; margin: 0; padding: 0 24px; background: #242424; border: 0; border-bottom: 1px solid #3e3e3e;
    font: 500 14px/1 ${FONT}; letter-spacing: .01em; text-transform: none; backdrop-filter: none;
    overflow-x: auto; overflow-y: hidden; scrollbar-width: none; }
  .s5bar::-webkit-scrollbar { display: none; }
  .s5bar > * { flex-shrink: 0; }
  .s5bar > .s5home { flex: 0 0 96px; width: 96px; height: 100%; margin: 0; padding: 0; display: flex; align-items: center; position: relative;
    cursor: pointer; user-select: none; font-size: 14px; line-height: 1; }
  .s5bar > .s5home .s5logo { display: flex; align-items: center; line-height: 1; }
  .s5bar > nav.pages { align-self: stretch; height: 100%; display: flex; gap: 2px; margin: 0; padding: 0; }
  .s5bar > nav.pages a { display: flex; align-items: center; padding: 0 12px; margin: 0; font: 500 14px/1 ${FONT}; letter-spacing: .01em;
    text-transform: none; color: #9a9a9a; text-decoration: none; border-top: 3px solid transparent; border-bottom: 3px solid transparent;
    transition: color .15s, opacity .2s; }
  .s5bar > nav.pages a:hover { color: #f2f2f2; }
  .s5bar > nav.pages a.here { color: #f2f2f2; border-bottom-color: #ff5a1f; }
  html.s5-fontwait .s5bar > nav.pages { visibility: hidden; }
  .s5bar > :not(.s5home):not(nav.pages) { animation: s5in .45s ease both; }
  .s5bar ~ * { animation: s5in .35s ease both; }
  @keyframes s5in { from { opacity: 0; } to { opacity: 1; } }`;
  const barStyle = document.createElement("style");
  barStyle.textContent = barCss;
  document.head.appendChild(barStyle);
  document.documentElement.classList.toggle("s5-viewer", S5.enabled && !S5.admin);
  document.documentElement.classList.toggle("s5-admin", S5.enabled && S5.admin);
  // Page links are drawn in Montserrat: wait for it (cached after the first page) so they don't
  // shift when it swaps in. Offline, fall back to the system font after a moment.
  if (document.fonts && document.fonts.load) {
    document.documentElement.classList.add("s5-fontwait");
    const shown = () => document.documentElement.classList.remove("s5-fontwait");
    Promise.race([document.fonts.load(`500 14px "Montserrat"`), new Promise(r => setTimeout(r, 700))]).then(shown, shown);
  }
  let quietUntil = 0, pending = null;

  const css = `
  .s5a-badge { position: fixed; right: 14px; bottom: 14px; z-index: 9998; font: 600 11px/1 var(--font, system-ui, sans-serif);
    letter-spacing: .14em; text-transform: uppercase; padding: 8px 12px; cursor: pointer; background: rgba(30,30,30,.92);
    color: var(--dim, #9a9a9a); border: 1px solid var(--line2, #555); user-select: none; }
  .s5a-badge.admin { color: var(--good, #7ccf8a); border-color: var(--good, #7ccf8a); }
  .s5a-badge.viewer { color: var(--accent, #ff5a1f); border-color: var(--accent, #ff5a1f); }
  .s5a-back { position: fixed; inset: 0; z-index: 9999; background: rgba(0,0,0,.6); display: flex; align-items: center; justify-content: center; }
  .s5a-box { width: min(92vw, 340px); background: var(--panel, #2b2b2b); border: 1px solid var(--line, #3e3e3e); padding: 26px;
    font: 400 14px/1.45 var(--font, system-ui, sans-serif); color: var(--text, #f2f2f2); }
  .s5a-box h3 { margin: 0 0 6px; font-weight: 500; font-size: 12px; letter-spacing: .16em; text-transform: uppercase; color: var(--dim, #9a9a9a); }
  .s5a-box p { margin: 0 0 16px; color: var(--dim, #9a9a9a); font-size: 13px; }
  .s5a-box input { width: 100%; box-sizing: border-box; font: 300 30px/1.2 var(--font, system-ui, sans-serif); letter-spacing: .3em; text-align: center;
    background: var(--well, #1f1f1f); color: var(--text, #f2f2f2); border: 1px solid var(--line2, #555); padding: 10px; outline: none; }
  .s5a-box input:focus { border-color: var(--accent, #ff5a1f); }
  .s5a-err { min-height: 18px; margin: 10px 0 0; color: var(--bad, #ef5b5b); font-size: 12px; }
  .s5a-row { display: flex; gap: 8px; margin-top: 14px; }
  .s5a-row button { flex: 1; font: 600 11px/1 var(--font, system-ui, sans-serif); letter-spacing: .14em; text-transform: uppercase; padding: 11px;
    cursor: pointer; background: transparent; color: var(--text, #f2f2f2); border: 1px solid var(--line2, #555); }
  a.s5-off { opacity: .32; cursor: not-allowed; }
  .s5a-row button.go { background: var(--accent, #ff5a1f); border-color: var(--accent, #ff5a1f); color: #111; }`;

  function el(tag, attrs = {}, html = "") {
    const e = document.createElement(tag);
    Object.entries(attrs).forEach(([k, v]) => e.setAttribute(k, v));
    e.innerHTML = html;
    return e;
  }

  // Another control page on this host. Over HTTPS (Tailscale), the dashboard is on 443, not 8080;
  // the other pages keep their port (Tailscale serves HTTPS on each).
  S5.url = (port, path = "/") => {
    const https = location.protocol === "https:";
    if (https && +port === 8080) return `https://${location.hostname}${path}`;
    return `${location.protocol}//${location.hostname}:${port}${path}`;
  };
  const reach = {};   // port -> Promise<boolean>
  function reachable(port) {
    const own = location.port || (location.protocol === "https:" ? "443" : "80");
    if (String(port) === own || (location.protocol === "https:" && +port === 8080 && own === "443")) return Promise.resolve(true);
    return (reach[port] ||= rawFetch(S5.url(port, "/s5auth.js"), { mode: "no-cors", cache: "no-store", signal: AbortSignal.timeout(5000) })
      .then(() => true, () => false));
  }
  function links() {
    document.querySelectorAll("a[data-port]").forEach(a => {
      a.href = S5.url(a.dataset.port, a.dataset.path || "/");
      if (a.classList.contains("here")) return;
      const off = why => { a.classList.toggle("s5-off", !!why); a.toggleAttribute("aria-disabled", !!why); a.title = why || a.dataset.title || ""; };
      if (a.dataset.title === undefined) a.dataset.title = a.title || "";
      if (S5.enabled && !S5.admin) return off("Admin only. Unlock with the PIN (bottom right) to open this page.");
      off("");
      reachable(a.dataset.port).then(ok => { if (ok || !S5.admin) return; off("Not reachable from here. Use the rig's Wi-Fi or Tailscale."); });
    });
  }
  document.addEventListener("click", e => {
    const a = e.target.closest && e.target.closest("a.s5-off");
    if (a) { e.preventDefault(); if (S5.enabled && !S5.admin) prompt("That page is admin only. Enter the PIN."); }
  }, true);

  let badge;
  function render() {
    document.documentElement.classList.toggle("s5-viewer", S5.enabled && !S5.admin);
    document.documentElement.classList.toggle("s5-admin", S5.enabled && S5.admin);
    if (!badge) return links();
    badge.style.display = S5.enabled ? "" : "none";
    badge.className = "s5a-badge " + (S5.admin ? "admin" : "viewer");
    badge.textContent = S5.admin ? "Admin" : "View only · unlock";
    badge.title = S5.admin ? "Unlocked on this browser. Click to lock it again." : "Enter the admin PIN to control the rig";
    links();
  }

  async function status() {
    try {
      const r = await rawFetch("/api/auth", { cache: "no-store", credentials: "same-origin" });
      if (r.ok) {
        Object.assign(S5, await r.json());
        try { localStorage.setItem("s5auth", JSON.stringify({ enabled: S5.enabled, admin: S5.admin })); } catch (e) { /* private mode */ }
      }
    } catch (e) { /* offline: keep last known */ }
    S5.ready = true;
    render();
    window.dispatchEvent(new CustomEvent("s5auth", { detail: { ...S5 } }));
  }

  function prompt(reason) {
    if (pending) return pending;
    pending = new Promise(resolve => {
      const back = el("div", { class: "s5a-back" }, `
        <form class="s5a-box" autocomplete="off">
          <h3>Admin PIN</h3>
          <p>${reason || "Enter the PIN to control the rig. This browser stays unlocked."}</p>
          <input type="password" inputmode="numeric" autocomplete="off" aria-label="PIN" maxlength="32">
          <div class="s5a-err"></div>
          <div class="s5a-row"><button type="button" class="no">Cancel</button><button type="submit" class="go">Unlock</button></div>
        </form>`);
      const form = back.querySelector("form"), input = back.querySelector("input"), err = back.querySelector(".s5a-err");
      const done = ok => { back.remove(); pending = null; if (!ok) quietUntil = Date.now() + 10000; resolve(ok); };
      back.querySelector(".no").onclick = () => done(false);
      back.addEventListener("click", e => { if (e.target === back) done(false); });
      back.addEventListener("keydown", e => { if (e.key === "Escape") done(false); });
      form.onsubmit = async e => {
        e.preventDefault();
        err.textContent = "Checking…";
        try {
          const r = await rawFetch("/api/auth", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" },
                                                  body: JSON.stringify({ pin: input.value }) });
          const d = await r.json().catch(() => ({}));
          if (r.ok && d.admin) { S5.admin = true; render(); done(true); return; }
          err.textContent = r.status === 429 ? `Too many attempts. Try again in ${Math.ceil((d.retry_s || 600) / 60)} min.` : "Wrong PIN.";
          input.value = ""; input.focus();
        } catch (e2) { err.textContent = "Can't reach the brain."; }
      };
      document.body.appendChild(back);
      setTimeout(() => input.focus(), 30);
    });
    return pending;
  }

  // Changes (non-GET) need admin: ask for the PIN first if we know we're view-only, and again on 401.
  window.fetch = async (input, init = {}) => {
    const method = String(init.method || (input instanceof Request ? input.method : "GET")).toUpperCase();
    const url = String(input instanceof Request ? input.url : input);
    if (method === "GET" || method === "HEAD" || url.includes("/api/auth") || url.includes("/api/screen")) return rawFetch(input, init);
    const refused = () => new Response(JSON.stringify({ error: "view only" }), { status: 401, headers: { "Content-Type": "application/json" } });
    if (S5.enabled && !S5.admin) {
      if (Date.now() < quietUntil || !(await prompt())) return refused();
    }
    let r = await rawFetch(input, init);
    if (r.status === 401) {
      S5.admin = false; render();
      if (Date.now() >= quietUntil && (await prompt("That needs admin. Enter the PIN."))) r = await rawFetch(input, init);
    }
    return r;
  };

  function mount() {
    const style = el("style"); style.textContent = css; document.head.appendChild(style);
    badge = el("div", { class: "s5a-badge", role: "button", tabindex: "0" });
    badge.style.display = "none";
    badge.onclick = async () => {
      if (!S5.admin) return prompt();
      if (!confirm("Lock this browser? You'll need the PIN again to control the rig.")) return;
      await rawFetch("/api/auth/logout", { method: "POST", credentials: "same-origin" }).catch(() => {});
      status();
    };
    document.body.appendChild(badge);
    render();
    status();
    setInterval(status, 60000);
  }
  if (document.body) mount(); else document.addEventListener("DOMContentLoaded", mount);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", links);

  // The System view (click the logo) lives on the dashboard; every page loads it from there.
  function loadSystem() {
    if (!document.querySelector(".s5bar .s5home") || window.S5SYS) return;
    const sc = document.createElement("script");
    sc.src = S5.url(8080, "/s5system.js");
    sc.async = true;
    document.head.appendChild(sc);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", loadSystem); else loadSystem();
})();
