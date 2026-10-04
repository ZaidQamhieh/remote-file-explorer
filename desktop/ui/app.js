(function () {
  const invoke = window.__TAURI__.core.invoke;
  const $ = (id) => document.getElementById(id);
  const steps = ["step-connect", "step-trust", "step-login", "step-approve", "step-devices", "step-settings"];
  let pending = { host: "", fingerprint: "" };
  let current = { signedIn: false };
  let settingsReturn = "step-connect";

  function show(step) {
    for (const id of steps) $(id).hidden = id !== step;
    // Keyboard and screen reader users are not left on a control that just disappeared: focus
    // goes to the new screen's heading, which is read out.
    const title = $(step.replace("step-", "title-"));
    if (title) title.focus();
  }

  function say(text, isError) {
    const el = $("message");
    el.hidden = !text;
    el.textContent = text || "";
    el.classList.toggle("error", !!isError);
    // An error interrupts a screen reader; progress and results wait their turn.
    el.setAttribute("role", isError ? "alert" : "status");
  }

  function submitter(ev) {
    return ev.submitter || ev.target.querySelector('button[type="submit"]');
  }

  // `busy` is shown while the call is in flight (the agent may take up to ten seconds to answer),
  // then removed unless something else has been said in the meantime.
  async function run(button, fn, busy) {
    button.disabled = true;
    say(busy || "");
    try {
      await fn();
    } catch (e) {
      say(String(e), true);
    } finally {
      button.disabled = false;
      if (busy && $("message").textContent === busy) say("");
    }
  }

  // The connect screen lists the agents already trusted, so a pin can be reviewed or forgotten.
  const connectPins = () => ({
    body: $("pins"),
    block: $("pins-block"),
    empty: null,
    refresh: showConnect,
  });
  const settingsPins = () => ({
    body: $("settings-pins"),
    block: null,
    empty: $("settings-pins-empty"),
    refresh: async () => renderPins(await invoke("list_pins"), settingsPins()),
  });

  async function showConnect() {
    show("step-connect");
    try {
      renderPins(await invoke("list_pins"), connectPins());
    } catch (e) {
      say(String(e), true);
    }
  }

  function renderPins(list, view) {
    const body = view.body;
    body.replaceChildren();
    for (const p of list) {
      const forget = document.createElement("button");
      forget.type = "button";
      forget.className = "link";
      forget.textContent = "Forget";
      forget.setAttribute("aria-label", "Forget " + p.host);
      forget.addEventListener("click", () => {
        // Two clicks: the first only arms the button.
        if (!forget.dataset.armed) {
          forget.dataset.armed = "1";
          forget.textContent = p.active ? "Forget and sign out?" : "Forget?";
          forget.setAttribute("aria-label", forget.textContent + " " + p.host + " Press again to confirm.");
          return;
        }
        run(forget, async () => {
          const out = await invoke("forget_pin", { host: p.host });
          if (out.signedOut) {
            renderDevices([]);
            setSession({ signedIn: false });
          }
          await view.refresh();
          if (view.empty) settingsAccount();
        });
      });
      const host = cell(p.host + (p.active ? " (signed in)" : ""));
      const fp = cell(p.fingerprint, "mono");
      const act = document.createElement("td");
      act.append(forget);
      const tr = document.createElement("tr");
      tr.append(host, fp, act);
      body.append(tr);
    }
    if (view.block) view.block.hidden = list.length === 0;
    if (view.empty) view.empty.hidden = list.length !== 0;
  }

  function when(unixSeconds) {
    if (!unixSeconds) return "never";
    return new Date(unixSeconds * 1000).toLocaleString();
  }

  function cell(text, className) {
    const td = document.createElement("td");
    td.textContent = text;
    if (className) td.className = className;
    return td;
  }

  function renderDevices(list) {
    const body = $("devices");
    body.replaceChildren();
    for (const d of list) {
      const tr = document.createElement("tr");
      tr.append(
        cell(d.label + (d.current ? " (this computer)" : "")),
        cell(when(d.lastSeen)),
        cell(d.lastAddress || "unknown"),
        cell(d.lastVersion || "unknown"),
        cell(d.revoked ? "Revoked" : "Active", d.revoked ? "tag revoked" : "tag")
      );
      body.append(tr);
    }
    $("devices-empty").hidden = list.length !== 0;
    // An ordinary device is shown only itself; say why, so a short list does not look like a bug.
    $("devices-note").hidden = !(list.length === 1 && !list[0].viaLogin);
  }

  async function showDevices() {
    // Fetch first: a failure must not leave an empty or stale list on screen.
    let list;
    try {
      list = await invoke("list_devices");
    } catch (e) {
      // The agent may have refused the saved login (revoked or removed there). The app then
      // dropped the token but kept the pin, so go back to sign-in on that agent.
      const saved = await invoke("saved_agent").catch(() => null);
      if (saved && saved.host && saved.fingerprint && !saved.signedIn) {
        setSession(saved);
        pending = { host: saved.host, fingerprint: saved.fingerprint };
        $("username").value = saved.username;
        show("step-login");
        loginMode(false);
      }
      throw e;
    }
    renderDevices(list);
    // The list can arrive after the user opened Settings; do not pull them out of it. Back goes here.
    if ($("step-settings").hidden) show("step-devices");
    else settingsReturn = "step-devices";
  }

  function setSession(saved) {
    current = saved;
    const on = saved.signedIn;
    $("session").hidden = !on;
    $("session-text").textContent = on ? (saved.username ? saved.username + " on " : "Paired with ") + saved.host : "";
  }

  // Settings: opens over whatever screen is showing and Back returns to it.
  function settingsAccount() {
    const c = current;
    $("settings-account").textContent = c.signedIn
      ? c.username
        ? "Signed in as " + c.username + " on " + c.host + "."
        : "Paired with " + c.host + " (no account; this computer can list and manage only itself)."
      : "Not signed in.";
    $("settings-device").hidden = !(c.signedIn && c.deviceId);
    $("settings-device").textContent = c.deviceId ? "This computer is device " + c.deviceId : "";
  }

  async function showSettings() {
    const from = steps.find((id) => !$(id).hidden);
    if (from && from !== "step-settings") settingsReturn = from;
    show("step-settings");
    say("");
    settingsAccount();
    $("keystore-result").textContent = "";
    $("keystore-result").className = "";
    $("diagnostics").hidden = true;
    $("diagnostics").value = "";
    $("copy-diagnostics").hidden = true;
    $("diagnostics-result").textContent = "";
    try {
      const [info, pins] = await Promise.all([invoke("app_settings"), invoke("list_pins")]);
      $("log-level").value = info.logLevel;
      $("log-level").dataset.saved = info.logLevel;
      $("about-version").textContent = info.appVersion;
      $("about-client").textContent = info.clientVersion;
      $("about-approval").textContent = info.minAgentForApproval + " or newer";
      $("about-platform").textContent = info.platform;
      $("about-data").textContent = info.dataDir;
      renderPins(pins, settingsPins());
    } catch (e) {
      say(String(e), true);
    }
  }

  $("open-settings").addEventListener("click", showSettings);
  $("settings-back").addEventListener("click", () => {
    say("");
    // The screen underneath may have ended while Settings was open (signed out here, or the
    // approval loop finished); do not return to a screen that no longer applies.
    if (settingsReturn === "step-devices" && !current.signedIn) return showConnect();
    if (settingsReturn === "step-approve" && liveLoops === 0) settingsReturn = "step-login";
    show(settingsReturn);
  });

  $("check-keystore").addEventListener("click", (ev) =>
    run(
      ev.currentTarget,
      async () => {
        const result = $("keystore-result");
        result.textContent = "";
        try {
          await invoke("check_keystore");
          result.textContent = "Works: a test secret was saved, read back and removed.";
          result.className = "tag";
        } catch (e) {
          result.textContent = "Not working.";
          result.className = "tag revoked";
          throw e;
        }
      },
      "Testing the keystore (it may ask you to unlock it)..."
    )
  );

  $("make-diagnostics").addEventListener("click", (ev) =>
    run(
      ev.currentTarget,
      async () => {
        const box = $("diagnostics");
        box.value = await invoke("diagnostics");
        box.hidden = false;
        $("copy-diagnostics").hidden = false;
        $("diagnostics-result").textContent = "";
      },
      "Creating the report..."
    )
  );

  $("copy-diagnostics").addEventListener("click", async () => {
    const box = $("diagnostics");
    const result = $("diagnostics-result");
    try {
      await navigator.clipboard.writeText(box.value);
      result.textContent = "Copied.";
    } catch (e) {
      // No clipboard access: select the text so Ctrl+C works.
      box.focus();
      box.select();
      result.textContent = "Select all and press Ctrl+C to copy.";
    }
  });

  $("log-level").addEventListener("change", async () => {
    const select = $("log-level");
    const wanted = select.value;
    say("");
    try {
      select.dataset.saved = await invoke("set_log_level", { level: wanted });
    } catch (e) {
      select.value = select.dataset.saved || "info";
      say(String(e), true);
    }
  });

  // Finding agents on the network only fills in the address box. Nothing is probed and nothing
  // is trusted until the user presses "Check certificate" and compares the fingerprint.
  function renderFound(list) {
    const body = $("found");
    body.replaceChildren();
    for (const f of list) {
      const use = document.createElement("button");
      use.type = "button";
      use.className = "link";
      use.textContent = "Use";
      use.setAttribute("aria-label", "Use " + f.hostport + (f.name ? " (" + f.name + ")" : ""));
      use.addEventListener("click", () => {
        $("host").value = f.hostport;
        $("host").focus();
        say("Address filled in. Press Check certificate, then compare the fingerprint with the PC.");
      });
      const act = document.createElement("td");
      act.append(use);
      const tr = document.createElement("tr");
      tr.append(
        cell(f.name || "agent"),
        cell(f.hostport + (f.known ? " (trusted before)" : ""), "mono"),
        cell(f.version || "unknown"),
        act
      );
      body.append(tr);
    }
    $("found-wrap").hidden = list.length === 0;
  }

  $("discover").addEventListener("click", (ev) =>
    run(
      ev.currentTarget,
      async () => {
        const status = $("discover-status");
        status.textContent = "";
        renderFound([]);
        const list = await invoke("discover_agents");
        renderFound(list);
        status.textContent = list.length
          ? list.length + (list.length === 1 ? " agent found." : " agents found.")
          : "No agents found. It may be on another network, or the network blocks mDNS; type the address instead.";
      },
      "Looking for agents (a few seconds)..."
    )
  );

  $("connect-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    const host = $("host").value.trim();
    run(submitter(ev), async () => {
      const probe = await invoke("probe_agent", { host });
      pending = { host, fingerprint: probe.fingerprint };
      $("fingerprint").textContent = probe.fingerprint;
      const warn = $("changed");
      warn.hidden = !probe.changed;
      warn.textContent = probe.changed
        ? "This agent's certificate is different from the one you trusted before (" + probe.previous.slice(0, 16) + "...). Only continue if you replaced or reinstalled the agent."
        : "";
      $("trust").textContent = probe.changed ? "I know it changed, trust the new certificate" : "They match, trust this agent";
      show("step-trust");
    }, "Reading the agent's certificate...");
  });

  $("trust").addEventListener("click", () => {
    show("step-login");
    loginMode(false);
  });
  $("trust-cancel").addEventListener("click", () => {
    pending = { host: "", fingerprint: "" };
    showConnect();
  });

  $("login-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    run(submitter(ev), async () => {
      const saved = await invoke("login", {
        host: pending.host,
        fingerprint: pending.fingerprint,
        username: $("username").value.trim(),
        password: $("password").value,
      });
      $("password").value = "";
      setSession(saved);
      await showDevices();
    }, "Signing in...");
  });

  function loginMode(code) {
    $("login-form").hidden = code;
    $("pair-form").hidden = !code;
    $(code ? "pairing-code" : "username").focus();
  }
  $("use-code").addEventListener("click", () => loginMode(true));
  $("use-account").addEventListener("click", () => loginMode(false));

  $("pair-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    run(submitter(ev), async () => {
      const saved = await invoke("pair_with_code", {
        host: pending.host,
        fingerprint: pending.fingerprint,
        code: $("pairing-code").value.trim(),
      });
      $("pairing-code").value = "";
      setSession(saved);
      await showDevices();
    }, "Pairing...");
  });

  // Approve on the PC: show the match code, then ask the agent every two seconds until the
  // owner answers. `waiting` changes on cancel so an old loop stops by itself.
  let waiting = 0;
  let liveLoops = 0;
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  async function askPcToApprove() {
    liveLoops++;
    try {
      await askPcToApproveLoop();
    } finally {
      liveLoops--;
    }
  }

  async function askPcToApproveLoop() {
    const me = ++waiting;
    const wait = await invoke("request_pairing", {
      host: pending.host,
      fingerprint: pending.fingerprint,
    });
    $("match-code").textContent = wait.matchCode;
    $("approve-status").textContent = "Waiting for the PC...";
    show("step-approve");
    const give_up = Date.now() + (wait.expiresInSeconds + 10) * 1000;
    while (me === waiting && Date.now() < give_up) {
      await sleep(2000);
      if (me !== waiting) return;
      const out = await invoke("poll_pairing");
      if (out.status === "approved") {
        setSession(out.saved);
        await showDevices();
        return;
      }
      if (out.status === "rejected") throw "The request was rejected on the PC.";
      if (out.status === "expired") throw "The request expired or was already used. Ask again.";
    }
    if (me === waiting) throw "The request timed out. Ask again.";
  }

  $("use-approval").addEventListener("click", (ev) =>
    run(ev.currentTarget, async () => {
      try {
        await askPcToApprove();
      } catch (e) {
        // Back to sign-in with the reason; a stale loop must not move the screen.
        waiting++;
        show("step-login");
        throw e;
      }
    })
  );

  $("approve-cancel").addEventListener("click", async () => {
    waiting++;
    try {
      await invoke("cancel_pairing");
    } finally {
      show("step-login");
    }
  });

  // Two clicks, and only from here: the app never replaces the device key by itself.
  $("reset-key").addEventListener("click", (ev) => {
    const b = ev.currentTarget;
    if (!b.dataset.armed) {
      b.dataset.armed = "1";
      b.textContent = "Click again to create a new device key";
      return;
    }
    run(b, async () => {
      await invoke("reset_device_key");
      delete b.dataset.armed;
      b.textContent = "Create a new device key for this computer";
      say("A new device key will be created the next time you sign in. The old one stays registered on the agent until it is removed there.");
    });
  });

  $("pair-back").addEventListener("click", () => {
    $("pairing-code").value = "";
    loginMode(false);
    showConnect();
  });

  $("login-back").addEventListener("click", () => {
    $("password").value = "";
    showConnect();
  });

  $("refresh").addEventListener("click", (ev) =>
    run(ev.currentTarget, showDevices, "Loading devices...")
  );

  $("sign-out").addEventListener("click", (ev) =>
    run(ev.currentTarget, async () => {
      const out = await invoke("sign_out");
      renderDevices([]);
      setSession({ signedIn: false });
      showConnect();
      if (out.note) say(out.note, true);
    }, "Signing out...")
  );

  (async function start() {
    try {
      // Reading the saved login can wait on the OS keystore's unlock prompt.
      say("Opening your saved login from the OS keystore (it may ask you to unlock it)...");
      const saved = await invoke("saved_agent");
      say("");
      if (saved.host) $("host").value = saved.host;
      setSession(saved);
      if (saved.signedIn) {
        say("Loading devices...");
        await showDevices();
        say("");
        return;
      }
    } catch (e) {
      say(String(e), true);
      // showDevices may already have moved to sign-in; do not override that.
      if (!$("step-login").hidden) return;
    }
    showConnect();
  })();

  // ---- feature:audit-logs ----
  // The agent's audit trail and log tail (admin only). Every string below came from the agent and
  // can carry text chosen by a stranger (a username tried at sign-in), so it only ever goes in
  // through textContent and is shortened first.
  steps.push("step-audit");

  const AUDIT_NAMES = {
    pair: "Device paired",
    register: "Account registered",
    login: "Signed in",
    login_failed: "Failed sign-in",
    device_revoked: "Device revoked",
    device_removed: "Device removed",
    device_updated: "Device changed",
    share_created: "Share link created",
    share_revoked: "Share link revoked",
    agent_restart: "Agent restarted",
    app_launch: "App launched",
  };
  const AUDIT_BAD = new Set(["login_failed", "device_revoked", "device_removed"]);
  const AUDIT_CAP = { action: 40, actor: 80, target: 120, detail: 160, message: 400, time: 40 };
  const auditState = { entries: [], next: null, forbidden: false, error: "", logs: [], logsLoaded: false, auditLoaded: false, seq: 0 };

  // Control characters and bidirectional overrides become spaces; long text is cut with an ellipsis.
  function auditClip(text, max) {
    const s = String(text == null ? "" : text).replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, " ");
    const chars = Array.from(s);
    return chars.length > max ? chars.slice(0, max).join("") + "…" : s;
  }

  // Local time for reading; the agent's own timestamp stays in the title attribute.
  function auditCell(text, title, className) {
    const td = cell(text, className);
    if (title) td.setAttribute("title", title);
    return td;
  }
  function auditTimeCell(iso) {
    const raw = auditClip(iso, AUDIT_CAP.time);
    const ms = Date.parse(raw);
    return Number.isNaN(ms) ? auditCell(raw || "unknown", raw) : auditCell(new Date(ms).toLocaleString(), raw);
  }
  function inAuditWindow(iso) {
    const secs = Number($("audit-time").value) || 0;
    if (!secs) return true;
    const ms = Date.parse(iso);
    return !Number.isNaN(ms) && ms >= Date.now() - secs * 1000;
  }
  const auditIsLogs = () => $("audit-view").value === "logs";

  function renderAuditTypes() {
    const sel = $("audit-type");
    const kept = sel.value || "";
    const seen = new Set(Object.keys(AUDIT_NAMES));
    for (const e of auditState.entries) seen.add(auditClip(e.action, AUDIT_CAP.action));
    const opts = [["", "All events"]];
    for (const a of seen) opts.push([a, AUDIT_NAMES[a] || a]);
    sel.replaceChildren(
      ...opts.map(([value, label]) => {
        const o = document.createElement("option");
        o.value = value;
        o.textContent = label;
        return o;
      })
    );
    sel.value = seen.has(kept) ? kept : "";
  }

  function renderAudit() {
    const wantLogs = auditIsLogs();
    $("audit-wrap").hidden = wantLogs || auditState.forbidden;
    $("log-wrap").hidden = !wantLogs || auditState.forbidden;
    $("audit-type-wrap").hidden = wantLogs;
    $("audit-text-wrap").hidden = !wantLogs;
    $("audit-forbidden").hidden = !auditState.forbidden;
    $("audit-forbidden").textContent = auditState.forbidden
      ? "This login cannot read the audit log or the agent log. Only an account sign-in (an admin device) can; a pairing code or an approval on the PC gives an ordinary device. Sign out and sign in with an account."
      : "";
    $("audit-error").hidden = !auditState.error;
    $("audit-error").textContent = auditState.error;
    const caption = $("audit-count");
    const empty = $("audit-empty");
    if (auditState.forbidden) {
      caption.textContent = "";
      empty.hidden = true;
      $("audit-more").hidden = true;
      return;
    }
    let rows;
    let loaded;
    if (wantLogs) {
      const needle = $("audit-text").value.trim().toLowerCase();
      loaded = auditState.logs.length;
      // The agent sends oldest first; the screen shows newest first like the audit log.
      rows = auditState.logs.filter((l) => inAuditWindow(l.ts) && (!needle || String(l.message).toLowerCase().includes(needle))).reverse();
      const body = $("log-body");
      body.replaceChildren();
      for (const l of rows) {
        const tr = document.createElement("tr");
        tr.append(auditTimeCell(l.ts), auditCell(auditClip(l.message, AUDIT_CAP.message)));
        body.append(tr);
      }
    } else {
      const type = $("audit-type").value;
      loaded = auditState.entries.length;
      rows = auditState.entries.filter((e) => (!type || e.action === type) && inAuditWindow(e.at));
      const body = $("audit-body");
      body.replaceChildren();
      for (const e of rows) {
        const action = auditClip(e.action, AUDIT_CAP.action);
        const target = auditClip(e.target, AUDIT_CAP.target);
        const detail = auditClip(e.detail, AUDIT_CAP.detail);
        const tr = document.createElement("tr");
        tr.append(
          auditTimeCell(e.at),
          auditCell(AUDIT_NAMES[action] || action, action, AUDIT_BAD.has(action) ? "tag revoked" : ""),
          auditCell(auditClip(e.actor, AUDIT_CAP.actor) || "unknown"),
          auditCell(target, target.length < String(e.target || "").length ? auditClip(e.target, 400) : ""),
          auditCell(detail, detail.length < String(e.detail || "").length ? auditClip(e.detail, 400) : "")
        );
        body.append(tr);
      }
    }
    const loadedAll = wantLogs || !auditState.next;
    caption.textContent =
      rows.length + " shown of " + loaded + " loaded." +
      (wantLogs ? " The agent sends only its last lines." : loadedAll ? " That is every event the agent kept." : " Older events are available: press Load more.");
    empty.hidden = rows.length !== 0 || !!auditState.error;
    if (rows.length === 0) {
      empty.textContent = wantLogs
        ? loaded === 0
          ? "The agent's log is empty. The agent reads it from the systemd journal, so it is empty when the agent does not run as the rfe-agent service."
          : "No log line matches these filters."
        : loaded === 0
          ? "The audit log is empty. Nothing has been recorded yet."
          : "No loaded event matches these filters." + (loadedAll ? "" : " Press Load more to look further back.");
    }
    $("audit-more").hidden = wantLogs || !auditState.next;
  }

  // The agent may have refused the saved login (revoked or removed there); the app then dropped the
  // token, so go back to sign-in like the device list does.
  async function auditBackToSignIn() {
    const saved = await invoke("saved_agent").catch(() => null);
    if (saved && saved.host && saved.fingerprint && !saved.signedIn) {
      setSession(saved);
      pending = { host: saved.host, fingerprint: saved.fingerprint };
      $("username").value = saved.username;
      show("step-login");
      loginMode(false);
      return true;
    }
    return false;
  }

  // Loads the newest page (more = false) or the next older one. A newer request or a change of view
  // makes an older answer stale: it is dropped.
  async function loadAudit(more) {
    const me = ++auditState.seq;
    const logs = auditIsLogs();
    try {
      if (logs) {
        const reply = await invoke("agent_log");
        if (me !== auditState.seq) return;
        auditState.forbidden = !!reply.forbidden;
        auditState.logs = reply.lines || [];
        auditState.logsLoaded = true;
      } else {
        const reply = await invoke("audit_page", { before: more ? auditState.next : null });
        if (me !== auditState.seq) return;
        auditState.forbidden = !!reply.forbidden;
        if (more) {
          const seen = new Set(auditState.entries.map((e) => e.id));
          auditState.entries = auditState.entries.concat((reply.entries || []).filter((e) => !seen.has(e.id)));
        } else {
          auditState.entries = reply.entries || [];
        }
        auditState.next = reply.forbidden ? null : reply.nextBefore == null ? null : reply.nextBefore;
        auditState.auditLoaded = true;
      }
      auditState.error = "";
    } catch (e) {
      if (me !== auditState.seq) return;
      auditState.error = String(e);
      if (await auditBackToSignIn()) say(String(e), true);
    }
    if (me !== auditState.seq) return;
    renderAuditTypes();
    renderAudit();
    // A hidden button cannot keep focus: after the last page, focus goes to Refresh.
    if (more && $("audit-more").hidden) $("audit-refresh").focus();
  }

  function clearAudit() {
    auditState.seq++;
    Object.assign(auditState, { entries: [], next: null, forbidden: false, error: "", logs: [], logsLoaded: false, auditLoaded: false });
    $("audit-body").replaceChildren();
    $("log-body").replaceChildren();
  }

  $("open-audit").addEventListener("click", (ev) =>
    run(
      ev.currentTarget,
      async () => {
        clearAudit();
        show("step-audit");
        renderAudit();
        await loadAudit(false);
      },
      "Loading the audit log..."
    )
  );
  const auditBusy = () => (auditIsLogs() ? "Loading the agent log..." : "Loading the audit log...");
  $("audit-refresh").addEventListener("click", (ev) => run(ev.currentTarget, () => loadAudit(false), auditBusy()));
  $("audit-more").addEventListener("click", (ev) => run(ev.currentTarget, () => loadAudit(true), "Loading older events..."));
  $("audit-view").addEventListener("change", () => {
    auditState.seq++; // an answer for the other view is stale
    auditState.error = "";
    const loaded = auditIsLogs() ? auditState.logsLoaded : auditState.auditLoaded;
    renderAudit();
    if (!loaded) run($("audit-refresh"), () => loadAudit(false), auditBusy());
  });
  for (const id of ["audit-type", "audit-time"]) $(id).addEventListener("change", renderAudit);
  $("audit-text").addEventListener("input", renderAudit);
  $("audit-back").addEventListener("click", () => {
    say("");
    clearAudit();
    if (!current.signedIn) return showConnect();
    show("step-devices");
  });
  // The events belong to the session that read them.
  $("sign-out").addEventListener("click", clearAudit);
})();
