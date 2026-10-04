// Which screen and message the window shows in each error, empty and loading state, driving
// desktop/ui/app.js against a fake DOM with `invoke` answered by the test. This does not check how
// the window looks; that needs real pixels.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, deferred, SIGNED_OUT, SIGNED_IN } from "./harness.mjs";

const device = (o = {}) => ({ id: "d1", label: "Laptop", created: 1, lastSeen: 0, revoked: false, current: true, lastAddress: "", lastVersion: "", viaLogin: true, ...o });

test("keystore locked at start: connect screen with the reason, not a blank window", async () => {
  const app = boot({
    saved_agent: () => Promise.reject("the OS keystore did not answer within 30s. Secrets are never saved to files."),
    list_pins: [],
  });
  await settle();
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.match(app.message(), /keystore did not answer/);
  assert.ok(app.els.message.classList.contains("error"));
});

test("keystore slow at start: says it may be asking to unlock, shows no screen yet", async () => {
  const gate = deferred();
  const app = boot({ saved_agent: () => gate.promise, list_pins: [] });
  await settle();
  assert.deepEqual(app.screen(), []);
  assert.match(app.message(), /OS keystore.*unlock/);
  gate.resolve(SIGNED_OUT);
  await settle();
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.equal(app.message(), "");
});

test("agent unreachable: stays on connect, shows the error, button usable again", async () => {
  const app = boot({
    saved_agent: SIGNED_OUT,
    list_pins: [],
    probe_agent: () => Promise.reject("cannot reach the agent securely: connection refused. Check that the agent is running and the address is right."),
  });
  await settle();
  await app.els["connect-form"].fire("submit");
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.match(app.message(), /cannot reach the agent/);
  assert.ok(app.els.message.classList.contains("error"));
  assert.equal(app.els["connect-form"].disabled, false);
});

test("slow agent: busy text while waiting, gone afterwards, button disabled meanwhile", async () => {
  const gate = deferred();
  const app = boot({ saved_agent: SIGNED_OUT, list_pins: [], probe_agent: () => gate.promise });
  await settle();
  const pressed = app.els["connect-form"].fire("submit");
  await settle();
  assert.match(app.message(), /Reading the agent's certificate/);
  assert.equal(app.els["connect-form"].disabled, true);
  gate.resolve({ fingerprint: "cd".repeat(32), previous: "", changed: false });
  await pressed;
  await settle();
  assert.equal(app.message(), "");
  assert.equal(app.els["connect-form"].disabled, false);
  assert.deepEqual(app.screen(), ["step-trust"]);
});

test("certificate changed since last time: warning shown, button says so", async () => {
  const app = boot({
    saved_agent: SIGNED_OUT,
    list_pins: [],
    probe_agent: { fingerprint: "cd".repeat(32), previous: "ab".repeat(32), changed: true },
  });
  await settle();
  await app.els["connect-form"].fire("submit");
  assert.deepEqual(app.screen(), ["step-trust"]);
  assert.equal(app.els.changed.hidden, false);
  assert.match(app.els.changed.textContent, /different from the one you trusted/);
  assert.match(app.els.trust.textContent, /know it changed/);
});

test("certificate changed while signed in: the refusal is shown and nothing is listed", async () => {
  const app = boot({
    saved_agent: SIGNED_IN,
    list_devices: () => Promise.reject("This agent's certificate is not the one you trusted (certificate fingerprint mismatch). Do not sign in."),
    list_pins: [],
  });
  await settle();
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.match(app.message(), /not the one you trusted/);
  assert.equal(app.els.devices.children.length, 0);
});

test("no devices: the empty message shows, the short-list note does not", async () => {
  const app = boot({ saved_agent: SIGNED_IN, list_devices: [] });
  await settle();
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.equal(app.els["devices-empty"].hidden, false);
  assert.equal(app.els["devices-note"].hidden, true);
  assert.equal(app.message(), "");
});

test("a code-paired device sees only itself: the note explains why", async () => {
  const app = boot({ saved_agent: SIGNED_IN, list_devices: [device({ viaLogin: false })] });
  await settle();
  assert.equal(app.els["devices-empty"].hidden, true);
  assert.equal(app.els["devices-note"].hidden, false);
  assert.equal(app.els.devices.children.length, 1);
});

test("slow device list: loading text, then the list", async () => {
  const gate = deferred();
  const app = boot({ saved_agent: SIGNED_IN, list_devices: () => gate.promise });
  await settle();
  assert.match(app.message(), /Loading devices/);
  gate.resolve([device()]);
  await settle();
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.equal(app.message(), "");
});

test("refresh fails: the error shows and the list already on screen stays", async () => {
  let fail = false;
  const app = boot({
    saved_agent: () => SIGNED_IN,
    list_devices: () => (fail ? Promise.reject("cannot reach the agent securely: timed out") : [device()]),
  });
  await settle();
  fail = true;
  await app.els.refresh.fire("click");
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.match(app.message(), /cannot reach the agent/);
  assert.equal(app.els.devices.children.length, 1);
  assert.equal(app.els.refresh.disabled, false);
});

test("agent refuses the saved login: back to sign-in on that agent with the reason", async () => {
  const app = boot({
    saved_agent: (() => {
      let n = 0;
      return () => (n++ === 0 ? SIGNED_IN : { ...SIGNED_OUT, fingerprint: "ab".repeat(32), username: "zaid" });
    })(),
    list_devices: () => Promise.reject("The agent no longer accepts this login. Sign in again."),
  });
  await settle();
  assert.deepEqual(app.screen(), ["step-login"]);
  assert.match(app.message(), /no longer accepts this login/);
  assert.equal(app.els.username.value, "zaid");
});

test("approval rejected on the PC: back to sign-in with the reason", async () => {
  const app = boot({
    saved_agent: SIGNED_OUT,
    list_pins: [],
    probe_agent: { fingerprint: "cd".repeat(32), previous: "", changed: false },
    request_pairing: { matchCode: "1234 5678", expiresInSeconds: 60 },
    poll_pairing: { status: "rejected", saved: null },
  });
  await settle();
  await app.els["connect-form"].fire("submit");
  await app.els.trust.fire("click");
  await app.els["use-approval"].fire("click");
  await settle();
  assert.deepEqual(app.screen(), ["step-login"]);
  assert.match(app.message(), /rejected on the PC/);
});

test("trusted agents: the list is hidden when empty and shown with one row per agent", async () => {
  let pins = [];
  const app = boot({ saved_agent: SIGNED_OUT, list_pins: () => pins });
  await settle();
  assert.equal(app.els["pins-block"].hidden, true);
  pins = [{ host: "pc:8765", fingerprint: "ab".repeat(32), active: false }];
  await app.els["trust-cancel"].fire("click");
  assert.equal(app.els["pins-block"].hidden, false);
  assert.equal(app.els.pins.children.length, 1);
});
