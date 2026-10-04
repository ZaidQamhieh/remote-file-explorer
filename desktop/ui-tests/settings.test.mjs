// The Settings screen, driven against the same fake DOM as states.test.mjs.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, deferred, SIGNED_OUT, SIGNED_IN } from "./harness.mjs";

const INFO = {
  logLevel: "info",
  appVersion: "0.1.0",
  clientVersion: "desktop-0.1.0",
  minAgentForApproval: "agent-v1.43.0-rc.1",
  dataDir: "/home/me/.local/share/app.rfe.desktop",
  platform: "linux",
};
const PIN = { host: "pc:8765", fingerprint: "ab".repeat(32), active: true };

const base = (more = {}) => ({
  saved_agent: SIGNED_OUT,
  list_pins: [],
  app_settings: INFO,
  ...more,
});

test("Settings opens over the connect screen and Back returns to it", async () => {
  const app = boot(base());
  await settle();
  await app.els["open-settings"].fire("click");
  assert.deepEqual(app.screen(), ["step-settings"]);
  await app.els["settings-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-connect"]);
});

test("Settings opened from the trust screen returns to it, with the fingerprint still there", async () => {
  const app = boot(
    base({ probe_agent: { fingerprint: "cd".repeat(32), previous: "", changed: false } })
  );
  await settle();
  await app.els["connect-form"].fire("submit");
  assert.deepEqual(app.screen(), ["step-trust"]);
  await app.els["open-settings"].fire("click");
  assert.deepEqual(app.screen(), ["step-settings"]);
  await app.els["settings-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-trust"]);
  assert.equal(app.els.fingerprint.textContent, "cd".repeat(32));
});

test("account: signed in with an account, paired without one, and not signed in", async () => {
  const app = boot(
    base({
      saved_agent: { ...SIGNED_IN, deviceId: "dev-123" },
      list_devices: [],
    })
  );
  await settle();
  await app.els["open-settings"].fire("click");
  assert.equal(app.els["settings-account"].textContent, "Signed in as zaid on pc:8765.");
  assert.equal(app.els["settings-device"].hidden, false);
  assert.match(app.els["settings-device"].textContent, /dev-123/);

  const paired = boot(
    base({ saved_agent: { ...SIGNED_IN, username: "", deviceId: "d9" }, list_devices: [] })
  );
  await settle();
  await paired.els["open-settings"].fire("click");
  assert.match(paired.els["settings-account"].textContent, /Paired with pc:8765 \(no account/);

  const out = boot(base());
  await settle();
  await out.els["open-settings"].fire("click");
  assert.equal(out.els["settings-account"].textContent, "Not signed in.");
  assert.equal(out.els["settings-device"].hidden, true);
});

test("about shows the versions and where settings are kept, and the level that is saved", async () => {
  const app = boot(base({ app_settings: { ...INFO, logLevel: "debug" } }));
  await settle();
  await app.els["open-settings"].fire("click");
  assert.equal(app.els["about-version"].textContent, "0.1.0");
  assert.equal(app.els["about-client"].textContent, "desktop-0.1.0");
  assert.equal(app.els["about-approval"].textContent, "agent-v1.43.0-rc.1 or newer");
  assert.equal(app.els["about-platform"].textContent, "linux");
  assert.match(app.els["about-data"].textContent, /app\.rfe\.desktop/);
  assert.equal(app.els["log-level"].value, "debug");
});

test("changing the log level saves it; a refusal puts the old level back and says why", async () => {
  let refuse = false;
  const app = boot(
    base({
      set_log_level: (a) =>
        refuse ? Promise.reject("could not write state.json") : Promise.resolve(a.level),
    })
  );
  await settle();
  await app.els["open-settings"].fire("click");
  app.els["log-level"].value = "debug";
  await app.els["log-level"].fire("change");
  assert.ok(app.calls.includes("set_log_level"));
  assert.equal(app.els["log-level"].dataset.saved, "debug");
  assert.equal(app.message(), "");

  refuse = true;
  app.els["log-level"].value = "off";
  await app.els["log-level"].fire("change");
  assert.equal(app.els["log-level"].value, "debug", "back to the saved level");
  assert.match(app.message(), /could not write state\.json/);
});

test("keystore test: success, failure with the reason, and a busy line while it waits", async () => {
  let gate = deferred();
  let mode = "slow";
  const app = boot(
    base({
      check_keystore: () =>
        mode === "slow"
          ? gate.promise
          : Promise.reject("the OS keystore refused access (locked). Unlock it."),
    })
  );
  await settle();
  await app.els["open-settings"].fire("click");
  const pressed = app.els["check-keystore"].fire("click");
  await settle();
  assert.match(app.message(), /Testing the keystore.*unlock/);
  assert.equal(app.els["check-keystore"].disabled, true);
  gate.resolve();
  await pressed;
  await settle();
  assert.match(app.els["keystore-result"].textContent, /^Works/);
  assert.equal(app.message(), "");

  mode = "locked";
  await app.els["check-keystore"].fire("click");
  assert.equal(app.els["keystore-result"].textContent, "Not working.");
  assert.ok(app.els["keystore-result"].classList.contains("revoked"));
  assert.match(app.message(), /refused access/);
  assert.equal(app.els["check-keystore"].disabled, false);
});

test("trusted agents in Settings: listed, and forgetting one refreshes the list in place", async () => {
  let pins = [PIN, { host: "other:1", fingerprint: "ef".repeat(32), active: false }];
  const app = boot(
    base({
      list_pins: () => pins,
      forget_pin: (a) => {
        pins = pins.filter((p) => p.host !== a.host);
        return { wasPinned: true, signedOut: false };
      },
    })
  );
  await settle();
  await app.els["open-settings"].fire("click");
  assert.equal(app.els["settings-pins"].children.length, 2);
  assert.equal(app.els["settings-pins-empty"].hidden, true);

  const forget = app.els["settings-pins"].children[1].children[2].children[0];
  await forget.fire("click"); // arms
  await forget.fire("click"); // confirms
  assert.deepEqual(app.screen(), ["step-settings"], "stays in Settings");
  assert.equal(app.els["settings-pins"].children.length, 1);
});

test("forgetting the agent you are signed in to signs out, and Back does not return to the device list", async () => {
  let pins = [PIN];
  const app = boot({
    saved_agent: { ...SIGNED_IN, deviceId: "d1" },
    list_devices: [],
    app_settings: INFO,
    list_pins: () => pins,
    forget_pin: () => {
      pins = [];
      return { wasPinned: true, signedOut: true };
    },
  });
  await settle();
  assert.deepEqual(app.screen(), ["step-devices"]);
  await app.els["open-settings"].fire("click");
  const forget = app.els["settings-pins"].children[0].children[2].children[0];
  await forget.fire("click");
  await forget.fire("click");
  assert.equal(app.els["settings-account"].textContent, "Not signed in.");
  assert.equal(app.els["settings-pins-empty"].hidden, false);
  await app.els["settings-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-connect"]);
});

