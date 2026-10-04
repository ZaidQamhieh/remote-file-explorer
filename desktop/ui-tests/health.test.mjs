// The health and metrics screen: what it shows for a full answer, a reduced one, a non-admin
// session and an agent that cannot be reached, and that auto-refresh runs only while the screen is
// open, never overlaps itself and stops on an error. Drives desktop/ui/app.js against a fake DOM.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { boot, settle, deferred, focused, SIGNED_IN, SIGNED_OUT } from "./harness.mjs";

const snap = (o = {}) => ({
  host: "pc:8765",
  fingerprint: "ab".repeat(32),
  health: { status: "ok", name: "office-pc", version: "1.43.0", os: "linux", readOnly: false, address: "192.168.1.20:8765", tailscaleAddress: "", macAddress: "" },
  status: { version: "1.43.0", uptimeSeconds: 93784, platform: "linux/amd64", freeBytes: 5 * 1024 ** 3, totalBytes: 100 * 1024 ** 3 },
  statusNote: "",
  metrics: { rxBytes: 1536, txBytes: 0, cpuPercent: 12.34, ramPercent: 50, tsMs: 1_700_000_000_000 },
  metricsForbidden: false,
  metricsNote: "",
  ...o,
});

// Timers the page asks for are held here and run by the test, so the five seconds cost nothing.
function bootHealth(handlers) {
  const timers = [];
  const app = boot(
    { saved_agent: SIGNED_IN, list_devices: [], app_settings: { logLevel: "info", appVersion: "0", clientVersion: "x", minAgentForApproval: "y", dataDir: "/d", platform: "linux" }, list_pins: [], ...handlers },
    { setTimeout: (fn, ms) => timers.push({ fn, ms }) }
  );
  const runTimer = async () => {
    const t = timers.shift();
    assert.ok(t, "no timer is waiting");
    await t.fn();
    await settle();
  };
  return { app, timers, runTimer, count: () => app.calls.filter((c) => c === "agent_health").length };
}

async function openHealth(h) {
  await settle();
  await h.app.els["open-health"].fire("click");
}

const text = (h, id) => h.app.els[id].textContent;
const visible = (h, id) => !h.app.els[id].hidden;

test("a full answer: every field with its unit, the agent's address and fingerprint, last-updated time", async () => {
  const h = bootHealth({ agent_health: snap() });
  await settle();
  focused.length = 0;
  await h.app.els["open-health"].fire("click");

  assert.equal(visible(h, "step-health"), true);
  assert.equal(visible(h, "step-devices"), false);
  assert.equal(focused.includes("title-health"), true, "focus moves to the new screen's heading");
  assert.equal(text(h, "health-host"), "pc:8765");
  assert.equal(text(h, "health-fingerprint"), "ab".repeat(32));
  assert.equal(text(h, "health-name"), "office-pc");
  assert.equal(text(h, "health-version"), "1.43.0");
  assert.equal(text(h, "health-os"), "linux");
  assert.match(text(h, "health-readonly"), /^No/);
  assert.equal(text(h, "health-address"), "192.168.1.20:8765");
  assert.equal(text(h, "health-tailscale"), "not reported");
  assert.equal(text(h, "health-status"), "Running (ok)");
  assert.equal(text(h, "health-uptime"), "1 d 2 h 3 min");
  assert.equal(text(h, "health-disk"), "5.0 GiB of 100 GiB");
  assert.equal(text(h, "health-cpu"), "12.3 %");
  assert.equal(text(h, "health-ram"), "50.0 %");
  assert.match(text(h, "health-rx"), /^1\.5 KiB \(1.?536 bytes\)$/);
  assert.equal(text(h, "health-tx"), "0 B");
  assert.equal(text(h, "health-rx-rate"), "Needs a second reading");
  assert.notEqual(text(h, "health-agent-time"), "");
  assert.match(text(h, "health-updated"), /^Last updated .+\.$/);
  assert.equal(visible(h, "health-forbidden"), false);
  assert.equal(visible(h, "health-metrics"), true);
  assert.equal(h.app.message(), "");
});

test("an answer without optional fields shows 'not reported', never a made-up zero", async () => {
  const h = bootHealth({
    agent_health: snap({
      health: { status: "ok", name: "", version: "", os: "", readOnly: null, address: "", tailscaleAddress: "", macAddress: "" },
      status: { version: "", uptimeSeconds: null, platform: "", freeBytes: null, totalBytes: null },
      metrics: { rxBytes: null, txBytes: null, cpuPercent: null, ramPercent: null, tsMs: null },
    }),
  });
  await openHealth(h);
  for (const id of ["health-name", "health-version", "health-os", "health-readonly", "health-address", "health-mac", "health-uptime", "health-disk", "health-cpu", "health-ram", "health-rx", "health-tx", "health-rx-rate", "health-agent-time"]) {
    assert.equal(text(h, id), "not reported", id);
  }
  assert.equal(h.app.message(), "");
});

