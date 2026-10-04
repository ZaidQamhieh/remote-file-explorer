// Accessibility that can be checked without a screen reader: every control has a name, headings
// and tables are marked up, focus follows the screen, errors are announced. Orca and a real
// keyboard-only run are not covered; see docs/accessibility.md.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { boot, settle, focused, SIGNED_OUT, SIGNED_IN } from "./harness.mjs";

const html = readFileSync(new URL("../ui/index.html", import.meta.url), "utf8");
const tags = (name) => [...html.matchAll(new RegExp(`<${name}\\b([^>]*)>([\\s\\S]*?)</${name}>`, "g"))];
const attr = (attrs, name) => (attrs.match(new RegExp(`\\b${name}="([^"]*)"`)) || [])[1];

test("the page declares its language and ids are unique", () => {
  assert.match(html, /<html lang="en">/);
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
  assert.equal(new Set(ids).size, ids.length, "duplicate ids");
});

test("every field has a label or an aria-label", () => {
  const labelled = new Set(tags("label").map((m) => attr(m[1], "for")));
  for (const tag of ["input", "select", "textarea"]) {
    const re = tag === "input" ? /<input\b([^>]*)>/g : new RegExp(`<${tag}\\b([^>]*)>`, "g");
    for (const m of html.matchAll(re)) {
      const id = attr(m[1], "id");
      assert.ok(labelled.has(id) || attr(m[1], "aria-label"), `${tag}#${id} has no label`);
    }
  }
});

test("every button has visible text or an aria-label, and is a type=button or submit", () => {
  for (const m of tags("button")) {
    const text = m[2].replace(/<[^>]*>/g, "").trim();
    assert.ok(text || attr(m[1], "aria-label"), `button ${attr(m[1], "id")} has no name`);
    assert.match(attr(m[1], "type") || "", /^(button|submit)$/, `button ${attr(m[1], "id")} has no type`);
  }
});

test("nothing steals the tab order", () => {
  for (const m of html.matchAll(/tabindex="(-?\d+)"/g)) {
    assert.ok(Number(m[1]) <= 0, `tabindex ${m[1]} reorders the tab sequence`);
  }
});

test("table columns are headers with a scope, and an empty header has a hidden name", () => {
  for (const m of tags("th")) {
    assert.equal(attr(m[1], "scope"), "col");
    const inner = m[2].replace(/<[^>]*>/g, "").trim();
    assert.ok(inner.length > 0, "an empty column header");
  }
});

test("every screen has a heading that can take focus", () => {
  for (const m of html.matchAll(/<section id="step-([a-z]+)"/g)) {
    assert.match(html, new RegExp(`<h2 id="title-${m[1]}" tabindex="-1">`), `step-${m[1]}`);
  }
});

test("focus moves to the new screen's heading when the screen changes", async () => {
  const app = boot({
    saved_agent: SIGNED_OUT,
    list_pins: [],
    probe_agent: { fingerprint: "cd".repeat(32), previous: "", changed: false },
  });
  await settle();
  focused.length = 0;
  await app.els["connect-form"].fire("submit");
  assert.deepEqual(app.screen(), ["step-trust"]);
  assert.equal(focused.at(-1), "title-trust");
  await app.els["trust-cancel"].fire("click");
  assert.equal(focused.at(-1), "title-connect");
});

test("an error is announced as an alert and a progress line as a status", async () => {
  const app = boot({
    saved_agent: SIGNED_OUT,
    list_pins: [],
    probe_agent: () => Promise.reject("cannot reach the agent securely"),
  });
  await settle();
  await app.els["connect-form"].fire("submit");
  assert.equal(app.els.message.attrs.role, "alert");
  assert.match(app.message(), /cannot reach/);

  const ok = boot({ saved_agent: SIGNED_IN, list_devices: [] });
  await settle();
  assert.equal(ok.els.message.attrs.role, "status");
});

test("buttons made on the fly say which row they act on", async () => {
  const app = boot({
    saved_agent: SIGNED_OUT,
    list_pins: [{ host: "pc:8765", fingerprint: "ab".repeat(32), active: false }],
    discover_agents: [{ name: "office", hostport: "10.0.0.2:8765", otherAddresses: [], version: "1", known: false }],
  });
  await settle();
  const forget = app.els.pins.children[0].children[2].children[0];
  assert.equal(forget.attrs["aria-label"], "Forget pc:8765");
  await forget.fire("click");
  assert.match(forget.attrs["aria-label"], /Forget\? pc:8765.*again/);

  await app.els.discover.fire("click");
  const use = app.els.found.children[0].children[3].children[0];
  assert.equal(use.attrs["aria-label"], "Use 10.0.0.2:8765 (office)");
});
