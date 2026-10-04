// The sign-in side of the app in the real window: the list of trusted agents (two pins, the two-click
// Forget, the signed-in marker), pairing with a code, approving on the PC (the match code the window
// shows is the one the agent shows its owner), a login the agent revoked, and the two-click "Create a
// new device key". Screenshots go to E2E_SHOTS when it is set.
//
//   desktop/e2e/run.sh            SCALE=2 desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { App, Agent, waitFor, sleep, resetAppState } from "./lib.mjs";

let a;
let b;
let left; // the agent whose pin survived the Forget test
let app;

before(async () => {
  a = await Agent.start("owner", "e2e-password-a");
  b = await Agent.start("owner", "e2e-password-b");
  resetAppState();
  app = await App.start();
});

after(async () => {
  if (app) await app.end();
  a?.stop();
  b?.stop();
});

// A failure says which screen the window was on and what it said, which is most of the diagnosis.
async function where() {
  return app.req("POST", "/execute/async", { args: [], script:
    "const done = arguments[arguments.length - 1]; const on = [...document.querySelectorAll('main > section')].filter((e) => !e.hidden).map((e) => e.id); const m = document.querySelector('#message'); const t = on.join(',') + ' | ' + (m.hidden ? '' : m.textContent); Promise.all([window.__TAURI__.core.invoke('saved_agent'), window.__TAURI__.core.invoke('list_pins')]).then(([s, p]) => done(t + ' | saved=' + JSON.stringify(s) + ' pins=' + JSON.stringify(p)), (e) => done(t + ' | ' + e));" });
}
const step = (name, fn) =>
  test(name, async () => {
    try {
      await fn();
    } catch (e) {
      e.message += `  [window: ${await where().catch(() => "?")}]`;
      await app.shot(`failed-${name.slice(0, 20).replace(/\W+/g, "-")}.png`).catch(() => {});
      throw e;
    }
  });

const errorShown = () =>
  app.script("const m = document.querySelector('#message'); return !m.hidden && m.classList.contains('error') ? m.textContent : '';");
const messageShown = () => app.script("const m = document.querySelector('#message'); return m.hidden ? '' : m.textContent;");

async function connectAndTrust(agent) {
  await app.fill("#host", agent.host);
  await app.click('#connect-form button[type="submit"]');
  await waitFor("the trust step", () => app.visible("#step-trust"));
  await app.click("#trust");
  await waitFor("the sign-in step", () => app.visible("#step-login"));
}

async function signInAccount(agent) {
  await app.fill("#username", agent.user);
  await app.fill("#password", agent.password);
  await app.click('#login-form button[type="submit"]');
  await waitFor("the device list", () => app.visible("#step-devices"));
}

const pinRows = () => app.rows("#pins tr");

step("trusted agents: two pins are listed and Forget needs a second press", async () => {
  await connectAndTrust(a);
  await signInAccount(a);
  await app.click("#sign-out");
  await waitFor("the connect screen", () => app.visible("#step-connect"));
  // A certificate is only remembered once a sign-in succeeded on it, so B is signed in to as well.
  await connectAndTrust(b);
  await signInAccount(b);
  await app.click("#sign-out");
  await waitFor("the connect screen", () => app.visible("#step-connect"));
  await waitFor("two pins", async () => (await pinRows()) === 2);
  const list = await app.text("#pins");
  assert.ok(list.includes(a.host) && list.includes(b.host), list);
  assert.equal(await app.visible("#pins-block"), true);
  await app.shot("7-trusted-agents.png");

  // The first press only arms the button; nothing is forgotten yet.
  const forget = "#pins tr:first-child button";
  assert.equal((await app.text(forget)).trim(), "Forget");
  await app.click(forget);
  assert.equal((await app.text(forget)).trim(), "Forget?");
  assert.equal(await pinRows(), 2);
  await app.shot("7-forget-armed.png");
  await app.click(forget);
  await waitFor("one pin left", async () => (await pinRows()) === 1);
  assert.equal(await errorShown(), "");
});

step("the signed-in marker and the stronger Forget show on the agent in use", async () => {
  // One pin is left (B or A); sign in to whatever is left and look at it in Settings.
  left = (await app.text("#pins")).includes(a.host) ? a : b;
  await connectAndTrust(left);
  await signInAccount(left);
  await app.click("#open-settings");
  await waitFor("settings", () => app.visible("#step-settings"));
  await waitFor("the pin list", async () => (await app.rows("#settings-pins tr")) === 1);
  assert.match(await app.text("#settings-pins"), /\(signed in\)/);
  const forget = "#settings-pins tr button";
  await app.click(forget);
  assert.match(await app.text(forget), /Forget and sign out\?/);
  await app.shot("7-settings-pins-armed.png");
  // Not confirmed: leave it as it is, and go back signed in.
  await app.click("#settings-back");
  await waitFor("devices", () => app.visible("#step-devices"));
  assert.match(await app.text("#session-text"), /owner/);
});

