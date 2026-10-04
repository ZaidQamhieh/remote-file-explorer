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
})();
