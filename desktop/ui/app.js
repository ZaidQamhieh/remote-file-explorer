(function () {
  const invoke = window.__TAURI__.core.invoke;
  const $ = (id) => document.getElementById(id);
  const steps = ["step-connect", "step-trust", "step-login", "step-approve", "step-devices", "step-settings"];
  let pending = { host: "", fingerprint: "" };
  let current = { signedIn: false };
  let settingsReturn = "step-connect";
  // The screens that need no session; every other screen (devices, files, audit, ...) belongs to one.
  const PRE_LOGIN = ["step-connect", "step-trust", "step-login", "step-approve", "step-settings"];

  function show(step) {
    for (const id of steps) $(id).hidden = id !== step;
    // Keyboard and screen reader users are not left on a control that just disappeared: focus
    // goes to the new screen's heading, which is read out.
    const title = $(step.replace("step-", "title-"));
    if (title) title.focus();
    placeMessage();
  }

  // The message line lives at the end of the screen being shown, so a refusal or result appears
  // inside the panel the user is looking at, not below it where a long list can push it off screen.
  function placeMessage() {
    const el = $("message");
    const panel = steps.map($).find((p) => !p.hidden);
    if (panel && el.parentNode !== panel) panel.append(el);
  }

  function say(text, isError) {
    const el = $("message");
    el.hidden = !text;
    el.textContent = text || "";
    el.classList.toggle("error", !!isError);
    // An error interrupts a screen reader; progress and results wait their turn.
    el.setAttribute("role", isError ? "alert" : "status");
    placeMessage();
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

  // The newest showDevices call wins: a slow answer for the agent the user left must not draw
  // over the list of the one they are on now.
  let devicesRun = 0;
  async function showDevices() {
    const mine = ++devicesRun;
    // Fetch first: a failure must not leave an empty or stale list on screen.
    let list;
    try {
      list = await invoke("list_devices");
    } catch (e) {
      if (mine !== devicesRun) return;
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
    if (mine !== devicesRun) return;
    renderDevices(list);
    // The list can arrive after the user opened Settings; do not pull them out of it. Back goes here.
    const here = steps.find((id) => !$(id).hidden);
    if ($("step-settings").hidden) {
      if (!here || PRE_LOGIN.includes(here) || here === "step-devices") show("step-devices");
    } else settingsReturn = "step-devices";
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
    if (!current.signedIn && !PRE_LOGIN.includes(settingsReturn)) return showConnect();
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
      say("A new device key will be created the next time you sign in. The old one stays registered on the agent until it is removed there. Logins saved for your other agents were removed too; sign in to each again.");
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

  // ---- feature:app-catalog ----
  // The host's apps: list them and start one. The window sends only the catalog id; the agent
  // looks it up and hands it to the host's launcher. Launching takes two presses (the first arms
  // the button) because it opens something on another person's screen.
  (function appCatalog() {
    steps.push("step-apps");
    let armed = null;

    function disarm() {
      if (!armed) return;
      armed.button.dataset.armed = "";
      armed.button.textContent = "Launch";
      armed.button.setAttribute("aria-label", "Launch " + armed.name);
      armed = null;
    }

    function renderApps(catalog) {
      const body = $("apps-list");
      body.replaceChildren();
      armed = null;
      const apps = catalog ? catalog.apps : [];
      for (const a of apps) {
        const act = document.createElement("td");
        if (!a.launchable) {
          act.textContent = "Cannot be launched";
        } else if (catalog.launchAllowed) {
          act.append(launchButton(a));
        } else {
          act.textContent = "Launching not allowed";
        }
        const tr = document.createElement("tr");
        tr.append(cell(a.name), cell(a.category || ""), cell(a.id.slice(0, 12) + "...", "mono"), act);
        tr.children[2].setAttribute("title", a.id);
        body.append(tr);
      }
      $("apps-wrap").hidden = apps.length === 0;
      $("apps-empty").hidden = !catalog || apps.length !== 0;
      $("apps-note").hidden = !catalog || catalog.launchAllowed || !apps.some((a) => a.launchable);
    }

    function launchButton(a) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "link";
      b.textContent = "Launch";
      b.setAttribute("aria-label", "Launch " + a.name);
      b.addEventListener("click", () => {
        if (!b.dataset.armed) {
          disarm();
          b.dataset.armed = "1";
          b.textContent = "Launch?";
          b.setAttribute("aria-label", "Launch " + a.name + "? Press again to confirm.");
          armed = { button: b, name: a.name };
          return;
        }
        disarm();
        run(
          b,
          async () => {
            try {
              await invoke("launch_host_app", { id: a.id });
            } catch (e) {
              await backToSignInIfLoggedOut();
              throw e;
            }
            say("Asked the PC to open " + a.name + ". It can take a moment to appear on its screen.");
          },
          "Asking the PC to open " + a.name + "..."
        );
      });
      return b;
    }

    // A refused login drops the saved token in the core; go back to sign-in, as the device list does.
    async function backToSignInIfLoggedOut() {
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

    async function loadApps() {
      disarm();
      try {
        renderApps(await invoke("list_host_apps"));
      } catch (e) {
        // Nothing stale stays on screen, so a refused or failed list is not mistaken for the PC's apps.
        renderApps(null);
        await backToSignInIfLoggedOut();
        throw e;
      }
    }

    $("open-apps").addEventListener("click", (ev) => {
      renderApps(null);
      show("step-apps");
      run(ev.currentTarget, loadApps, "Loading apps...");
    });
    $("apps-refresh").addEventListener("click", (ev) => run(ev.currentTarget, loadApps, "Loading apps..."));
    $("apps-back").addEventListener("click", () => {
      say("");
      if (current.signedIn) show("step-devices");
      else showConnect();
    });
  })();

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

  // ---- feature:file-browser ----
  // Browse the agent's files. The window never builds a path or a URL: it sends back paths the agent
  // listed (the Rust core checks them) and shows what comes back with textContent only. Changes
  // (new folder, rename, delete to trash) are offered only when the agent's permissions allow them,
  // and a refusal is shown in the agent's own words.
  steps.push("step-files");

  const files = {
    roots: null, // what files_roots returned: locations, readOnly, caps
    mode: "locations", // "locations" or "folder"
    root: "", // the location the open folder is under; the trail starts there
    path: "",
    crumbs: [],
    entries: [],
    cursor: null, // set while the agent has more entries for this folder
    sortKey: "name",
    sortDir: 1,
    rows: [], // one {entry, open, controls} per shown row, in shown order
    active: 0, // the row whose controls are in the tab order
    form: null, // {kind: "new"} or {kind: "rename", entry}
    armed: null, // the delete button waiting for its second press
    token: 0, // bumped by every load, so a slow answer for an old folder is dropped
  };

  // The hook the transfers screen uses: it replaces onFileSelected with what happens when a file
  // (not a folder) is opened with Enter or a click. This default only says which file it was.
  window.rfeFileActions = window.rfeFileActions || {
    onFileSelected(entry) {
      filesStatus("Selected " + entry.path + ".");
    },
  };

  const filesStatus = (text) => {
    $("files-status").textContent = text;
  };
  const canModify = () => !!files.roots && !files.roots.readOnly && (!files.roots.caps || files.roots.caps.modify);
  const canDelete = () => !!files.roots && !files.roots.readOnly && (!files.roots.caps || files.roots.caps.delete);

  function fmtSize(n) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return (i === 0 || n >= 10 ? Math.round(n) : n.toFixed(1)) + " " + units[i];
  }

  const typeLabel = (e) => (e.isDir ? (e.isSymlink ? "Folder link" : "Folder") : e.isSymlink ? "Link" : e.mimeType || "File");

  function sizeLabel(e) {
    if (!e.isDir) return fmtSize(e.size || 0);
    if (e.childCount == null) return "";
    if (e.childCount >= 1000) return "1000+ items";
    return e.childCount + (e.childCount === 1 ? " item" : " items");
  }

  function filesSorted() {
    const keys = {
      name: (e) => e.name,
      size: (e) => (e.isDir ? (e.childCount == null ? -1 : e.childCount) : e.size || 0),
      modified: (e) => Date.parse(e.modified) || 0,
      type: typeLabel,
    };
    const key = keys[files.sortKey];
    const text = (a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
    return files.entries.slice().sort((a, b) => {
      // Folders stay together above the files whatever the sort.
      if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
      const x = key(a);
      const y = key(b);
      let r = typeof x === "string" ? text(x, y) : x - y;
      if (r === 0 && files.sortKey !== "name") r = text(a.name, b.name);
      return r * files.sortDir;
    });
  }

  // Where the agent is not letting this login in is the agent's call; the trail only starts at the
  // location the user opened, so it never offers steps above it.
  function trimTrail(crumbs, root) {
    const at = crumbs.findIndex((c) => c.path === root);
    return at > 0 ? crumbs.slice(at) : crumbs;
  }

  function disarm() {
    const a = files.armed;
    if (!a) return;
    a.button.textContent = "Delete";
    a.button.setAttribute("aria-label", "Delete " + a.entry.name);
    files.armed = null;
  }

  function filesRenderTrail() {
    const loc = files.mode === "locations";
    const items = [{ label: "Locations", aria: "Go to the list of locations", go: loc ? null : filesOpenLocations }];
    if (!loc) {
      files.crumbs.forEach((c, i) => {
        const last = i === files.crumbs.length - 1;
        items.push({ label: c.label, aria: "Go to folder " + c.label, go: last ? null : () => filesOpenFolder(c.path) });
      });
    }
    $("files-trail").replaceChildren(
      ...items.map((it) => {
        const li = document.createElement("li");
        if (it.go) {
          const b = document.createElement("button");
          b.type = "button";
          b.className = "link";
          b.textContent = it.label;
          b.setAttribute("aria-label", it.aria);
          b.addEventListener("click", it.go);
          li.append(b);
        } else {
          const s = document.createElement("span");
          s.textContent = it.label;
          s.setAttribute("aria-current", "page");
          li.append(s);
        }
        return li;
      })
    );
  }

  function filesRenderNote() {
    const r = files.roots;
    let text = "";
    if (r && r.readOnly) text = "The agent is read-only, so nothing here can be created, renamed or deleted.";
    else if (r && r.caps && !r.caps.modify && !r.caps.delete) text = "This computer may look but not change files on this agent.";
    $("files-note").hidden = !text;
    $("files-note").textContent = text;
  }

  function filesRenderLocations() {
    const r = files.roots;
    const body = $("files-locations");
    body.replaceChildren();
    for (const loc of r ? r.locations : []) {
      const open = document.createElement("button");
      open.type = "button";
      open.className = "link filelink";
      open.textContent = loc.label;
      open.setAttribute("aria-label", "Open " + loc.label + " (" + loc.path + ")");
      open.addEventListener("click", () => filesOpenFolder(loc.path, loc));
      const nameCell = document.createElement("td");
      nameCell.append(open);
      const tr = document.createElement("tr");
      tr.append(nameCell, cell(loc.path, "mono-line"), cell(loc.totalBytes ? fmtSize(loc.freeBytes) + " free of " + fmtSize(loc.totalBytes) : ""));
      body.append(tr);
    }
    const none = !!r && r.locations.length === 0;
    $("files-locations-table").hidden = !r || none;
    $("files-locations-empty").hidden = !none;
    if (none) {
      $("files-locations-empty").textContent =
        "No folder is open to this login." +
        (r.accessDenied
          ? " The agent confined this computer to a folder it does not allow."
          : r.caps && !r.caps.browse
            ? " This computer is not allowed to browse."
            : " The agent has not shared a folder with it.");
    }
  }

  function filesSetActive(i, focus) {
    if (files.armed && (!files.rows[i] || files.rows[i].entry !== files.armed.entry)) disarm();
    files.active = i;
    files.rows.forEach((row, n) => {
      for (const c of row.controls) c.setAttribute("tabindex", n === i ? "0" : "-1");
    });
    if (focus && files.rows[i]) files.rows[i].open.focus();
  }

  function filesRenderRows() {
    files.armed = null;
    const list = filesSorted();
    const body = $("files-rows");
    body.replaceChildren();
    files.rows = [];
    list.forEach((e, i) => {
      const open = document.createElement("button");
      open.type = "button";
      open.className = "link filelink";
      open.textContent = e.name;
      open.setAttribute("aria-label", (e.isDir ? "Open folder " : e.isSymlink ? "Open link " : "Select file ") + e.name);
      open.addEventListener("click", () => {
        filesSetActive(files.rows.findIndex((r) => r.entry === e));
        filesActivate(e);
      });
      const controls = [open];
      const nameCell = document.createElement("td");
      nameCell.append(open);
      if (e.isSymlink) {
        const to = document.createElement("span");
        to.className = "muted";
        to.textContent = e.symlinkTarget ? " → " + e.symlinkTarget : " (link)";
        nameCell.append(to);
      }
      const act = document.createElement("td");
      if (canModify()) {
        const ren = document.createElement("button");
        ren.type = "button";
        ren.className = "link";
        ren.textContent = "Rename";
        ren.setAttribute("aria-label", "Rename " + e.name);
        ren.addEventListener("click", () => filesOpenForm({ kind: "rename", entry: e }));
        controls.push(ren);
        act.append(ren);
      }
      if (canDelete()) {
        const del = document.createElement("button");
        del.type = "button";
        del.className = "link";
        del.textContent = "Delete";
        del.setAttribute("aria-label", "Delete " + e.name);
        del.addEventListener("click", () => {
          // Two presses: the first only arms it. Deleting moves the entry to the agent's trash.
          if (!files.armed || files.armed.button !== del) {
            disarm();
            files.armed = { button: del, entry: e };
            del.textContent = "Delete?";
            del.setAttribute("aria-label", "Delete " + e.name + "? Press again to move it to the trash.");
            say("Press Delete again to move " + e.name + " to the trash. It can be restored from there.");
            return;
          }
          filesRun(
            del,
            async () => {
              await invoke("files_trash", { path: e.path });
              files.armed = null;
              files.entries = files.entries.filter((x) => x.path !== e.path);
              const at = files.rows.findIndex((r) => r.entry === e);
              filesRenderRows();
              if (files.rows.length) filesSetActive(Math.min(at, files.rows.length - 1), true);
              else $("files-refresh").focus();
              say("Moved to the trash: " + e.name);
            },
            "Moving to the trash..."
          );
        });
        controls.push(del);
        act.append(del);
      }
      const tr = document.createElement("tr");
      tr.append(nameCell, cell(typeLabel(e)), cell(sizeLabel(e)), cell(Date.parse(e.modified) ? new Date(e.modified).toLocaleString() : ""), act);
      body.append(tr);
      files.rows.push({ entry: e, open, controls });
    });
    $("files-empty").hidden = list.length !== 0;
    $("files-more-block").hidden = !files.cursor;
    for (const key of ["name", "size", "modified", "type"]) {
      $("files-th-" + key).setAttribute("aria-sort", key === files.sortKey ? (files.sortDir > 0 ? "ascending" : "descending") : "none");
    }
    $("files-table").setAttribute("aria-label", "Contents of " + files.path);
    files.active = Math.max(0, Math.min(files.active, files.rows.length - 1));
    filesSetActive(files.active, false);
  }

  function filesRender() {
    const loc = files.mode === "locations";
    $("files-locations-wrap").hidden = !loc;
    $("files-list-wrap").hidden = loc;
    $("files-new-folder").hidden = loc || !canModify();
    filesRenderTrail();
    filesRenderNote();
    if (loc) filesRenderLocations();
    else filesRenderRows();
  }

  function filesCloseForm() {
    files.form = null;
    $("files-name-form").hidden = true;
    $("files-name").value = "";
  }

  function filesOpenForm(form) {
    files.form = form;
    $("files-name-label").textContent = form.kind === "new" ? "Folder name" : "New name for " + form.entry.name;
    $("files-name").value = form.kind === "new" ? "" : form.entry.name;
    $("files-name-form").hidden = false;
    $("files-name").focus();
    if (form.kind === "rename") $("files-name").select();
  }

  // The agent no longer accepts the login: go back to sign-in, as the device list does.
  async function filesSessionCheck() {
    const saved = await invoke("saved_agent").catch(() => null);
    if (!saved || saved.signedIn) return;
    setSession(saved);
    await showDevices().catch(() => {});
    if (!$("step-files").hidden) showConnect();
  }

  async function filesFail(e, gen) {
    if (gen !== files.token) return;
    await filesSessionCheck();
    say(String(e), true);
  }

  function filesRun(button, fn, busy) {
    return run(
      button,
      async () => {
        try {
          await fn();
        } catch (e) {
          await filesSessionCheck();
          throw e;
        }
      },
      busy
    );
  }

  async function filesOpenLocations() {
    const gen = ++files.token;
    say("Loading folder...");
    let r;
    try {
      r = await invoke("files_roots");
    } catch (e) {
      return filesFail(e, gen);
    }
    if (gen !== files.token) return;
    say("");
    files.roots = r;
    files.mode = "locations";
    filesCloseForm();
    filesStatus("");
    filesRender();
    $("title-files").focus();
  }

  async function filesOpenFolder(path, location) {
    const gen = ++files.token;
    say("Loading folder...");
    let page;
    try {
      page = await invoke("files_list", { path, cursor: null, limit: 500 });
    } catch (e) {
      return filesFail(e, gen);
    }
    if (gen !== files.token) return;
    say("");
    if (location) files.root = location.path;
    files.mode = "folder";
    files.path = page.path;
    files.crumbs = trimTrail(page.crumbs, files.root);
    files.entries = page.entries;
    files.cursor = page.nextCursor || null;
    files.active = 0;
    filesCloseForm();
    filesStatus("");
    filesRender();
    if (files.rows.length) filesSetActive(0, true);
    else $("title-files").focus();
  }

  async function filesActivate(e) {
    if (e.isDir) return filesOpenFolder(e.path);
    if (e.isSymlink) {
      // The listing does not say whether a link leads to a folder, and the agent decides whether
      // the link may be followed at all, so ask it and show its answer.
      const gen = ++files.token;
      let m;
      try {
        m = await invoke("files_meta", { path: e.path });
      } catch (err) {
        return filesFail(err, gen);
      }
      if (gen !== files.token) return;
      return m.isDir ? filesOpenFolder(m.path) : filesSelect(m);
    }
    filesSelect(e);
  }

  function filesSelect(entry) {
    try {
      window.rfeFileActions.onFileSelected(Object.assign({}, entry));
    } catch (err) {
      say(String(err), true);
    }
  }

  function filesUp() {
    if (files.mode === "locations") return filesLeave();
    if (files.crumbs.length >= 2) return filesOpenFolder(files.crumbs[files.crumbs.length - 2].path);
    return filesOpenLocations();
  }

  function filesLeave() {
    if (!current.signedIn) return showConnect();
    show("step-devices");
  }

  $("open-files").addEventListener("click", () => {
    show("step-files");
    files.roots = null;
    files.mode = "locations";
    filesRender();
    filesOpenLocations();
  });
  $("files-back").addEventListener("click", filesLeave);
  $("files-refresh").addEventListener("click", () => (files.mode === "locations" ? filesOpenLocations() : filesOpenFolder(files.path)));
  $("files-new-folder").addEventListener("click", () => filesOpenForm({ kind: "new" }));
  function filesCancelForm() {
    const back = files.form && files.form.kind === "rename" ? files.rows.find((r) => r.entry === files.form.entry) : null;
    filesCloseForm();
    if (back) back.open.focus();
    else $("files-new-folder").focus();
  }
  $("files-name-cancel").addEventListener("click", filesCancelForm);

  $("files-name-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    const form = files.form;
    if (!form) return;
    filesRun(
      submitter(ev),
      async () => {
        const name = $("files-name").value;
        let changed;
        if (form.kind === "new") {
          changed = await invoke("files_create_folder", { parent: files.path, name });
          files.entries.push(changed);
        } else {
          changed = await invoke("files_rename", { path: form.entry.path, newName: name });
          files.entries = files.entries.map((x) => (x === form.entry ? changed : x));
        }
        filesCloseForm();
        filesRenderRows();
        const at = files.rows.findIndex((r) => r.entry === changed);
        filesSetActive(Math.max(0, at), true);
      },
      form.kind === "new" ? "Creating the folder..." : "Renaming..."
    );
  });

  $("files-more").addEventListener("click", (ev) =>
    filesRun(
      ev.currentTarget,
      async () => {
        const gen = files.token;
        const page = await invoke("files_list", { path: files.path, cursor: files.cursor, limit: 500 });
        if (gen !== files.token) return;
        for (const e of page.entries) files.entries.push(e);
        files.cursor = page.nextCursor || null;
        filesRenderRows();
      },
      "Loading folder..."
    )
  );

  for (const key of ["name", "size", "modified", "type"]) {
    $("files-sort-" + key).addEventListener("click", () => {
      if (files.sortKey === key) files.sortDir = -files.sortDir;
      else {
        files.sortKey = key;
        files.sortDir = 1;
      }
      filesRenderRows();
      filesStatus("Sorted by " + key + ", " + (files.sortDir > 0 ? "ascending" : "descending") + (files.cursor ? " (only the entries loaded so far)" : "") + ".");
    });
  }

  // Keyboard: arrows, Home and End move between rows (one tab stop for the whole list), Enter or
  // Space on a name opens it (they are buttons), Backspace goes up a folder, Escape closes the name
  // box or cancels a delete.
  $("files-table").addEventListener("keydown", (ev) => {
    const tag = ev.target && ev.target.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    const last = files.rows.length - 1;
    const go = (i) => {
      ev.preventDefault();
      if (last >= 0) filesSetActive(Math.max(0, Math.min(last, i)), true);
    };
    if (ev.key === "ArrowDown") go(files.active + 1);
    else if (ev.key === "ArrowUp") go(files.active - 1);
    else if (ev.key === "Home") go(0);
    else if (ev.key === "End") go(last);
  });
  $("step-files").addEventListener("keydown", (ev) => {
    const tag = ev.target && ev.target.tagName;
    if (ev.key === "Escape") {
      if (files.armed) {
        disarm();
        say("");
      }
      if (files.form) filesCancelForm();
      return;
    }
    if (ev.key !== "Backspace" || tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    ev.preventDefault();
    filesUp();
  });
  // ---- end feature:file-browser ----

  // ---- feature:multi-hosts ----
  // Saved hosts: switch between agents, rename, remove (two clicks), add. The window only asks the
  // Rust core by key; it never sees a token and never sends an address of its own to these commands.
  function hostsStatus(text, isError) {
    const el = $("hosts-status");
    el.textContent = text || "";
    el.className = isError ? "tag revoked" : "";
  }

  function hostLoginText(h) {
    if (!h.signedIn) return "Signed out";
    return h.username ? "Signed in as " + h.username : "Paired with a code";
  }

  async function refreshHosts() {
    try {
      renderHosts(await invoke("list_hosts"));
    } catch (e) {
      hostsStatus(String(e), true);
    }
  }

  async function switchToHost(h, button) {
    await run(
      button,
      async () => {
        const saved = await invoke("switch_host", { key: h.key });
        renderDevices([]);
        setSession(saved);
        $("host").value = saved.host;
        pending = { host: saved.host, fingerprint: saved.fingerprint };
        settingsAccount();
        await refreshHosts();
        await settingsPins().refresh();
        if (saved.signedIn) {
          await showDevices();
          show("step-devices");
          say("");
        } else {
          $("username").value = saved.username;
          $("login-form").hidden = false;
          $("pair-form").hidden = true;
          show("step-login");
          say("Signed out on this host. Sign in to continue.");
        }
      },
      "Switching host..."
    );
  }

  function startRename(h, nameCell, actions) {
    const input = document.createElement("input");
    input.type = "text";
    input.value = h.name;
    input.maxLength = 64;
    input.autocomplete = "off";
    input.setAttribute("aria-label", "New name for " + h.name);
    const save = document.createElement("button");
    save.type = "button";
    save.textContent = "Save";
    save.setAttribute("aria-label", "Save the new name for " + h.name);
    const cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "link";
    cancel.textContent = "Cancel";
    cancel.setAttribute("aria-label", "Cancel renaming " + h.name);
    const doSave = () =>
      run(save, async () => {
        await invoke("rename_host", { key: h.key, name: input.value });
        await refreshHosts();
        hostsStatus("Renamed.");
      });
    save.addEventListener("click", doSave);
    cancel.addEventListener("click", async () => {
      await refreshHosts();
    });
    input.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") {
        ev.preventDefault();
        doSave();
      } else if (ev.key === "Escape") {
        refreshHosts();
      }
    });
    nameCell.replaceChildren(input);
    actions.replaceChildren(save, cancel);
    input.focus();
  }

  function renderHosts(list) {
    const body = $("hosts-list");
    body.replaceChildren();
    for (const h of list) {
      const use = document.createElement("button");
      use.type = "button";
      use.className = "link";
      use.textContent = h.active ? "Open" : "Switch";
      use.setAttribute("aria-label", (h.active ? "Open " : "Switch to ") + h.name);
      use.addEventListener("click", () => switchToHost(h, use));

      const rename = document.createElement("button");
      rename.type = "button";
      rename.className = "link";
      rename.textContent = "Rename";
      rename.setAttribute("aria-label", "Rename " + h.name);

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "link";
      remove.textContent = "Remove";
      remove.setAttribute("aria-label", "Remove " + h.name);
      remove.addEventListener("click", () => {
        // Two clicks: the first only arms the button.
        if (!remove.dataset.armed) {
          remove.dataset.armed = "1";
          remove.textContent = "Remove and delete login?";
          remove.setAttribute(
            "aria-label",
            "Remove and delete the saved login for " + h.name + "? Press again to confirm."
          );
          return;
        }
        run(remove, async () => {
          const out = await invoke("remove_host", { key: h.key });
          if (out.wasActive) {
            renderDevices([]);
            setSession({ signedIn: false });
            settingsAccount();
            settingsReturn = "step-connect";
          }
          await refreshHosts();
          await settingsPins().refresh();
          hostsStatus("Removed " + h.name + ".");
        });
      });

      const actions = document.createElement("td");
      actions.append(use, rename, remove);
      const nameCell = cell(h.name + (h.active ? " (in use)" : ""));
      rename.addEventListener("click", () => startRename(h, nameCell, actions));
      const tr = document.createElement("tr");
      tr.append(nameCell, cell(h.host, "mono"), cell(hostLoginText(h)), actions);
      body.append(tr);
    }
    $("hosts-empty").hidden = list.length !== 0;
  }

  $("open-settings").addEventListener("click", refreshHosts);
  $("open-hosts").addEventListener("click", async () => {
    await showSettings();
    await refreshHosts();
    $("title-hosts").focus();
  });
  $("hosts-add").addEventListener("click", async () => {
    // Emptied before the await: whatever is typed while the trusted list loads must survive.
    $("host").value = "";
    await showConnect();
    $("host").focus();
    say("Type the new host's address. Your current login stays saved.");
  });
  // ---- feature:device-actions ----
  // Per-device actions in the devices table for an admin session (an account sign-in): change a
  // device's access, revoke it, remove it. The agent has no rename. renderDevices is wrapped, not
  // edited: it is first called after an await, so this block has run by then. Everything goes
  // through the Rust core; the agent decides who may (403 for anyone else) and the window only
  // shows the actions to a session that can use them.
  {
    const baseRenderDevices = renderDevices;
    const BOXES = {
      browse: "da-browse",
      download: "da-download",
      upload: "da-upload",
      modify: "da-modify",
      delete: "da-delete",
      share: "da-share",
      viewApps: "da-viewapps",
      launchApps: "da-launchapps",
      readOnly: "da-readonly",
    };
    let editing = null; // { id, label, self, loaded, opener }

    const resetSave = () => {
      $("da-editor-self").hidden = true;
      delete $("da-save").dataset.armed;
      $("da-save").textContent = "Save access";
    };

    const closeEditor = () => {
      editing = null;
      $("da-editor").hidden = true;
      resetSave();
    };

    // Runs one device action: busy text while it is in flight, then the list as the agent has it
    // (also after a failure: a 404 means the row is gone), then the result. An action on this
    // computer's own device ends the session, so the window goes back to the first screen.
    function perform(button, busy, call, done, after) {
      return run(
        button,
        async () => {
          let out;
          try {
            out = await call();
          } catch (e) {
            await showDevices().catch(() => {});
            throw e;
          }
          if (after) after();
          if (out && out.signedOut) {
            closeEditor();
            renderDevices([]);
            setSession({ signedIn: false });
            await showConnect();
            say(done);
            return;
          }
          try {
            await showDevices();
            say(done);
          } catch (e) {
            say(done + " The list could not be refreshed: " + e, true);
          }
        },
        busy
      );
    }

    const rowName = (d) => d.label + (d.current ? " (this computer)" : "");

    // Two presses, like Forget: the first only arms the button. On this computer's own device the
    // first press also shows a stronger warning, and the core refuses without the confirmation.
    function dangerButton(d, verb, command, past) {
      const b = document.createElement("button");
      b.type = "button";
      let warning = "";
      const idle = () => {
        delete b.dataset.armed;
        b.className = "link da-danger";
        b.textContent = verb;
        b.setAttribute("aria-label", verb + " " + rowName(d));
        if (warning && $("message").textContent === warning) say("");
        warning = "";
      };
      idle();
      b.addEventListener("blur", () => {
        if (b.dataset.armed && !b.disabled) idle();
      });
      b.addEventListener("click", () => {
        if (!b.dataset.armed) {
          b.dataset.armed = "1";
          b.className = "link da-danger armed";
          if (d.current) {
            b.textContent = "Sign this computer out?";
            warning =
              "This is the computer you are using. " + verb + " signs you out here, and you will have to sign in again. Press the button again to sign this computer out.";
            b.setAttribute("aria-label", "Press the button again to sign this computer out: " + verb + " " + d.label);
            say(warning, true);
          } else {
            b.textContent = verb + "?";
            b.setAttribute("aria-label", verb + "? " + d.label + " Press again to confirm.");
          }
          return;
        }
        warning = "";
        perform(
          b,
          verb === "Remove" ? "Removing..." : "Revoking...",
          () => invoke(command, { id: d.id, confirmSelf: !!d.current }),
          past + d.label + "." + (d.current ? " This computer is signed out; sign in again to continue." : "")
        );
      });
      return b;
    }

    function openEditor(d, rec, opener) {
      editing = { id: d.id, label: d.label, self: !!d.current, loaded: rec, opener };
      $("da-editor-title").textContent = "Access for " + rowName(d);
      $("da-editor-hint").textContent = rec.viaLogin
        ? "This device signed in with an account, so the agent ignores its file permissions. The read-only and folder limits still apply."
        : "";
      for (const [key, id] of Object.entries(BOXES)) $(id).checked = !!rec[key];
      $("da-jail").value = rec.jailRoot || "";
      resetSave();
      $("da-editor").hidden = false;
      $("da-editor-title").focus();
    }

    function accessButton(d) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "link";
      b.textContent = "Access";
      b.setAttribute("aria-label", "Change access for " + rowName(d));
      b.addEventListener("click", () =>
        run(
          b,
          async () => openEditor(d, await invoke("device_access", { id: d.id }), b),
          "Reading the device's access..."
        )
      );
      return b;
    }

    renderDevices = function (list) {
      baseRenderDevices(list);
      const admin = list.some((d) => d.current && d.viaLogin);
      $("da-hint").hidden = !admin || list.length === 0;
      if (!admin || (editing && !list.some((d) => d.id === editing.id))) closeEditor();
      const rows = $("devices").children;
      list.forEach((d, i) => {
        const td = document.createElement("td");
        if (admin) {
          const box = document.createElement("div");
          box.className = "da-actions";
          if (!d.revoked) box.append(accessButton(d), dangerButton(d, "Revoke", "revoke_device", "Revoked "));
          box.append(dangerButton(d, "Remove", "remove_device", "Removed "));
          td.append(box);
        }
        rows[i].append(td);
      });
    };

    // Allowing apps to be started needs them to be viewable; keep the two boxes consistent.
    $("da-launchapps").addEventListener("change", () => {
      if ($("da-launchapps").checked) $("da-viewapps").checked = true;
    });
    $("da-viewapps").addEventListener("change", () => {
      if (!$("da-viewapps").checked) $("da-launchapps").checked = false;
    });

    $("da-cancel").addEventListener("click", () => {
      const opener = editing && editing.opener;
      closeEditor();
      say("");
      (opener || $("title-devices")).focus();
    });

    $("da-save").addEventListener("click", () => {
      const e = editing;
      if (!e) return;
      // Only what changed is sent, so an unchanged folder limit is not checked again.
      const patch = {};
      for (const [key, id] of Object.entries(BOXES)) {
        if ($(id).checked !== !!e.loaded[key]) patch[key] = $(id).checked;
      }
      const jail = $("da-jail").value.trim();
      if (jail !== (e.loaded.jailRoot || "")) patch.jailRoot = jail;
      if (Object.keys(patch).length === 0) {
        say("No setting was changed, so there is nothing to save.");
        return;
      }
      const save = $("da-save");
      if (e.self && !save.dataset.armed) {
        save.dataset.armed = "1";
        save.textContent = "Save access to this computer?";
        $("da-editor-self").hidden = false;
        return;
      }
      perform(
        save,
        "Saving access...",
        () => invoke("set_device_access", { id: e.id, patch, confirmSelf: e.self }),
        "Saved the access of " + e.label + ".",
        closeEditor
      );
    });
  }

  // ---- feature:pairing-codes ----
  // "Pair a phone": asks the agent for a one-time code (admin sessions only) and shows it. The
  // code exists only as the text of #pcodes-code. Leaving the screen for any reason (Back,
  // Settings, sign-out, expiry) clears it, and the app never puts it on the clipboard.
  steps.push("step-pairing");
  let pcodesEpoch = 0; // bumped on every clear, so an answer or a tick that comes late is dropped
  let pcodesDeadline = 0;

  function pcodesClear() {
    pcodesEpoch++;
    pcodesDeadline = 0;
    $("pcodes-code").textContent = "";
    $("pcodes-code-block").hidden = true;
    $("pcodes-expiry").textContent = "";
    $("pcodes-select-result").textContent = "";
    $("pcodes-expired").hidden = true;
    $("pcodes-forbidden").hidden = true;
    $("pcodes-generate").textContent = "Generate a code";
  }

  // Every screen change clears the code, whoever asked for it. The pairing screen itself is
  // never shown to a session that has ended (Back from Settings after forgetting the agent).
  const showScreen = show;
  show = function (step) {
    if (step === "step-pairing" && !current.signedIn) return showConnect();
    pcodesClear();
    showScreen(step);
  };

  function pcodesTick(me) {
    if (me !== pcodesEpoch) return;
    const left = Math.ceil((pcodesDeadline - Date.now()) / 1000);
    if (left <= 0) {
      pcodesClear();
      $("pcodes-expired").hidden = false;
      // The button that had focus is gone with the code; keep the keyboard user somewhere useful.
      $("pcodes-generate").focus();
      return;
    }
    $("pcodes-expiry").textContent = "Expires in " + Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0") + ".";
    setTimeout(() => pcodesTick(me), 1000);
  }

  async function pcodesGenerate() {
    pcodesClear(); // the old code leaves the screen first; it stays valid on the agent until its time is up
    const me = pcodesEpoch;
    let out;
    try {
      out = await invoke("generate_pairing_code");
    } catch (e) {
      // The agent may have refused the saved login (revoked or removed there). The app then
      // dropped the token but kept the pin, so go back to sign-in on that agent.
      if (me === pcodesEpoch) {
        const saved = await invoke("saved_agent").catch(() => null);
        if (saved && saved.host && saved.fingerprint && !saved.signedIn) {
          setSession(saved);
          pending = { host: saved.host, fingerprint: saved.fingerprint };
          $("username").value = saved.username;
          show("step-login");
          loginMode(false);
        }
      }
      throw e;
    }
    if (me !== pcodesEpoch) return; // the user left the screen while the agent was answering
    if (out.status === "forbidden") {
      $("pcodes-forbidden").hidden = false;
      return;
    }
    $("pcodes-code").textContent = out.code;
    $("pcodes-code-block").hidden = false;
    $("pcodes-generate").textContent = "Generate a new code";
    pcodesDeadline = Date.now() + out.expiresInSeconds * 1000;
    pcodesTick(me);
  }

  $("open-pairing").addEventListener("click", () => {
    say("");
    show("step-pairing");
  });
  $("pcodes-back").addEventListener("click", () => {
    say("");
    show("step-devices");
  });
  $("pcodes-generate").addEventListener("click", (ev) =>
    run(ev.currentTarget, pcodesGenerate, "Asking the agent for a code...")
  );
  // Sign-out takes a moment to reach the agent; the code goes the instant the button is pressed.
  $("sign-out").addEventListener("click", pcodesClear);

  // Selecting is the copy path: the app does not use the clipboard for a live pairing code.
  $("pcodes-select").addEventListener("click", () => {
    const result = $("pcodes-select-result");
    try {
      window.getSelection().selectAllChildren($("pcodes-code"));
      result.textContent = "Selected. Press Ctrl+C to copy.";
    } catch (e) {
      result.textContent = "Select the code with the mouse, then press Ctrl+C.";
    }
  });

  // ---- feature:health-metrics ----
  // Health and metrics. One command, `agent_health`, reads /health, /status and /metrics through the
  // pinned client. Auto-refresh runs only while this screen is showing, and each refresh starts when
  // the last one has ended, so a slow agent never piles up requests. Only the previous reading is
  // kept, to turn the agent's byte totals into a rate; there is no history. Text goes in with
  // textContent only.
  steps.push("step-health");
  const NOT_REPORTED = "not reported";
  const HEALTH_EVERY_MS = 5000;
  const FORBIDDEN_TEXT =
    "Metrics are for administrators. This computer signed in with a pairing code or was approved on the PC, so the agent refuses to share the PC's processor, memory and traffic figures (403). Sign in with the account to see them.";
  const HEALTH_FIELDS = [
    "health-host", "health-fingerprint", "health-name", "health-version", "health-os", "health-readonly",
    "health-address", "health-tailscale", "health-mac", "health-status", "health-uptime", "health-disk",
    "health-cpu", "health-ram", "health-rx", "health-tx", "health-rx-rate", "health-tx-rate", "health-agent-time",
  ];
  let healthRun = 0; // changes when the screen is opened or left or auto-refresh is switched, so an old loop ends
  let healthBusy = false;
  let healthPrev = null; // the previous metrics reading: { rx, tx, ts }

  // Binary units (1 KiB = 1024 bytes). `sizeText` is the short form, `formatBytes` adds the exact
  // count for anything over a kilobyte.
  function sizeText(n) {
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let v = Math.max(0, n);
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return (i === 0 ? String(Math.round(v)) : v.toFixed(v >= 100 ? 0 : 1)) + " " + units[i];
  }

  function formatBytes(n) {
    if (n == null) return NOT_REPORTED;
    return n < 1024 ? sizeText(n) : sizeText(n) + " (" + Math.round(n).toLocaleString() + " bytes)";
  }

  function formatDuration(seconds) {
    if (seconds == null) return NOT_REPORTED;
    const s = Math.max(0, Math.floor(seconds));
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d) return d + " d " + h + " h " + m + " min";
    if (h) return h + " h " + m + " min";
    if (m) return m + " min " + (s % 60) + " s";
    return s + " s";
  }

  const formatPercent = (p) => (p == null ? NOT_REPORTED : p.toFixed(1) + " %");
  const orNone = (v) => (v ? v : NOT_REPORTED);
  const setText = (id, text) => {
    $(id).textContent = text;
  };

  // The agent's totals only grow, so a rate is the difference between two readings over the time
  // between them, on the agent's own clock. A total that went down means the agent restarted.
  function healthRates(m) {
    if (m.rxBytes == null || m.txBytes == null || m.tsMs == null) return [NOT_REPORTED, NOT_REPORTED];
    const prev = healthPrev;
    healthPrev = { rx: m.rxBytes, tx: m.txBytes, ts: m.tsMs };
    if (!prev) return ["Needs a second reading", "Needs a second reading"];
    const seconds = (m.tsMs - prev.ts) / 1000;
    if (m.rxBytes < prev.rx || m.txBytes < prev.tx) {
      return ["Counters were reset (the agent restarted)", "Counters were reset (the agent restarted)"];
    }
    if (seconds <= 0) return ["Needs a newer reading", "Needs a newer reading"];
    return [sizeText((m.rxBytes - prev.rx) / seconds) + "/s", sizeText((m.txBytes - prev.tx) / seconds) + "/s"];
  }

  function renderHealth(s) {
    const h = s.health || {};
    setText("health-host", s.host);
    setText("health-fingerprint", s.fingerprint);
    setText("health-name", orNone(h.name));
    setText("health-version", orNone(h.version));
    setText("health-os", orNone(h.os));
    setText("health-readonly", h.readOnly == null ? NOT_REPORTED : h.readOnly ? "Yes (the agent refuses changes)" : "No");
    setText("health-address", orNone(h.address));
    setText("health-tailscale", orNone(h.tailscaleAddress));
    setText("health-mac", orNone(h.macAddress));
    setText("health-status", h.status === "ok" ? "Running (ok)" : orNone(h.status));

    const st = s.status;
    setText("health-uptime", st ? formatDuration(st.uptimeSeconds) : NOT_REPORTED);
    setText(
      "health-disk",
      st && st.freeBytes != null && st.totalBytes != null
        ? sizeText(st.freeBytes) + " of " + sizeText(st.totalBytes)
        : NOT_REPORTED
    );
    $("health-status-note").hidden = !s.statusNote;
    setText("health-status-note", s.statusNote ? "Uptime and disk space could not be read: " + s.statusNote : "");

    const m = s.metrics;
    $("health-forbidden").hidden = !s.metricsForbidden;
    setText("health-forbidden", s.metricsForbidden ? FORBIDDEN_TEXT : "");
    $("health-metrics").hidden = !m;
    const noMetrics = !m && !s.metricsForbidden;
    $("health-metrics-note").hidden = !noMetrics;
    setText("health-metrics-note", noMetrics ? "No metrics were reported. " + (s.metricsNote || "") : "");
    if (!m) {
      healthPrev = null;
      return;
    }
    setText("health-cpu", formatPercent(m.cpuPercent));
    setText("health-ram", formatPercent(m.ramPercent));
    setText("health-rx", formatBytes(m.rxBytes));
    setText("health-tx", formatBytes(m.txBytes));
    const [rx, tx] = healthRates(m);
    setText("health-rx-rate", rx);
    setText("health-tx-rate", tx);
    setText("health-agent-time", m.tsMs == null ? NOT_REPORTED : new Date(m.tsMs).toLocaleString());
  }

  // One refresh. Returns false without asking when another is still in flight. On an error the
  // numbers already on screen stay; if the agent refused the saved login the app has dropped it
  // and kept the pin, so go back to sign-in on that agent, as the device list does.
  async function loadHealth() {
    if (healthBusy) return false;
    healthBusy = true;
    try {
      const s = await invoke("agent_health");
      renderHealth(s);
      setText("health-updated", "Last updated " + new Date().toLocaleTimeString() + ".");
      $("health-auto-note").hidden = true;
      return true;
    } catch (e) {
      const saved = await invoke("saved_agent").catch(() => null);
      if (saved && saved.host && saved.fingerprint && !saved.signedIn) {
        healthRun++;
        setSession(saved);
        pending = { host: saved.host, fingerprint: saved.fingerprint };
        $("username").value = saved.username;
        show("step-login");
        loginMode(false);
      }
      throw e;
    } finally {
      healthBusy = false;
    }
  }

  // Stops auto-refresh after an error, so a locked keystore or a PC that is off is not asked every
  // five seconds; the user turns it back on.
  function healthAutoStopped() {
    healthRun++;
    $("health-auto").checked = false;
    setText("health-auto-note", "Auto-refresh stopped after an error. Press Refresh, or turn it on again.");
    $("health-auto-note").hidden = false;
  }

  function healthAutoLoop(me) {
    setTimeout(async () => {
      if (me !== healthRun || $("step-health").hidden || !$("health-auto").checked) return;
      try {
        await loadHealth();
      } catch (e) {
        if (me === healthRun) {
          healthAutoStopped();
          say(String(e), true);
        }
        return;
      }
      if (me === healthRun) healthAutoLoop(me);
    }, HEALTH_EVERY_MS);
  }

  $("open-health").addEventListener("click", (ev) => {
    healthRun++;
    healthPrev = null;
    for (const id of HEALTH_FIELDS) setText(id, "");
    for (const id of ["health-forbidden", "health-metrics-note", "health-status-note", "health-auto-note"]) $(id).hidden = true;
    $("health-metrics").hidden = false;
    $("health-auto").checked = false;
    setText("health-updated", "Not read yet.");
    say("");
    show("step-health");
    run(ev.currentTarget, loadHealth, "Reading the agent's health...");
  });

  $("health-back").addEventListener("click", () => {
    healthRun++;
    say("");
    show("step-devices");
  });

  $("health-refresh").addEventListener("click", (ev) =>
    run(ev.currentTarget, async () => {
      try {
        await loadHealth();
      } catch (e) {
        if ($("health-auto").checked) healthAutoStopped();
        throw e;
      }
    }, "Reading the agent's health...")
  );

  $("health-auto").addEventListener("change", () => {
    const me = ++healthRun;
    $("health-auto-note").hidden = true;
    if (!$("health-auto").checked) return;
    healthAutoLoop(me);
  });

  // Coming back to this screen (from Settings or Transfers) restarts the loop in the last show() wrapper.

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

  // ---- feature:transfers ----
  // Downloads and uploads. The window only asks the Rust core to start, cancel or retry a transfer
  // and polls its list; the core does every network call and every file access.
  steps.push("step-transfers");
  let transfersReturn = "step-connect";
  const transferRows = new Map();
  const transferSeen = new Map();
  let transfersPolling = false;

  function transferSize(n) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    let v = n;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return (i === 0 ? String(v) : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
  }

  function transferPercent(t) {
    if (t.state === "done") return 100;
    return t.total > 0 ? Math.min(100, Math.floor((100 * t.done) / t.total)) : 0;
  }

  function transferText(t) {
    switch (t.state) {
      case "queued":
        return "Waiting for a free slot";
      case "running":
        if (t.total > 0 && t.done >= t.total) return "Checking the file";
        return t.total > 0
          ? transferPercent(t) + "% (" + transferSize(t.done) + " of " + transferSize(t.total) + ")"
          : transferSize(t.done) + " so far";
      case "done":
        return (
          "Done, " + transferSize(t.total) +
          (t.direction === "download" ? ", saved as " + t.localPath : "") +
          (t.verified ? ". Verified by the computer." : ".")
        );
      case "failed":
        return "Failed: " + t.error;
      default:
        return "Cancelled";
    }
  }

  function makeTransferRow(id) {
    const li = document.createElement("li");
    li.className = "transfer";
    li.setAttribute("tabindex", "-1");
    const name = document.createElement("div");
    name.className = "transfer-name";
    const status = document.createElement("div");
    status.className = "transfer-status";
    const bar = document.createElement("progress");
    bar.setAttribute("role", "progressbar");
    bar.setAttribute("aria-valuemin", "0");
    bar.setAttribute("aria-valuemax", "100");
    bar.max = 100;
    const actions = document.createElement("div");
    actions.className = "row";
    const act = (text, command) => {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = text;
      b.addEventListener("click", () =>
        run(b, async () => {
          await invoke(command, { id });
          await pollTransfersOnce();
          pollTransfers();
          li.focus();
        })
      );
      return b;
    };
    const cancel = act("Cancel", "transfer_cancel");
    const retry = act("Retry", "transfer_retry");
    actions.append(cancel, retry);
    li.append(name, status, bar, actions);
    return { li, name, status, bar, cancel, retry };
  }

  function updateTransferRow(row, t) {
    const down = t.direction === "download";
    row.name.textContent = (down ? "Download: " : "Upload: ") + t.name;
    row.li.setAttribute("title", down ? "From " + t.remotePath : "To " + t.remotePath + " from " + t.localPath);
    row.status.textContent = transferText(t);
    row.status.classList.toggle("failed", t.state === "failed");
    const pct = transferPercent(t);
    row.bar.value = pct;
    row.bar.setAttribute("aria-label", (down ? "Downloading " : "Uploading ") + t.name);
    row.bar.setAttribute("aria-valuenow", String(pct));
    row.bar.setAttribute("aria-valuetext", transferText(t));
    row.cancel.hidden = !(t.state === "queued" || t.state === "running" || t.state === "failed");
    row.cancel.setAttribute("aria-label", (t.state === "failed" ? "Give up on " : "Cancel ") + t.name);
    row.retry.hidden = !(t.state === "failed" || t.state === "cancelled");
    row.retry.setAttribute("aria-label", "Retry " + t.name);
  }

  function renderTransfers(list) {
    const order = [];
    for (const t of list) {
      let row = transferRows.get(t.id);
      if (!row) {
        row = makeTransferRow(t.id);
        transferRows.set(t.id, row);
      }
      updateTransferRow(row, t);
      order.push(t.id);
      const before = transferSeen.get(t.id);
      transferSeen.set(t.id, t.state);
      if (before && before !== t.state) {
        if (t.state === "done") $("transfers-status").textContent = t.name + " finished.";
        if (t.state === "failed") say(t.name + " failed: " + t.error, true);
      }
    }
    for (const id of [...transferRows.keys()]) {
      if (!order.includes(id)) {
        transferRows.delete(id);
        transferSeen.delete(id);
      }
    }
    // Rebuild the list only when its rows changed, so a focused button is not torn out under the user.
    const listEl = $("transfer-list");
    const shown = listEl.children;
    const same = shown.length === order.length && order.every((id, i) => shown[i] === transferRows.get(id).li);
    if (!same) listEl.replaceChildren(...order.map((id) => transferRows.get(id).li));
    $("transfers-empty").hidden = order.length !== 0;
    $("transfers-clear").disabled = !list.some((t) => t.state === "done" || t.state === "cancelled");
  }

  async function pollTransfersOnce() {
    const list = await invoke("transfer_list");
    renderTransfers(list);
    return list;
  }

  // Ask the core every half second while the screen is open and something is still moving.
  async function pollTransfers() {
    if (transfersPolling) return;
    transfersPolling = true;
    try {
      while (!$("step-transfers").hidden) {
        let list;
        try {
          list = await pollTransfersOnce();
        } catch (e) {
          say(String(e), true);
          break;
        }
        if (!list.some((t) => t.state === "queued" || t.state === "running")) break;
        await sleep(500);
      }
    } finally {
      transfersPolling = false;
    }
  }

  async function showTransfers() {
    const from = steps.find((id) => !$(id).hidden);
    if (from && from !== "step-transfers") transfersReturn = from;
    show("step-transfers");
    say("");
    $("transfers-status").textContent = "";
    try {
      $("transfers-folder").textContent = await invoke("transfer_folder");
    } catch (e) {
      say(String(e), true);
    }
    await pollTransfers();
  }

  $("open-transfers").addEventListener("click", showTransfers);
  $("transfers-back").addEventListener("click", () => {
    say("");
    if (!current.signedIn) return showConnect();
    show(transfersReturn === "step-transfers" ? "step-devices" : transfersReturn);
  });

  $("download-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    run(submitter(ev), async () => {
      await invoke("transfer_download", { remotePath: $("download-path").value.trim() });
      $("download-path").value = "";
      $("transfers-status").textContent = "Download started.";
      pollTransfers();
    });
  });

  $("upload-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    run(submitter(ev), async () => {
      await invoke("transfer_upload", {
        localPath: $("upload-path").value.trim(),
        remoteDir: $("upload-dir").value.trim(),
      });
      $("upload-path").value = "";
      $("transfers-status").textContent = "Upload started.";
      pollTransfers();
    });
  });

  $("transfers-clear").addEventListener("click", (ev) =>
    run(ev.currentTarget, async () => {
      await invoke("transfer_clear_finished");
      await pollTransfersOnce();
    })
  );

  // For the file browser: start a transfer by path. Resolves to the transfer's id, rejects with the
  // reason. It does not change the screen; the Transfers screen shows the progress.
  window.rfeTransfers = {
    download: async (remotePath) => {
      const id = await invoke("transfer_download", { remotePath: String(remotePath) });
      pollTransfers();
      return id;
    },
    upload: async (localPath, remoteDir) => {
      const id = await invoke("transfer_upload", { localPath: String(localPath), remoteDir: String(remoteDir) });
      pollTransfers();
      return id;
    },
  };

  // ---- file browser -> transfers: a selected file offers a download ----
  // Wraps the file browser's hook (it keeps its own behaviour); a folder never reaches it.
  {
    const btn = $("files-download");
    let picked = null;
    const offer = (entry) => {
      picked = entry && entry.path ? entry : null;
      if (!picked) return;
      btn.textContent = "Download " + (picked.name || picked.path);
      btn.hidden = false;
    };
    const clear = () => {
      picked = null;
      btn.hidden = true;
    };
    const previous = window.rfeFileActions.onFileSelected;
    window.rfeFileActions.onFileSelected = (entry) => {
      previous(entry);
      offer(entry);
    };
    btn.addEventListener("click", async () => {
      if (!picked) return;
      const file = picked;
      btn.disabled = true;
      try {
        await window.rfeTransfers.download(file.path);
        say("Download of " + (file.name || file.path) + " started. Progress is on the Transfers screen.");
      } catch (err) {
        say(String(err), true);
      } finally {
        btn.disabled = false;
      }
    });
    // Moving to another folder, or leaving the screen, drops the offer.
    for (const id of ["files-refresh", "files-back"]) $(id).addEventListener("click", clear);
    if (typeof MutationObserver !== "undefined") new MutationObserver(clear).observe($("files-trail"), { childList: true });
  }

  // ---- integration: pollers that depend on the visible screen ----
  // Last wrapper of show(): coming back to Transfers or Health (from Settings, or from each other)
  // restarts the loop that ended while the screen was hidden, and the pairing-request rows are
  // dropped when the user lands on a screen outside the session.
  {
    const wrapped = show;
    show = function (step) {
      wrapped(step);
      if (step === "step-transfers") pollTransfers();
      if (step === "step-health" && $("health-auto").checked) healthAutoLoop(++healthRun);
      if (PRE_LOGIN.includes(step) && step !== "step-settings") inboxReset();
    };
  }
})();
