// Every screen the signed-in window offers, opened in the real window against a real agent: it must
// appear, say nothing is wrong (no error message), and go back to the device list. Screenshots go to
// E2E_SHOTS when it is set.
//
//   desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { App, Agent, waitFor, sleep, resetAppState } from "./lib.mjs";

let agent;
let app;

before(async () => {
  agent = await Agent.start();
  resetAppState();
  app = await App.start();
  await app.fill("#host", agent.host);
  await app.click('#connect-form button[type="submit"]');
  await waitFor("the trust step", () => app.visible("#step-trust"));
  await app.click("#trust");
  await waitFor("the sign-in step", () => app.visible("#step-login"));
  await app.fill("#username", agent.user);
  await app.fill("#password", agent.password);
  await app.click('#login-form button[type="submit"]');
  await waitFor("the device list", () => app.visible("#step-devices"));
});

after(async () => {
  if (app) await app.end();
  agent?.stop();
});

const errorShown = () =>
  app.script("const m = document.querySelector('#message'); return !m.hidden && m.classList.contains('error') ? m.textContent : '';");

// Opens a screen from the device list, waits for it to settle, checks it, and comes back.
// `expected` is the message a screen is meant to show when the agent refuses it on purpose.
async function visit(slug, open, step, back, expected = "") {
  await app.click(open);
  await waitFor(`${step} to show`, () => app.visible(step));
  await sleep(1500);
  const shown = await errorShown();
  const problem = expected ? (shown.match(expected) ? "" : `expected ${expected}, got "${shown}"`) : shown;
  await app.shot(`6-${slug}.png`);
  // Always go back, so one failing screen cannot leave the rest of the run on the wrong screen.
  await app.click(back);
  await waitFor("the device list again", () => app.visible("#step-devices"));
  assert.equal(problem, "", `${slug}: the screen reports an error`);
}

test("files: the agent's folder opens and lists its contents", async () => {
  await app.click("#open-files");
  await waitFor("the files screen", () => app.visible("#step-files"));
  await waitFor("a location", async () => (await app.rows("#files-locations tr")) >= 1);
  await app.click("#files-locations tr button");
  await waitFor("the folder view", () => app.visible("#files-list-wrap"));
  assert.equal(await errorShown(), "");
  await app.shot("6-files.png");
  await app.click("#files-back");
  await waitFor("the device list again", () => app.visible("#step-devices"));
});

test("transfers", () => visit("transfers", "#open-transfers", "#step-transfers", "#transfers-back"));
test("health and metrics", () => visit("health", "#open-health", "#step-health", "#health-back"));
test("audit and logs", () => visit("audit", "#open-audit", "#step-audit", "#audit-back"));
test("pairing requests", () => visit("pair-inbox", "#open-pair-inbox", "#step-pair-inbox", "#inbox-back"));
// A throwaway agent gives this login no app-viewing grant, so the refusal is the right answer.
test("apps on this PC: the agent's refusal is explained", () =>
  visit("apps", "#open-apps", "#step-apps", "#apps-back", /not allowed to see the host's apps/));

test("pair a phone: a code is generated, shown, and cleared on the way out", async () => {
  await app.click("#open-pairing");
  await waitFor("the pairing screen", () => app.visible("#step-pairing"));
  await app.click("#pcodes-generate");
  await waitFor("a code", async () => (await app.text("#pcodes-code")).trim().length >= 6);
  assert.equal(await errorShown(), "");
  await app.shot("6-pairing.png");
  await app.click("#pcodes-back");
  await waitFor("the device list again", () => app.visible("#step-devices"));
  await app.click("#open-pairing");
  await waitFor("the pairing screen", () => app.visible("#step-pairing"));
  assert.equal((await app.text("#pcodes-code")).trim(), "", "the code does not survive leaving the screen");
  await app.click("#pcodes-back");
});
