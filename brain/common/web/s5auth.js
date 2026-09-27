// Sektor5 admin PIN: shared by every control page (include with <script src="/s5auth.js">).
//
// Anyone can look. Changing anything is admin-only, enforced by each service (a POST without the
// admin cookie gets 401). This script shows VIEW ONLY / ADMIN, asks for the PIN when a change is
// refused, and retries the change once unlocked. The cookie lasts 5 years, per browser and host.
(() => {
  "use strict";
  const S5 = (window.S5AUTH = { enabled: false, admin: true, ready: false });
  const rawFetch = window.fetch.bind(window);
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
  .s5a-row button.go { background: var(--accent, #ff5a1f); border-color: var(--accent, #ff5a1f); color: #111; }`;

  function el(tag, attrs = {}, html = "") {
    const e = document.createElement(tag);
    Object.entries(attrs).forEach(([k, v]) => e.setAttribute(k, v));
    e.innerHTML = html;
    return e;
  }

  let badge;
  function render() {
    document.documentElement.classList.toggle("s5-viewer", S5.enabled && !S5.admin);
    document.documentElement.classList.toggle("s5-admin", S5.enabled && S5.admin);
    if (!badge) return;
    badge.style.display = S5.enabled ? "" : "none";
    badge.className = "s5a-badge " + (S5.admin ? "admin" : "viewer");
    badge.textContent = S5.admin ? "Admin" : "View only · unlock";
    badge.title = S5.admin ? "Unlocked on this browser. Click to lock it again." : "Enter the admin PIN to control the rig";
  }

  async function status() {
    try {
      const r = await rawFetch("/api/auth", { cache: "no-store", credentials: "same-origin" });
      if (r.ok) Object.assign(S5, await r.json());
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
})();
