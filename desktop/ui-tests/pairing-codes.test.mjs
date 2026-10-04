// The "Pair a phone" screen: which state shows when, the countdown, and that the code leaves the
// window the moment the user leaves the screen. Driven against the fake DOM with `invoke` answered
// by the test and a clock the test moves; how it looks needs real pixels.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { boot, settle, deferred, focused, SIGNED_OUT, SIGNED_IN } from "./harness.mjs";

const device = { id: "d1", label: "Laptop", created: 1, lastSeen: 0, revoked: false, current: true, lastAddress: "", lastVersion: "", viaLogin: true };
const CODE = "K7M2QX9P";

// A clock and a timer queue the test moves by hand, so the countdown takes no real time.
function clock() {
  let now = 1_700_000_000_000;
  const queue = [];
  class FakeDate extends Date {
    static now() {
      return now;
    }
  }
  return {
    extra: { Date: FakeDate, setTimeout: (fn, ms) => queue.push({ at: now + ms, fn }) },
    async advance(seconds) {
      for (let i = 0; i < seconds; i++) {
        now += 1000;
        const due = queue.filter((t) => t.at <= now);
        queue.splice(0, queue.length, ...queue.filter((t) => t.at > now));
        for (const t of due) t.fn();
        await settle();
      }
    },
  };
}

const visible = (app, id) => !app.els[id].hidden;
const onPairingScreen = (app) => visible(app, "step-pairing");

// Every test gets a clock it never moves unless it says so: the harness's own timer runs at once, and
// a countdown on a real clock would spin for ten minutes.
async function openPairing(handlers = {}, extra = clock().extra) {
  const app = boot(
    {
      saved_agent: SIGNED_IN,
      list_devices: [device],
      generate_pairing_code: { status: "ok", code: CODE, expiresInSeconds: 600 },
      ...handlers,
    },
    extra
  );
  await settle();
  assert.deepEqual(app.screen(), ["step-devices"]);
  await app.els["open-pairing"].fire("click");
  return app;
}

test("opening the screen shows no code and moves focus to its heading", async () => {
  focused.length = 0;
  const app = await openPairing();
  assert.ok(onPairingScreen(app));
  assert.equal(focused.at(-1), "title-pairing");
  assert.ok(!visible(app, "pcodes-code-block"));
  assert.equal(app.els["pcodes-code"].textContent, "");
  assert.equal(app.calls.includes("generate_pairing_code"), false, "opening mints nothing");
});

test("generate shows the code as text with its expiry, and the button offers a new one", async () => {
  const c = clock();
  const app = await openPairing({}, c.extra);
  await app.els["pcodes-generate"].fire("click");
  assert.equal(app.els["pcodes-code"].textContent, CODE);
  assert.ok(visible(app, "pcodes-code-block"));
  assert.equal(app.els["pcodes-expiry"].textContent, "Expires in 10:00.");
  assert.equal(app.els["pcodes-generate"].textContent, "Generate a new code");
  assert.ok(!visible(app, "pcodes-forbidden") && !visible(app, "pcodes-expired"));
  assert.equal(app.message(), "");
  // The code announces itself (a status region) and is labelled by visible text.
  assert.equal(app.els["pcodes-code"].names.has("mono"), true);
});

test("the countdown ticks down, and at zero the code is gone and the screen says so", async () => {
  const c = clock();
  const app = await openPairing({ generate_pairing_code: { status: "ok", code: CODE, expiresInSeconds: 3 } }, c.extra);
  await app.els["pcodes-generate"].fire("click");
  assert.equal(app.els["pcodes-expiry"].textContent, "Expires in 0:03.");
  await c.advance(1);
  assert.equal(app.els["pcodes-expiry"].textContent, "Expires in 0:02.");
  await c.advance(1);
  assert.equal(app.els["pcodes-expiry"].textContent, "Expires in 0:01.");
  focused.length = 0;
  await c.advance(1);
  assert.equal(app.els["pcodes-code"].textContent, "", "the code is cleared at expiry");
  assert.ok(!visible(app, "pcodes-code-block"));
  assert.ok(visible(app, "pcodes-expired"));
  assert.equal(focused.at(-1), "pcodes-generate", "focus is not left on a hidden control");
});