test("Settings failing to load shows the reason and stays usable", async () => {
  const app = boot(base({ app_settings: () => Promise.reject("cannot read state.json") }));
  await settle();
  await app.els["open-settings"].fire("click");
  assert.deepEqual(app.screen(), ["step-settings"]);
  assert.match(app.message(), /cannot read state\.json/);
  await app.els["settings-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-connect"]);
});

test("nothing secret is ever written into the Settings screen", async () => {
  const app = boot(
    base({
      saved_agent: { ...SIGNED_IN, deviceId: "d1", token: "tok-secret", password: "pw-secret" },
      list_devices: [],
    })
  );
  await settle();
  await app.els["open-settings"].fire("click");
  const text = Object.values(app.els)
    .map((e) => e.textContent + " " + (e.value || ""))
    .join(" ");
  assert.ok(!text.includes("tok-secret") && !text.includes("pw-secret"), text);
});

test("diagnostics: created on request, shown for reading, and copied", async () => {
  const REPORT = "RFE Desktop diagnostics\napp version: 0.1.0\n";
  const copied = [];
  const app = boot(base({ diagnostics: REPORT }), {
    navigator: { clipboard: { writeText: async (t) => copied.push(t) } },
  });
  await settle();
  await app.els["open-settings"].fire("click");
  assert.equal(app.els.diagnostics.hidden, true, "nothing is built until asked");
  assert.equal(app.els["copy-diagnostics"].hidden, true);

  await app.els["make-diagnostics"].fire("click");
  assert.equal(app.els.diagnostics.hidden, false);
  assert.equal(app.els.diagnostics.value, REPORT);
  assert.equal(app.els["copy-diagnostics"].hidden, false);

  await app.els["copy-diagnostics"].fire("click");
  assert.deepEqual(copied, [REPORT]);
  assert.equal(app.els["diagnostics-result"].textContent, "Copied.");
});

test("diagnostics: with no clipboard access the text is selected and the user is told how to copy", async () => {
  const app = boot(base({ diagnostics: "report" }), {
    navigator: { clipboard: { writeText: () => Promise.reject(new Error("denied")) } },
  });
  await settle();
  await app.els["open-settings"].fire("click");
  await app.els["make-diagnostics"].fire("click");
  await app.els["copy-diagnostics"].fire("click");
  assert.match(app.els["diagnostics-result"].textContent, /Ctrl\+C/);
});

test("diagnostics: a failure shows the reason and leaves no stale report; reopening Settings clears it", async () => {
  let fail = false;
  const app = boot(
    base({ diagnostics: () => (fail ? Promise.reject("cannot build the report") : "old report") })
  );
  await settle();
  await app.els["open-settings"].fire("click");
  await app.els["make-diagnostics"].fire("click");
  assert.equal(app.els.diagnostics.value, "old report");
  await app.els["settings-back"].fire("click");
  await app.els["open-settings"].fire("click");
  assert.equal(app.els.diagnostics.hidden, true, "a report from before is not kept");
  assert.equal(app.els.diagnostics.value, "");

  fail = true;
  await app.els["make-diagnostics"].fire("click");
  assert.match(app.message(), /cannot build the report/);
  assert.equal(app.els.diagnostics.hidden, true);
  assert.equal(app.els["make-diagnostics"].disabled, false);
});