test("a non-admin session: a clear 403 state for the metrics, the health still shown", async () => {
  const h = bootHealth({ agent_health: snap({ metrics: null, metricsForbidden: true }) });
  await openHealth(h);
  assert.equal(visible(h, "health-forbidden"), true);
  assert.match(text(h, "health-forbidden"), /^Metrics are for administrators\./);
  assert.match(text(h, "health-forbidden"), /403/);
  assert.equal(visible(h, "health-metrics"), false);
  assert.equal(visible(h, "health-metrics-note"), false);
  assert.equal(text(h, "health-name"), "office-pc");
  assert.equal(text(h, "health-uptime"), "1 d 2 h 3 min");
  assert.equal(h.app.message(), "", "a 403 is a state of the screen, not an error banner");
});

test("metrics that failed for another reason say so, with the reason", async () => {
  const h = bootHealth({ agent_health: snap({ metrics: null, metricsNote: "The agent did not answer within 5 seconds. It may be asleep." }) });
  await openHealth(h);
  assert.match(text(h, "health-metrics-note"), /^No metrics were reported\. The agent did not answer within 5 seconds/);
  assert.equal(visible(h, "health-forbidden"), false);
  assert.equal(visible(h, "health-metrics"), false);
});

test("the status request failing leaves the rest and says why", async () => {
  const h = bootHealth({ agent_health: snap({ status: null, statusNote: "cannot reach the agent securely: reset" }) });
  await openHealth(h);
  assert.match(text(h, "health-status-note"), /^Uptime and disk space could not be read: cannot reach/);
  assert.equal(text(h, "health-uptime"), "not reported");
  assert.equal(text(h, "health-name"), "office-pc");
});

test("an agent that cannot be reached: the error is an alert, the screen stays, the button is usable", async () => {
  const h = bootHealth({ agent_health: () => Promise.reject("The agent did not answer within 5 seconds. It may be asleep, busy or on another network.") });
  await openHealth(h);
  assert.equal(visible(h, "step-health"), true);
  assert.match(h.app.message(), /did not answer within 5 seconds/);
  assert.equal(h.app.els.message.attrs.role, "alert");
  assert.equal(h.app.els["open-health"].disabled, false);
  assert.equal(h.app.els["health-refresh"].disabled, false);
  assert.equal(text(h, "health-updated"), "Not read yet.");
});

test("a refresh that fails keeps the numbers already on screen", async () => {
  let fail = false;
  const h = bootHealth({ agent_health: () => (fail ? Promise.reject("cannot reach the agent securely: timed out") : snap()) });
  await openHealth(h);
  const was = text(h, "health-updated");
  fail = true;
  await h.app.els["health-refresh"].fire("click");
  assert.match(h.app.message(), /cannot reach the agent/);
  assert.equal(text(h, "health-cpu"), "12.3 %");
  assert.equal(text(h, "health-updated"), was);
  assert.equal(h.app.els["health-refresh"].disabled, false);
});