test("a login that is not an admin one gets the not-allowed state, not a code or a crash", async () => {
  const app = await openPairing({ generate_pairing_code: { status: "forbidden", code: "", expiresInSeconds: 0 } });
  await app.els["pcodes-generate"].fire("click");
  assert.ok(visible(app, "pcodes-forbidden"));
  assert.ok(!visible(app, "pcodes-code-block"));
  assert.equal(app.els["pcodes-code"].textContent, "");
  assert.ok(onPairingScreen(app), "stays on the screen");
  assert.equal(app.els["pcodes-generate"].disabled, false, "the button is usable again");
  assert.equal(app.message(), "");
});

test("the not-allowed state goes away when the next attempt works", async () => {
  let n = 0;
  const app = await openPairing({
    generate_pairing_code: () => (n++ === 0 ? { status: "forbidden", code: "", expiresInSeconds: 0 } : { status: "ok", code: CODE, expiresInSeconds: 600 }),
  });
  await app.els["pcodes-generate"].fire("click");
  assert.ok(visible(app, "pcodes-forbidden"));
  await app.els["pcodes-generate"].fire("click");
  assert.ok(!visible(app, "pcodes-forbidden"));
  assert.equal(app.els["pcodes-code"].textContent, CODE);
});

test("an agent error is shown as an alert and no code appears", async () => {
  const app = await openPairing({ generate_pairing_code: () => Promise.reject("cannot reach the agent securely: connection refused.") });
  await app.els["pcodes-generate"].fire("click");
  assert.match(app.message(), /cannot reach the agent/);
  assert.equal(app.els.message.attrs.role, "alert");
  assert.ok(!visible(app, "pcodes-code-block"));
  assert.equal(app.els["pcodes-generate"].disabled, false);
});

test("a login the agent no longer accepts sends the window back to sign-in", async () => {
  const dead = { ...SIGNED_OUT, fingerprint: "ab".repeat(32), username: "zaid" };
  let signedIn = true;
  const app = await openPairing({
    saved_agent: () => (signedIn ? SIGNED_IN : dead),
    generate_pairing_code: () => {
      signedIn = false;
      return Promise.reject("The agent no longer accepts this login. Sign in again.");
    },
  });
  await app.els["pcodes-generate"].fire("click");
  assert.deepEqual(app.screen(), ["step-login"]);
  assert.match(app.message(), /no longer accepts this login/);
  assert.equal(app.els.username.value, "zaid");
});

test("generating again takes the old code off the screen first and shows the new one", async () => {
  const gate = deferred();
  let n = 0;
  const app = await openPairing({
    generate_pairing_code: () => (n++ === 0 ? { status: "ok", code: CODE, expiresInSeconds: 600 } : gate.promise),
  });
  await app.els["pcodes-generate"].fire("click");
  assert.equal(app.els["pcodes-code"].textContent, CODE);
  const second = app.els["pcodes-generate"].fire("click");
  await settle();
  assert.equal(app.els["pcodes-code"].textContent, "", "the old code is gone while the new one is made");
  assert.match(app.message(), /Asking the agent for a code/);
  assert.equal(app.els["pcodes-generate"].disabled, true);
  gate.resolve({ status: "ok", code: "NEWCODE2", expiresInSeconds: 600 });
  await second;
  await settle();
  assert.equal(app.els["pcodes-code"].textContent, "NEWCODE2");
  assert.equal(app.message(), "");
});

