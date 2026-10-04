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
  // ---- feature:transfers ----
  // Downloads and uploads. The window only asks the Rust core to start, cancel or retry a transfer
  // and polls its list; the core does every network call and every file access.
  steps.push("step-transfers");
  let transfersReturn = "step-connect";
  const transferRows = new Map();
  const transferSeen = new Map();
  let transfersPolling = false;

  function fmtSize(n) {
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
          ? transferPercent(t) + "% (" + fmtSize(t.done) + " of " + fmtSize(t.total) + ")"
          : fmtSize(t.done) + " so far";
      case "done":
        return (
          "Done, " + fmtSize(t.total) +
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
      await pollTransfers();
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
      await pollTransfers();
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
})();
