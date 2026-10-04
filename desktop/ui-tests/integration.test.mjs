// Checks that only matter once the features share one window: pollers that must restart when their
// screen comes back.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, SIGNED_IN } from "./harness.mjs";

const RUNNING = { id: "t1", direction: "download", state: "running", name: "a.bin", remotePath: "/r/a.bin", localPath: "", done: 1, total: 10, error: "", verified: false };
const INFO = { version: "0.1.0", platform: "linux", dataDir: "/d", logLevel: "info", logPath: "/l", keystore: "x" };

// A running transfer keeps the polling loop alive; hiding the screen ends it.
const apps = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.els["step-transfers"].hidden = true;
});

const start = async (extra = {}) => {
  const app = boot({
    saved_agent: SIGNED_IN,
    list_devices: [],
    list_pins: [],
    app_settings: INFO,
    transfer_folder: "/home/me/Downloads/RFE Desktop",
    transfer_list: [RUNNING],
    transfer_download: "t1",
    ...extra,
  });
  apps.push(app);
  await settle();
  return app;
};
const polls = (app) => app.calls.filter((c) => c === "transfer_list").length;

test("progress resumes when the user comes back to Transfers from Settings", async () => {
  const app = await start();
  await app.els["open-transfers"].fire("click");
  await settle();
  await app.els["open-settings"].fire("click");
  await settle();
  const before = polls(app);
  await app.els["settings-back"].fire("click");
  await new Promise((r) => setTimeout(r, 700));
  assert.ok(polls(app) > before, "polling restarted after Back");
});
