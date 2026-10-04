(function () {
  const invoke = window.__TAURI__.core.invoke;
  const $ = (id) => document.getElementById(id);
  const steps = ["step-connect", "step-trust", "step-login", "step-devices"];
  let pending = { host: "", fingerprint: "" };

  function show(step) {
    for (const id of steps) $(id).hidden = id !== step;
  }

  function say(text, isError) {
    const el = $("message");
    el.hidden = !text;
    el.textContent = text || "";
    el.classList.toggle("error", !!isError);
  }

  function submitter(ev) {
    return ev.submitter || ev.target.querySelector('button[type="submit"]');
  }

  async function run(button, fn) {
    button.disabled = true;
    say("");
    try {
      await fn();
    } catch (e) {
      say(String(e), true);
    } finally {
      button.disabled = false;
    }
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
  }

  async function showDevices() {
    // Fetch first: a failure must not leave an empty or stale list on screen.
    const list = await invoke("list_devices");
    renderDevices(list);
    show("step-devices");
  }

  function setSession(saved) {
    const on = saved.signedIn;
    $("session").hidden = !on;
    $("session-text").textContent = on ? saved.username + " on " + saved.host : "";
  }

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
    });
  });

  $("trust").addEventListener("click", () => {
    show("step-login");
    $("username").focus();
  });
  $("trust-cancel").addEventListener("click", () => {
    pending = { host: "", fingerprint: "" };
    show("step-connect");
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
    });
  });

  $("login-back").addEventListener("click", () => {
    $("password").value = "";
    show("step-connect");
  });

  $("refresh").addEventListener("click", (ev) => run(ev.currentTarget, showDevices));

  $("sign-out").addEventListener("click", (ev) =>
    run(ev.currentTarget, async () => {
      const out = await invoke("sign_out");
      renderDevices([]);
      setSession({ signedIn: false });
      show("step-connect");
      if (out.note) say(out.note, true);
    })
  );

  (async function start() {
    try {
      const saved = await invoke("saved_agent");
      if (saved.host) $("host").value = saved.host;
      setSession(saved);
      if (saved.signedIn) {
        await showDevices();
        return;
      }
    } catch (e) {
      say(String(e), true);
    }
    show("step-connect");
  })();
})();
