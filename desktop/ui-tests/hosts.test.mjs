// Saved hosts in Settings: list, switch, rename, remove with two clicks, add. Driven against the
// same fake DOM as the other screens.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, focused, SIGNED_OUT, SIGNED_IN } from "./harness.mjs";

const INFO = {
  logLevel: "info",
  appVersion: "0.1.0",
  clientVersion: "desktop-0.1.0",
  minAgentForApproval: "agent-v1.43.0-rc.1",
  dataDir: "/data",
  platform: "linux",
};
const FP = "ab".repeat(32);
const OFFICE = { key: "pc:8765", name: "Office PC", host: "pc:8765", fingerprint: FP, username: "zaid", signedIn: true, active: true };
const LAB = { key: "lab:8765", name: "lab:8765", host: "lab:8765", fingerprint: "cd".repeat(32), username: "", signedIn: false, active: false };
const HOME = { key: "home:8765", name: "Home", host: "home:8765", fingerprint: "ef".repeat(32), username: "mo", signedIn: true, active: false };

const base = (more = {}) => ({
  saved_agent: SIGNED_IN,
  list_devices: [],
  list_pins: [],
  app_settings: INFO,
  list_hosts: [OFFICE, LAB, HOME],
  ...more,
});

const rows = (app) => app.els["hosts-list"].children;
const buttons = (row) => row.children[3].children;

async function openHosts(app) {
  await settle();
  await app.els["open-settings"].fire("click");
}

test("Settings lists the saved hosts, marks the one in use and says who is signed in", async () => {
  const app = boot(base());
  await openHosts(app);
  assert.equal(rows(app).length, 3);
  assert.equal(rows(app)[0].children[0].textContent, "Office PC (in use)");
  assert.equal(rows(app)[0].children[1].textContent, "pc:8765");
  assert.equal(rows(app)[0].children[2].textContent, "Signed in as zaid");
  assert.equal(rows(app)[1].children[2].textContent, "Signed out");
  assert.deepEqual(buttons(rows(app)[0]).map((b) => b.textContent), ["Open", "Rename", "Remove"]);
  assert.deepEqual(buttons(rows(app)[1]).map((b) => b.textContent), ["Switch", "Rename", "Remove"]);
  assert.equal(app.els["hosts-empty"].hidden, true);
  // Every row's buttons say which host they act on.
  assert.equal(buttons(rows(app)[2])[0].attrs["aria-label"], "Switch to Home");
  assert.equal(buttons(rows(app)[2])[2].attrs["aria-label"], "Remove Home");
});

test("a host name is shown as text, never as markup", async () => {
  const evil = { ...HOME, name: "<img src=x onerror=alert(1)>" };
  const app = boot(base({ list_hosts: [evil] }));
  await openHosts(app);
  assert.equal(rows(app)[0].children[0].textContent, "<img src=x onerror=alert(1)>");
  assert.equal(rows(app)[0].children[0].children.length, 0);
});

test("no saved host shows the empty note", async () => {
  const app = boot(base({ list_hosts: [] }));
  await openHosts(app);
  assert.equal(app.els["hosts-empty"].hidden, false);
});

test("switching to a host with a saved login opens its devices without a password", async () => {
  let asked;
  const app = boot(
    base({
      switch_host: (a) => {
        asked = a;
        return { host: "home:8765", fingerprint: "ef".repeat(32), signedIn: true, username: "mo", deviceId: "d9" };
      },
    })
  );
  await openHosts(app);
  await buttons(rows(app)[2])[0].fire("click");
  assert.equal(JSON.stringify(asked), JSON.stringify({ key: "home:8765" }));
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.equal(app.els["session-text"].textContent, "mo on home:8765");
  assert.ok(app.calls.filter((c) => c === "list_devices").length >= 2, "devices of the new host were loaded");
  assert.ok(!app.calls.includes("login"));
});

test("switching to a signed-out host goes to sign-in on that host with the account name filled in", async () => {
  let sent;
  const app = boot(
    base({
      switch_host: { host: "lab:8765", fingerprint: "cd".repeat(32), signedIn: false, username: "ops" },
      login: (a) => ((sent = a), { host: a.host, fingerprint: a.fingerprint, signedIn: true, username: a.username }),
    })
  );
  await openHosts(app);
  await buttons(rows(app)[1])[0].fire("click");
  assert.deepEqual(app.screen(), ["step-login"]);
  assert.equal(app.els.username.value, "ops");
  assert.match(app.message(), /Signed out on this host/);
  // Signing in now goes to that host, with the fingerprint that was pinned for it.
  app.els.password.value = "pw";
  await app.els["login-form"].fire("submit");
  assert.equal(sent.host, "lab:8765");
  assert.equal(sent.fingerprint, "cd".repeat(32));
});