test("slow agent: busy text while waiting, and a second press does not start a second request", async () => {
  const gate = deferred();
  const h = bootHealth({ agent_health: () => gate.promise });
  await settle();
  const opened = h.app.els["open-health"].fire("click");
  await settle();
  assert.match(h.app.message(), /Reading the agent's health/);
  await h.app.els["health-refresh"].fire("click");
  assert.equal(h.count(), 1, "one request in flight at a time");
  gate.resolve(snap());
  await opened;
  await settle();
  assert.equal(h.app.message(), "");
  assert.equal(text(h, "health-name"), "office-pc");
});

test("the rate is the growth between two readings over the agent's own clock", async () => {
  const readings = [
    snap({ metrics: { rxBytes: 1000, txBytes: 5000, cpuPercent: 1, ramPercent: 1, tsMs: 1_000_000 } }),
    snap({ metrics: { rxBytes: 1000 + 2048, txBytes: 5000, cpuPercent: 1, ramPercent: 1, tsMs: 1_002_000 } }),
    snap({ metrics: { rxBytes: 10, txBytes: 10, cpuPercent: 1, ramPercent: 1, tsMs: 1_004_000 } }),
  ];
  const h = bootHealth({ agent_health: () => readings.shift() });
  await openHealth(h);
  assert.equal(text(h, "health-rx-rate"), "Needs a second reading");
  await h.app.els["health-refresh"].fire("click");
  assert.equal(text(h, "health-rx-rate"), "1.0 KiB/s");
  assert.equal(text(h, "health-tx-rate"), "0 B/s");
  await h.app.els["health-refresh"].fire("click");
  assert.match(text(h, "health-rx-rate"), /^Counters were reset \(the agent restarted\)/);
});

test("auto-refresh: every five seconds while open, one request at a time, off by default", async () => {
  const h = bootHealth({ agent_health: snap() });
  await openHealth(h);
  assert.equal(h.app.els["health-auto"].checked, false);
  assert.equal(h.timers.length, 0, "nothing is scheduled until it is turned on");

  h.app.els["health-auto"].checked = true;
  await h.app.els["health-auto"].fire("change");
  assert.deepEqual(h.timers.map((t) => t.ms), [5000]);
  assert.equal(h.count(), 1);

  await h.runTimer();
  assert.equal(h.count(), 2);
  assert.deepEqual(h.timers.map((t) => t.ms), [5000], "the next one is scheduled after this one ended");
  await h.runTimer();
  assert.equal(h.count(), 3);
});

test("auto-refresh stops by itself when the screen is left", async () => {
  const h = bootHealth({ agent_health: snap() });
  await openHealth(h);
  h.app.els["health-auto"].checked = true;
  await h.app.els["health-auto"].fire("change");
  await h.app.els["health-back"].fire("click");
  assert.equal(visible(h, "step-devices"), true);

  await h.runTimer();
  assert.equal(h.count(), 1, "no request after leaving");
  assert.equal(h.timers.length, 0, "and no further timer");
});

test("auto-refresh pauses behind Settings and picks up again on Back", async () => {
  const h = bootHealth({ agent_health: snap() });
  await openHealth(h);
  h.app.els["health-auto"].checked = true;
  await h.app.els["health-auto"].fire("change");
  await h.app.els["open-settings"].fire("click");
  assert.equal(visible(h, "step-health"), false);

  await h.runTimer();
  assert.equal(h.count(), 1, "nothing is asked while Settings covers the screen");
  assert.equal(h.timers.length, 0);

  await h.app.els["settings-back"].fire("click");
  assert.equal(visible(h, "step-health"), true);
  assert.deepEqual(h.timers.map((t) => t.ms), [5000]);
  await h.runTimer();
  assert.equal(h.count(), 2);
});

test("an error during auto-refresh turns it off and says so, instead of asking every five seconds", async () => {
  let n = 0;
  const h = bootHealth({ agent_health: () => (n++ === 0 ? snap() : Promise.reject("cannot reach the agent securely: refused")) });
  await openHealth(h);
  h.app.els["health-auto"].checked = true;
  await h.app.els["health-auto"].fire("change");
  await h.runTimer();

  assert.equal(h.app.els["health-auto"].checked, false);
  assert.equal(visible(h, "health-auto-note"), true);
  assert.match(text(h, "health-auto-note"), /^Auto-refresh stopped after an error\./);
  assert.match(h.app.message(), /cannot reach the agent/);
  assert.equal(h.timers.length, 0);
  assert.equal(text(h, "health-cpu"), "12.3 %", "the last good numbers stay");
});

test("turning auto-refresh off cancels the pending refresh", async () => {
  const h = bootHealth({ agent_health: snap() });
  await openHealth(h);
  h.app.els["health-auto"].checked = true;
  await h.app.els["health-auto"].fire("change");
  h.app.els["health-auto"].checked = false;
  await h.app.els["health-auto"].fire("change");
  await h.runTimer();
  assert.equal(h.count(), 1);
  assert.equal(h.timers.length, 0);
});

test("the agent refused the saved login: back to sign-in on that agent, auto-refresh over", async () => {
  let n = 0;
  const h = bootHealth({
    saved_agent: () => (n++ === 0 ? SIGNED_IN : { ...SIGNED_OUT, fingerprint: "ab".repeat(32), username: "zaid" }),
    agent_health: () => Promise.reject("The agent no longer accepts this login. Sign in again."),
  });
  await openHealth(h);
  assert.deepEqual(h.app.screen(), ["step-login"]);
  assert.equal(visible(h, "step-health"), false);
  assert.match(h.app.message(), /no longer accepts this login/);
  assert.equal(h.app.els.username.value, "zaid");
});

test("text from the agent is shown as text, not as markup", async () => {
  const h = bootHealth({ agent_health: snap({ health: { status: "ok", name: "<img src=x onerror=alert(1)>", version: "1", os: "linux", readOnly: true, address: "", tailscaleAddress: "", macAddress: "" } }) });
  await openHealth(h);
  assert.equal(text(h, "health-name"), "<img src=x onerror=alert(1)>");
  const source = readFileSync(new URL("../ui/app.js", import.meta.url), "utf8");
  const mine = source.slice(source.indexOf("// ---- feature:health-metrics ----"));
  assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML|document\.write/.test(mine));
});
