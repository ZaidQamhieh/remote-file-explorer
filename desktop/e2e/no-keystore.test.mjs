// A session with no Secret Service at all (no gnome-keyring, KeePassXC or KWallet on the bus): the
// window still opens, and signing in stops with a message that says what to install, before the
// agent is asked for anything. Runs only in a session started without a keyring:
//
//   RFE_E2E_NO_KEYRING=1 RFE_E2E_ONLY=no-keystore desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { App, Agent, waitFor, resetAppState } from "./lib.mjs";

const without = process.env.RFE_E2E_NO_KEYRING === "1";
let agent;
let app;

before(async () => {
  if (without) agent = await Agent.start();
});

after(async () => {
  if (app) await app.end();
  agent?.stop();
});

test("no Secret Service: the window opens and sign-in says what is missing", { skip: !without }, async () => {
  resetAppState();
  app = await App.start();
  await waitFor("the connect step", () => app.visible("#step-connect"));
  await app.fill("#host", agent.host);
  await app.click('#connect-form button[type="submit"]');
  await waitFor("the trust step", () => app.visible("#step-trust"));
  await app.click("#trust");
  await waitFor("the sign-in step", () => app.visible("#step-login"));
  await app.fill("#username", agent.user);
  await app.fill("#password", agent.password);
  await app.click('#login-form button[type="submit"]');

  // "Signing in..." shows first; the answer replaces it.
  await waitFor("the answer", async () => {
    const t = await app.text("#message");
    return t.length > 0 && !/^Signing in/.test(t);
  });
  const said = await app.text("#message");
  console.log(`message shown: ${said}`);
  assert.match(said, /keystore|Secret Service|keyring/i, said);
  assert.ok(await app.visible("#step-login"), "still on the sign-in step");
  assert.doesNotMatch(agent.devices(), /RFE Desktop/, "nothing was enrolled on the agent");
  await app.shot("7-no-keystore.png");

  // Settings: the keystore test says it is not working, and the message beside it says why.
  await app.click("#open-settings");
  await waitFor("settings", () => app.visible("#step-settings"));
  await app.click("#check-keystore");
  await waitFor("the keystore result", async () => (await app.text("#keystore-result")).length > 0);
  assert.match(await app.text("#keystore-result"), /Not working/);
  await waitFor("the reason", async () => /Secret Service/i.test(await app.text("#message")));
});
