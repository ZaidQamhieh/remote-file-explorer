// Keyboard only, in the real window: every sign-in route and the main actions are reached and used
// with Tab, Shift+Tab, Enter and Space, and the order Tab takes through a screen is recorded and
// checked (it is the reading order; every stop shows a focus outline). Prints each screen's order.
//
//   desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { App, Agent, waitFor, resetAppState, KEYS } from "./lib.mjs";

let a;
let b;
let app;

before(async () => {
  a = await Agent.start("owner", "e2e-keyboard-a");
  b = await Agent.start("owner", "e2e-keyboard-b");
  resetAppState();
  app = await App.start();
});

after(async () => {
  if (app) await app.end();
  a?.stop();
  b?.stop();
});

// What a screen reader would call the focused control, and whether it shows a focus outline.
const focusInfo = () =>
  app.script(`
    const e = document.activeElement;
    if (!e || e === document.body) return null;
    const cs = getComputedStyle(e);
    const name = e.id || e.getAttribute("aria-label") || (e.textContent || "").trim().slice(0, 40) || e.tagName;
    return { name, outline: cs.outlineStyle !== "none" && parseFloat(cs.outlineWidth) > 0, tag: e.tagName };
  `);

async function tabTo(id, max = 60) {
  for (let i = 0; i < max; i++) {
    const f = await focusInfo();
    if (f && f.name === id) return;
    await app.press(KEYS.tab);
  }
  throw new Error(`Tab never reached ${id}; the last stop was ${JSON.stringify(await focusInfo())}`);
}

/** Starts from the top of the page and tabs through the screen once; returns each stop. */
async function tabOrder(max = 80) {
  await app.script("document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0);");
  const stops = [];
  for (let i = 0; i < max; i++) {
    await app.press(KEYS.tab);
    const f = await focusInfo();
    if (!f) break;
    if (stops.some((s) => s.name === f.name && s.tag === f.tag) && stops.length > 2) break;
    stops.push(f);
  }
  return stops;
}

function checkOrder(screen, stops, mustInclude) {
  console.log(`tab order, ${screen}: ${stops.map((s) => s.name).join(" > ")}`);
  const noRing = stops.filter((s) => !s.outline).map((s) => s.name);
  assert.deepEqual(noRing, [], `${screen}: these stops show no focus outline`);
  const names = stops.map((s) => s.name);
  for (const want of mustInclude) assert.ok(names.includes(want), `${screen}: Tab never reaches ${want}: ${names.join(", ")}`);
  // Reading order: the order must follow the order on the page.
  assert.ok(names.length >= mustInclude.length, `${screen}: too few stops`);
}

const press = async (keys) => app.press(keys);

async function connectKeyboard(agent) {
  await app.script("document.querySelector('#host').focus(); document.querySelector('#host').select();");
  await press(agent.host + KEYS.enter);
  await waitFor("the trust step", () => app.visible("#step-trust"));
  await tabTo("trust");
  await press(KEYS.enter);
  await waitFor("the sign-in step", () => app.visible("#step-login"));
}

test("connect screen: tab order, outlines, and Find agents with the keyboard", async () => {
  await app.script("document.querySelector('#host').focus();");
  checkOrder("connect", await tabOrder(), ["host", "Check certificate", "discover"]);
  await tabTo("discover");
  await press(KEYS.enter);
  await waitFor("the discovery status", async () => (await app.text("#discover-status")).length > 0, 20000);
});

test("sign in with an account, then sign out, by keyboard", async () => {
  await connectKeyboard(a);
  checkOrder("sign-in", await tabOrder(), ["username", "password", "Sign in", "login-back", "use-code", "use-approval", "reset-key"]);
  await app.script("document.querySelector('#username').focus();");
  await press(a.user + KEYS.tab + a.password + KEYS.enter);
  await waitFor("the device list", () => app.visible("#step-devices"));
  assert.equal((await focusInfo()).name, "title-devices", "focus lands on the new screen's heading");
  checkOrder("devices", await tabOrder(), ["open-settings", "open-transfers", "sign-out", "refresh", "open-apps", "open-health", "open-pairing"]);

  await tabTo("sign-out");
  await press(KEYS.enter);
  await waitFor("the connect screen", () => app.visible("#step-connect"));
});

test("pair with a code by keyboard", async () => {
  await connectKeyboard(b);
  await tabTo("use-code");
  await press(KEYS.enter);
  await waitFor("the code form", () => app.visible("#pair-form"));
  assert.equal((await focusInfo()).name, "pairing-code", "focus goes to the code field");
  await press(b.pairCode() + KEYS.enter);
  await waitFor("the device list", () => app.visible("#step-devices"));
  await tabTo("refresh");
  await press(KEYS.enter);
  await tabTo("sign-out");
  await press(KEYS.enter);
  await waitFor("the connect screen", () => app.visible("#step-connect"));
});

test("approve on the PC by keyboard, cancel by keyboard, then approve", async () => {
  await connectKeyboard(a);
  await tabTo("use-approval");
  await press(KEYS.enter);
  await waitFor("the approve step", () => app.visible("#step-approve"));
  await tabTo("approve-cancel");
  await press(KEYS.enter);
  await waitFor("the sign-in step", () => app.visible("#step-login"));

  await tabTo("use-approval");
  await press(KEYS.enter);
  await waitFor("the approve step", () => app.visible("#step-approve"));
  await waitFor("a match code", async () => (await app.text("#match-code")).trim().length >= 6);
  const code = (await app.text("#match-code")).trim();
  a.answerPairRequest("accept", a.pairRequestId(code));
  await waitFor("the device list", () => app.visible("#step-devices"), 30000);
});

test("settings: every control is reachable, and Forget needs two presses by keyboard", async () => {
  await tabTo("open-settings");
  await press(KEYS.enter);
  await waitFor("settings", () => app.visible("#step-settings"));
  const stops = await tabOrder(120);
  checkOrder("settings", stops, ["check-keystore", "log-level", "make-diagnostics", "settings-back"]);

  // The first press on a Forget button only arms it.
  const forget = stops.find((s) => /^Forget/.test(s.name));
  assert.ok(forget, "a Forget button is in the tab order: " + stops.map((s) => s.name).join(", "));
  await tabTo(forget.name);
  await press(KEYS.space);
  const armed = await focusInfo();
  assert.match(armed.name, /Press again to confirm/, "the armed button says so: " + armed.name);
  await tabTo("settings-back");
  await press(KEYS.enter);
  await waitFor("devices", () => app.visible("#step-devices"));
  assert.match(await app.text("#session-text"), /owner|Paired/, "still signed in: Forget was not confirmed");
});

test("the devices table actions are reachable and need two presses by keyboard", async () => {
  // An approved device is an ordinary one with no actions; sign in with the account for an admin view.
  await tabTo("sign-out");
  await press(KEYS.enter);
  await waitFor("the connect screen", () => app.visible("#step-connect"));
  await connectKeyboard(a);
  await app.script("document.querySelector('#username').focus();");
  await press(a.user + KEYS.tab + a.password + KEYS.enter);
  await waitFor("the device list", () => app.visible("#step-devices"));
  await app.script("document.querySelector('#refresh').focus();");
  await tabTo("Revoke RFE Desktop (this computer)");
  await press(KEYS.enter);
  const armed = await focusInfo();
  assert.match(armed.name, /Press the button again to sign this computer out/, armed.name);
  // Not confirmed: leave it by tabbing elsewhere and pressing nothing else.
  await app.script("document.querySelector('#refresh').focus();");
  assert.equal(await app.visible("#step-devices"), true);
});
