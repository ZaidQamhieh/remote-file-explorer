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
              filesSetActive(Math.min(at, files.rows.length - 1), true);
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
})();