test("a refused switch stays in Settings and says why", async () => {
  const app = boot(
    base({ switch_host: () => Promise.reject("lab:8765 is no longer a trusted agent; connect and compare its fingerprint again") })
  );
  await openHosts(app);
  await buttons(rows(app)[1])[0].fire("click");
  assert.deepEqual(app.screen(), ["step-settings"]);
  assert.match(app.message(), /no longer a trusted agent/);
  assert.equal(app.els.message.attrs.role, "alert");
});

test("rename: the name cell becomes a labelled field, Save sends the key and the new name", async () => {
  let sent;
  const app = boot(base({ rename_host: (a) => ((sent = a), undefined) }));
  await openHosts(app);
  const row = rows(app)[1];
  await buttons(row)[1].fire("click");
  const input = row.children[0].children[0];
  assert.equal(input.attrs["aria-label"], "New name for lab:8765");
  assert.equal(input.value, "lab:8765");
  input.value = "Lab";
  const save = row.children[3].children[0];
  assert.equal(save.textContent, "Save");
  await save.fire("click");
  assert.equal(JSON.stringify(sent), JSON.stringify({ key: "lab:8765", name: "Lab" }));
  assert.equal(app.els["hosts-status"].textContent, "Renamed.");
});

test("rename: Enter saves, Escape puts the list back, a refused name is shown", async () => {
  const calls = [];
  const app = boot(
    base({
      rename_host: (a) => (calls.push(a), a.name.length > 3 ? Promise.reject("the name can be at most 64 characters") : undefined),
    })
  );
  await openHosts(app);
  let row = rows(app)[1];
  await buttons(row)[1].fire("click");
  let input = row.children[0].children[0];
  input.value = "Long name";
  for (const fn of input.listeners.keydown) fn({ key: "Enter", preventDefault() {} });
  await settle();
  assert.equal(calls.length, 1);
  assert.match(app.message(), /at most 64 characters/);

  // A refused name leaves the field open to correct; Escape then gives up.
  input = rows(app)[1].children[0].children[0];
  assert.ok(input, "still editing after a refusal");
  for (const fn of input.listeners.keydown) fn({ key: "Escape", preventDefault() {} });
  await settle();
  assert.equal(rows(app)[1].children[0].children.length, 0, "back to plain text");
  assert.equal(calls.length, 1, "Escape saves nothing");
});

test("remove needs two presses and the first sends nothing", async () => {
  let removed;
  const app = boot(base({ remove_host: (a) => ((removed = a), { wasActive: false }) }));
  await openHosts(app);
  const remove = buttons(rows(app)[2])[2];
  await remove.fire("click");
  assert.equal(removed, undefined);
  assert.match(remove.attrs["aria-label"], /Remove and delete the saved login for Home\? Press again to confirm\./);
  await remove.fire("click");
  assert.equal(JSON.stringify(removed), JSON.stringify({ key: "home:8765" }));
  assert.equal(app.els["hosts-status"].textContent, "Removed Home.");
  assert.deepEqual(app.screen(), ["step-settings"]);
});

test("removing the host in use signs the window out and Back goes to the connect screen", async () => {
  const app = boot(base({ remove_host: { wasActive: true } }));
  await openHosts(app);
  const remove = buttons(rows(app)[0])[2];
  await remove.fire("click");
  await remove.fire("click");
  assert.equal(app.els.session.hidden, true);
  assert.equal(app.els["settings-account"].textContent, "Not signed in.");
  await app.els["settings-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-connect"]);
});

test("a list that cannot be read is reported in the hosts block, not as a page error", async () => {
  const app = boot(base({ list_hosts: () => Promise.reject("hosts.json is damaged (x); delete it to start over") }));
  await openHosts(app);
  assert.match(app.els["hosts-status"].textContent, /hosts\.json is damaged/);
  assert.equal(app.message(), "");
});

test("Hosts in the header opens Settings and puts focus on the saved hosts heading", async () => {
  const app = boot(base());
  await settle();
  focused.length = 0;
  await app.els["open-hosts"].fire("click");
  assert.deepEqual(app.screen(), ["step-settings"]);
  assert.equal(rows(app).length, 3);
  assert.equal(focused.at(-1), "title-hosts");
});

test("Add another host opens the connect screen with an empty address and keeps the login", async () => {
  const app = boot(base());
  await openHosts(app);
  await app.els["hosts-add"].fire("click");
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.equal(app.els.host.value, "");
  assert.match(app.message(), /Your current login stays saved/);
  assert.ok(!app.calls.includes("sign_out") && !app.calls.includes("remove_host"));
});

test("with nothing saved the app still opens on the connect screen", async () => {
  const app = boot({ saved_agent: SIGNED_OUT, list_pins: [] });
  await settle();
  assert.deepEqual(app.screen(), ["step-connect"]);
});