test("Back clears the code and returns to the devices", async () => {
  const app = await openPairing();
  await app.els["pcodes-generate"].fire("click");
  assert.equal(app.els["pcodes-code"].textContent, CODE);
  await app.els["pcodes-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.equal(app.els["pcodes-code"].textContent, "");
  await app.els["open-pairing"].fire("click");
  assert.ok(!visible(app, "pcodes-code-block"), "coming back shows no old code");
});

test("opening Settings from the screen clears the code, and Back from Settings shows none", async () => {
  const app = await openPairing({
    app_settings: { logLevel: "info", appVersion: "1", clientVersion: "desktop-1", minAgentForApproval: "x", dataDir: "/d", platform: "linux" },
    list_pins: [],
  });
  await app.els["pcodes-generate"].fire("click");
  assert.equal(app.els["pcodes-code"].textContent, CODE);
  await app.els["open-settings"].fire("click");
  assert.deepEqual(app.screen(), ["step-settings"]);
  assert.equal(app.els["pcodes-code"].textContent, "");
  await app.els["settings-back"].fire("click");
  assert.ok(onPairingScreen(app));
  assert.equal(app.els["pcodes-code"].textContent, "");
  assert.ok(!visible(app, "pcodes-code-block"));
});

test("sign-out removes the code the moment it is pressed, not when the agent answers", async () => {
  const gate = deferred();
  const app = await openPairing({ sign_out: () => gate.promise });
  await app.els["pcodes-generate"].fire("click");
  assert.equal(app.els["pcodes-code"].textContent, CODE);
  const pressed = app.els["sign-out"].fire("click");
  await settle();
  assert.equal(app.els["pcodes-code"].textContent, "", "gone while sign-out is still in flight");
  gate.resolve({ revoked: true, note: "" });
  await pressed;
  await settle();
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.equal(app.els["pcodes-code"].textContent, "");
});

test("an answer that arrives after the user left is thrown away", async () => {
  const gate = deferred();
  const app = await openPairing({ generate_pairing_code: () => gate.promise });
  const pressed = app.els["pcodes-generate"].fire("click");
  await settle();
  await app.els["pcodes-back"].fire("click");
  gate.resolve({ status: "ok", code: CODE, expiresInSeconds: 600 });
  await pressed;
  await settle();
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.equal(app.els["pcodes-code"].textContent, "");
  assert.ok(!visible(app, "pcodes-code-block"));
});

test("a countdown left running does not bring a cleared code back", async () => {
  const c = clock();
  const app = await openPairing({}, c.extra);
  await app.els["pcodes-generate"].fire("click");
  await app.els["pcodes-back"].fire("click");
  await c.advance(5);
  assert.equal(app.els["pcodes-code"].textContent, "");
  assert.equal(app.els["pcodes-expiry"].textContent, "");
  assert.ok(!visible(app, "pcodes-expired"));
});

test("select: with a selection API the code is selected and nothing is copied for the user", async () => {
  const selected = [];
  const clipboard = [];
  const answers = {
    saved_agent: SIGNED_IN,
    list_devices: [device],
    generate_pairing_code: { status: "ok", code: CODE, expiresInSeconds: 600 },
  };
  const invoke = (name) => (name in answers ? Promise.resolve(answers[name]) : Promise.reject(`unexpected command ${name}`));
  const app = boot(
    {},
    {
      window: {
        __TAURI__: { core: { invoke } },
        getSelection: () => ({ selectAllChildren: (el) => selected.push(el.id) }),
      },
      navigator: { clipboard: { writeText: (t) => clipboard.push(t) } },
      ...clock().extra,
    }
  );
  await settle();
  await app.els["open-pairing"].fire("click");
  await app.els["pcodes-generate"].fire("click");
  await app.els["pcodes-select"].fire("click");
  assert.deepEqual(selected, ["pcodes-code"]);
  assert.equal(app.els["pcodes-select-result"].textContent, "Selected. Press Ctrl+C to copy.");
  assert.deepEqual(clipboard, [], "the clipboard is never written");
});

test("select: without a selection API it tells the user to select by hand", async () => {
  const app = await openPairing();
  await app.els["pcodes-generate"].fire("click");
  await app.els["pcodes-select"].fire("click");
  assert.match(app.els["pcodes-select-result"].textContent, /Select the code with the mouse/);
});

test("the code is only ever set as text, never as markup", () => {
  const source = readFileSync(new URL("../ui/app.js", import.meta.url), "utf8");
  const block = source.slice(source.indexOf("// ---- feature:pairing-codes ----"));
  assert.ok(block.length > 500, "the feature block was found");
  assert.doesNotMatch(block, /innerHTML|outerHTML|insertAdjacentHTML|document\.write/);
  assert.doesNotMatch(block, /localStorage|sessionStorage|navigator|writeText/, "the code is not stored or copied");
});

test("the screen's own texts and roles are in the page", () => {
  const html = readFileSync(new URL("../ui/index.html", import.meta.url), "utf8");
  assert.match(html, /<p id="pcodes-expired"[^>]*role="status"[^>]*hidden>This pairing code has expired\./);
  assert.match(html, /<p id="pcodes-forbidden"[^>]*role="alert"[^>]*hidden>This login cannot create pairing codes\./);
  assert.match(html, /<p id="pcodes-code"[^>]*role="status"[^>]*aria-labelledby="pcodes-code-label"/);
  assert.match(html, /<h2 id="title-pairing" tabindex="-1">/);
});
