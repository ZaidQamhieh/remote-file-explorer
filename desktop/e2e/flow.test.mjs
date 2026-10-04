// The first-run flow in the real window: type the address, compare the fingerprint, trust, sign in,
// see this computer in the device table, open Settings, sign out. Real WebKit, real keyring, a
// real agent; nothing is faked. Screenshots go to E2E_SHOTS when it is set.
//
//   desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { App, Agent, waitFor, resetAppState, KEYS } from "./lib.mjs";

let agent;
let app;

before(async () => {
  agent = await Agent.start();
});

after(async () => {
  if (app) await app.end();
  agent?.stop();
});

const norm = (s) => s.replace(/[^0-9a-fA-F]/g, "").toLowerCase();

test("first run: address, compare fingerprint, trust, sign in, devices, settings, sign out", async () => {
  resetAppState();
  app = await App.start();
  await app.fill("#host", agent.host);
  await app.shot("1-connect.png");
  await app.click('#connect-form button[type="submit"]');

  await waitFor("the trust step", () => app.visible("#step-trust"));
  assert.equal(norm(await app.text("#fingerprint")), agent.fingerprint(), "the window shows the agent's own fingerprint");
  await app.shot("2-trust.png");
  await app.click("#trust");

  await waitFor("the sign-in step", () => app.visible("#step-login"));
  await app.fill("#username", agent.user);
  await app.fill("#password", agent.password);
  await app.shot("3-login.png");
  await app.click('#login-form button[type="submit"]');

  await waitFor("the device list", () => app.visible("#step-devices"));
  await waitFor("a row", async () => (await app.rows("#devices tr")) >= 1);
  assert.match(await app.text("#devices"), /this computer/);
  assert.match(await app.text("#session-text"), new RegExp(agent.user));
  assert.match(agent.devices(), /RFE Desktop/, "the agent lists the paired device");
  await app.shot("4-devices.png");

  // Settings, then back.
  await app.click("#open-settings");
  await waitFor("settings", () => app.visible("#step-settings"));
  assert.match(await app.text("#about-version"), /\d+\.\d+\.\d+/);
  await app.click("#check-keystore");
  await waitFor("the keystore result", async () => (await app.text("#keystore-result")).length > 0);
  assert.doesNotMatch(await app.text("#keystore-result"), /fail|error|cannot/i);
  await app.click("#settings-back");
  await waitFor("devices again", () => app.visible("#step-devices"));
  await app.shot("5-back.png");

  await app.click("#sign-out");
  await waitFor("connect after sign out", () => app.visible("#step-connect") || app.visible("#step-login"));
});

test("keyboard only: the whole sign-in without touching the mouse", async () => {
  resetAppState();
  await app.end();
  app = await App.start();
  await app.script("document.querySelector('#host').focus();");
  await app.press(agent.host);
  await app.press(KEYS.enter);
  await waitFor("the trust step", () => app.visible("#step-trust"));
  // Focus moves to the step's heading; Tab reaches the trust button first.
  assert.equal(await app.focused(), "title-trust");
  await app.press(KEYS.tab);
  assert.equal(await app.focused(), "trust");
  await app.press(KEYS.enter);
  await waitFor("the sign-in step", () => app.visible("#step-login"));
  assert.equal(await app.focused(), "username", "sign-in starts in the username field");
  await app.press(agent.user + KEYS.tab + agent.password + KEYS.enter);
  await waitFor("the device list", () => app.visible("#step-devices"));
  assert.equal(await app.focused(), "title-devices");
});
