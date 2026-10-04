// What a screen reader is given: the app's AT-SPI tree, read from the accessibility bus of the
// private session. Not Orca itself (it is not installed here): this is the data Orca speaks from.
// Skips when the accessibility bus is not available.
//
//   desktop/e2e/run.sh

import { test, after } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { App, Agent, waitFor, resetAppState } from "./lib.mjs";

const dump = join(dirname(fileURLToPath(import.meta.url)), "atspi-dump.py");
const BUTTON = "button";
let app;
let agent;
after(async () => {
  if (app) await app.end();
  agent?.stop();
});

function tree() {
  const out = execFileSync("python3", [dump, "rfe"], { encoding: "utf8", timeout: 30000 });
  return out
    .split("\n")
    .filter(Boolean)
    .map((l) => {
      const [depth, role, showing, ...name] = l.split("\t");
      return { depth: Number(depth), role, showing: showing === "1", name: name.join("\t") };
    });
}

test("the screens expose headings, labelled fields, buttons and tables to assistive technology", async (t) => {
  agent = await Agent.start();
  resetAppState();
  app = await App.start();
  let nodes;
  try {
    nodes = await (async () => {
      let last;
      for (let i = 0; i < 20; i++) {
        try {
          const n = tree();
          if (n.length > 5) return n;
        } catch (e) {
          last = e;
        }
        await new Promise((r) => setTimeout(r, 500));
      }
      throw last || new Error("empty tree");
    })();
  } catch (e) {
    t.skip(`no accessibility bus: ${String(e.message).split("\n")[0]}`);
    return;
  }
  const shown = nodes.filter((n) => n.showing);
  const named = (role, re) => shown.some((n) => n.role === role && re.test(n.name));
  writeFileSync(join(process.env.E2E_APP_DATA, "..", "atspi-connect.txt"), nodes.map((n) => `${"  ".repeat(n.depth)}${n.role}: ${n.name}`).join("\n"));
  const dumpOf = (list) => list.map((n) => `${"  ".repeat(n.depth)}${n.role}: ${n.name}`).join("\n");
  assert.ok(named("heading", /Connect to an agent/), "the screen's heading is a heading\n" + dumpOf(shown));
  assert.ok(named("label", /Agent address/) || named("entry", /Agent address/), "the address field has its label\n" + dumpOf(shown));
  assert.ok(named(BUTTON, /Check certificate/), "the submit button has a name\n" + dumpOf(shown));

  try {
    // Sign in and read the device table.
    await app.fill("#host", agent.host);
    await app.click('#connect-form button[type="submit"]');
    await waitFor("the trust step", () => app.visible("#step-trust"));
    await app.click("#trust");
    await waitFor("the sign-in step", () => app.visible("#step-login"));
    await app.fill("#username", agent.user);
    await app.fill("#password", agent.password);
    await app.click('#login-form button[type="submit"]');
    await waitFor("the device list", () => app.visible("#step-devices"));
    await waitFor("a row", async () => (await app.rows("#devices tr")) >= 1);
    const devices = tree().filter((n) => n.showing);
    assert.ok(devices.some((n) => n.role === "heading" && /Paired devices/.test(n.name)), "devices heading");
    assert.ok(devices.some((n) => n.role === "table"), "the device list is a table");
    // The cells' text is not in the tree as nodes (WebKit gives it to the parent), so this checks the
    // structure a screen reader announces ("table, 6 columns, column header"), not the words.
    assert.equal(devices.filter((n) => /column header/.test(n.role)).length, 6, "six column headers\n" + dumpOf(devices));
    assert.equal(devices.filter((n) => n.role === "table cell").length, 6, "a row of six cells\n" + dumpOf(devices));
    const buttons = devices.filter((n) => n.role === BUTTON).map((n) => n.name);
    for (const want of [/Revoke RFE Desktop/, /Remove RFE Desktop/]) {
      assert.ok(buttons.some((b) => want.test(b)), `a button named ${want}: ${buttons.join(" | ")}`);
    }
    writeFileSync(join(process.env.E2E_APP_DATA, "..", "atspi-devices.txt"), devices.map((n) => `${"  ".repeat(n.depth)}${n.role}: ${n.name}`).join("\n"));
  } finally {
    // Leave nothing signed in for the files that run after this one.
    if (await app.visible("#sign-out").catch(() => false)) await app.click("#sign-out").catch(() => {});
    await waitFor("signed out", () => app.visible("#step-connect")).catch(() => {});
  }
});
