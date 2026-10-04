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

  // ---- feature:pair-inbox ----
  // The pairing-request inbox: what the agent holds for the owner to answer. The list refreshes on
  // a timer only while this screen is showing (the `show` wrapper below starts and stops it).
  // Rows are updated in place, not rebuilt, so a button the user has tabbed to keeps focus and a
  // click always lands on the request it was drawn for.
  steps.push("step-pair-inbox");
  const inbox = { rows: new Map(), gen: 0, timer: null, ticks: 0, fetching: -1, failed: false };

  const baseShow = show;
  show = function (step) {
    baseShow(step);
    if (step === "step-pair-inbox") inboxEnter();
    else inboxLeave();
  };

  function duration(s) {
    return s < 60 ? s + " s" : Math.floor(s / 60) + " min " + (s % 60) + " s";
  }

  function inboxLeave() {
    inbox.gen++;
    if (inbox.timer !== null) clearInterval(inbox.timer);
    inbox.timer = null;
  }

  function inboxStartTimer() {
    if (inbox.timer === null) inbox.timer = setInterval(inboxTick, 1000);
  }

  function inboxReset() {
    inbox.rows.clear();
    $("inbox-rows").replaceChildren();
    $("inbox-wrap").hidden = true;
    $("inbox-empty").hidden = true;
    $("inbox-limit").hidden = true;
    $("inbox-forbidden").hidden = true;
  }

  function inboxEnter() {
    if (!current.signedIn) {
      showConnect();
      return;
    }
    inboxLeave();
    inbox.ticks = 0;
    inbox.failed = false;
    inboxReset();
    $("inbox-status").textContent = "Loading pairing requests...";
    inboxStartTimer();
    inboxFetch();
  }

  // The agent may have refused the saved login (revoked or removed there): the app dropped the
  // token and kept the pin, so go back to sign-in on that agent, as the device list does.
  async function inboxSessionEnded() {
    const saved = await invoke("saved_agent").catch(() => null);
    if (saved && saved.host && saved.fingerprint && !saved.signedIn) {
      setSession(saved);
      pending = { host: saved.host, fingerprint: saved.fingerprint };
      $("username").value = saved.username;
      show("step-login");
      loginMode(false);
    }
  }

  async function inboxFetch() {
    const me = inbox.gen;
    if (inbox.fetching === me) return;
    inbox.fetching = me;
    try {
      let out;
      try {
        out = await invoke("list_pair_requests");
      } catch (e) {
        if (me !== inbox.gen) return;
        inbox.failed = true;
        $("inbox-status").textContent = "";
        say(String(e), true);
        await inboxSessionEnded();
        return;
      }
      // The screen was left, or left and opened again, while the agent was answering.
      if (me !== inbox.gen) return;
      if (inbox.failed) {
        inbox.failed = false;
        say("");
      }
      inboxRender(out);
    } finally {
      if (inbox.fetching === me) inbox.fetching = -1;
    }
  }

  function inboxRender(out) {
    $("inbox-forbidden").hidden = !out.forbidden;
    if (out.forbidden) {
      // Nothing to poll for: this login can never see requests.
      inboxLeave();
      inboxReset();
      $("inbox-forbidden").hidden = false;
      $("inbox-status").textContent = "";
      return;
    }
    const seen = new Set(out.requests.map((r) => r.id));
    const gone = [...inbox.rows.keys()].filter((id) => !seen.has(id));
    if (gone.length) {
      const active = document.activeElement;
      for (const id of gone) inbox.rows.delete(id);
      $("inbox-rows").replaceChildren(...[...inbox.rows.values()].map((r) => r.tr));
      // A row that disappeared must not take the keyboard's place with it.
      if (active && typeof active.focus === "function" && active.isConnected) active.focus();
      else if (active && active !== document.body) $("title-pair-inbox").focus();
    }
    for (const r of out.requests) {
      let row = inbox.rows.get(r.id);
      if (!row) {
        row = inboxMakeRow(r);
        inbox.rows.set(r.id, row);
        $("inbox-rows").append(row.tr);
      }
      row.age = r.ageSeconds;
      row.left = r.expiresInSeconds;
      inboxPaint(row);
    }
    const n = out.requests.length;
    $("inbox-wrap").hidden = n === 0;
    $("inbox-empty").hidden = n !== 0;
    $("inbox-limit").hidden = n < out.limit;
    $("inbox-status").textContent = n ? n + (n === 1 ? " request waiting." : " requests waiting.") : "";
  }

  function inboxMakeRow(r) {
    const row = { id: r.id, label: r.label, code: r.matchCode, age: 0, left: 0, armLeft: 0 };
    const device = cell(r.label);
    if (r.replaces) {
      const note = document.createElement("div");
      note.className = "hint";
      note.textContent = "Takes over the paired device " + r.replaces + " (new login, access reset to browse-only).";
      device.append(note);
    }
    row.waiting = cell("");
    row.expires = cell("");
    const who = r.label + ", code " + r.matchCode;
    row.accept = document.createElement("button");
    row.accept.type = "button";
    row.accept.className = "primary";
    row.reject = document.createElement("button");
    row.reject.type = "button";
    row.reject.textContent = "Reject";
    row.reject.setAttribute("aria-label", "Reject " + who);
    inboxDisarm(row);
    row.accept.addEventListener("click", () => {
      // Two presses: the first only arms the button, so a stray click grants nothing.
      if (!row.accept.dataset.armed) {
        row.accept.dataset.armed = "1";
        row.armLeft = 8;
        row.accept.textContent = "Press again to accept";
        row.accept.setAttribute("aria-label", "Press again to accept " + who);
        return;
      }
      inboxAnswer(row, true, row.accept);
    });
    row.reject.addEventListener("click", () => inboxAnswer(row, false, row.reject));
    const actions = document.createElement("td");
    const wrap = document.createElement("div");
    wrap.className = "row";
    wrap.append(row.accept, row.reject);
    actions.append(wrap);
    row.tr = document.createElement("tr");
    row.tr.append(device, cell(r.address || "unknown"), row.waiting, row.expires, cell(r.matchCode, "inbox-code"), actions);
    return row;
  }

  function inboxDisarm(row) {
    delete row.accept.dataset.armed;
    row.armLeft = 0;
    row.accept.textContent = "Accept";
    row.accept.setAttribute("aria-label", "Accept " + row.label + ", code " + row.code);
  }

  function inboxPaint(row) {
    row.waiting.textContent = duration(row.age);
    row.expires.textContent = row.left > 0 ? duration(row.left) : "expired";
    row.accept.disabled = row.reject.disabled = row.left <= 0;
  }

  async function inboxAnswer(row, approve, button) {
    const both = [row.accept, row.reject];
    await run(button, async () => {
      for (const b of both) b.disabled = true;
      let out;
      try {
        out = await invoke("answer_pair_request", { id: row.id, approve });
      } catch (e) {
        inboxPaint(row);
        await inboxSessionEnded();
        throw e;
      }
      // Refresh before saying what happened, so the list already shows it.
      await inboxFetch();
      say(
        out === "gone"
          ? "That request already expired or was answered on the PC."
          : (approve ? "Accepted " : "Rejected ") + row.label + "."
      );
      $("title-pair-inbox").focus();
    });
    // A row that is still there (the answer failed, or the list could not be refreshed) goes back
    // to its resting state.
    if (inbox.rows.get(row.id) === row) {
      inboxDisarm(row);
      inboxPaint(row);
    }
  }

  function inboxTick() {
    if ($("step-pair-inbox").hidden) {
      inboxLeave();
      return;
    }
    for (const row of inbox.rows.values()) {
      row.left = Math.max(0, row.left - 1);
      row.age = Math.min(120, row.age + 1);
      if (row.armLeft && --row.armLeft === 0) inboxDisarm(row);
      inboxPaint(row);
    }
    if (++inbox.ticks % 3 === 0) inboxFetch();
  }

  $("open-pair-inbox").addEventListener("click", () => {
    say("");
    show("step-pair-inbox");
  });
  $("inbox-back").addEventListener("click", () => {
    say("");
    show("step-devices");
  });
  $("inbox-refresh").addEventListener("click", () => {
    inboxStartTimer();
    inboxFetch();
  });
  // ---- end feature:pair-inbox ----

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
})();