step("saved hosts: a second agent keeps the first one's login, and switching works", async () => {
  const other = left === a ? b : a;
  await app.click("#open-hosts");
  await waitFor("settings", () => app.visible("#step-settings"));
  await app.click("#hosts-add");
  await waitFor("the connect screen", async () => /new host's address/.test(await messageShown()));
  await connectAndTrust(other);
  await signInAccount(other);
  await app.click("#open-hosts");
  await waitFor("two hosts", async () => (await app.rows("#hosts-list tr")) === 2);
  const list = await app.text("#hosts-list");
  assert.ok(list.includes(a.host) && list.includes(b.host), list);
  assert.match(list, /in use/);
  await app.shot("7-saved-hosts.png");

  // The other agent is parked, not signed out: switching needs no password.
  await app.click('#hosts-list button[aria-label^="Switch to"]');
  await waitFor("the device list", () => app.visible("#step-devices"));
  assert.ok((await app.text("#session-text")).includes(left.host), await app.text("#session-text"));
  assert.equal(await errorShown(), "");
});

step("pair with a one-time code", async () => {
  await app.click("#sign-out");
  await waitFor("the connect screen", () => app.visible("#step-connect"));
  await connectAndTrust(b);
  await app.click("#use-code");
  await waitFor("the code form", () => app.visible("#pair-form"));
  await app.fill("#pairing-code", b.pairCode());
  await app.shot("7-pairing-code-form.png");
  await app.click('#pair-form button[type="submit"]');
  await waitFor("the device list", () => app.visible("#step-devices"));
  assert.match(await app.text("#session-text"), /Paired with/);
  assert.match(await app.text("#devices"), /this computer/);
  // A code makes an ordinary device: it sees only itself, and the window says why.
  assert.equal(await app.visible("#devices-note"), true);
  await app.shot("7-paired-with-code.png");
});

step("approve on the PC: the match code is the one the agent shows its owner", async () => {
  await app.click("#sign-out");
  await waitFor("the connect screen", () => app.visible("#step-connect"));
  await connectAndTrust(a);
  await app.click("#use-approval");
  await waitFor("the approve step", () => app.visible("#step-approve"));
  await waitFor("the match code", async () => (await app.text("#match-code")).trim().length >= 6);
  const shown = (await app.text("#match-code")).trim();
  const onPc = a.pairRequests();
  assert.ok(onPc.includes(shown), `window: ${shown}; agent: ${onPc}`);
  await app.shot("7-approve-on-pc.png");

  // Cancel only stops waiting: the window is back at sign-in. (The agent has no call to withdraw a
  // request, so it stays on the PC's list until it expires; nobody is collecting it.)
  await app.click("#approve-cancel");
  await waitFor("the sign-in step", () => app.visible("#step-login"));

  // Again, and this time the owner accepts the new request (matched by its code, as the owner would).
  await app.click("#use-approval");
  await waitFor("the approve step", () => app.visible("#step-approve"));
  await waitFor("a new match code", async () => {
    const code = (await app.text("#match-code")).trim();
    return code.length >= 6 && code !== shown;
  });
  const second = (await app.text("#match-code")).trim();
  a.answerPairRequest("accept", a.pairRequestId(second));
  await waitFor("the device list", () => app.visible("#step-devices"), 30000);
  assert.equal(await errorShown(), "");
});

step("a login the agent revoked sends the window back to sign-in with the reason", async () => {
  // Signed in through approval: its device id is in the agent's list; revoke every active device.
  const rows = a.devices().split("\n").filter((l) => /RFE Desktop/.test(l));
  assert.ok(rows.length >= 1, a.devices());
  for (const line of rows) a.revoke(line.trim().split(/\s+/)[0]);
  await app.click("#refresh");
  await waitFor("the sign-in step", () => app.visible("#step-login"), 20000);
  assert.notEqual(await messageShown(), "", "the window says why");
  await app.shot("7-login-revoked.png");
});

step("Create a new device key needs two presses", async () => {
  const link = "#reset-key";
  assert.match((await app.text(link)).trim(), /^Create a new device key/);
  await app.click(link);
  assert.match((await app.text(link)).trim(), /^Click again/);
  await app.shot("7-reset-key-armed.png");
  await app.click(link);
  await waitFor("the note", async () => /A new device key will be created/.test(await messageShown()));
  assert.equal(await errorShown(), "");
  await sleep(200);
  await app.shot("7-reset-key-done.png");
});
