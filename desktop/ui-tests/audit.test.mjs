// The audit and logs screen: states (loaded, empty, forbidden, error), paging, filters, and that
// text from the agent is shown as text, cut to length. Same fake DOM as the other screens.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { boot, settle, focused, SIGNED_IN } from "./harness.mjs";

const html = readFileSync(new URL("../ui/index.html", import.meta.url), "utf8");
const device = { id: "d1", label: "Laptop", created: 1, lastSeen: 0, revoked: false, current: true, lastAddress: "", lastVersion: "", viaLogin: true };
const ago = (s) => new Date(Date.now() - s * 1000).toISOString();
const entry = (id, o = {}) => ({ id, at: ago(id * 10), action: "login", actor: "owner", target: "", detail: "from 10.0.0.2", ...o });
const page = (entries, nextBefore = null) => ({ forbidden: false, entries, nextBefore });

async function open(handlers) {
  const app = boot({ saved_agent: SIGNED_IN, list_devices: [device], ...handlers });
  await settle();
  await app.els["open-audit"].fire("click");
  return app;
}

const rows = (app, body = "audit-body") => app.els[body].children.map((tr) => tr.children.map((td) => td.textContent));
const shown = (app) => !app.els["step-audit"].hidden;

test("the audit log lists events newest first, in local time with the agent's time in the title", async () => {
  const e = [entry(3, { action: "device_revoked", actor: "Desk", target: "dev-1" }), entry(2, { action: "login_failed", actor: "mallory" }), entry(1, { action: "pair", actor: "Phone" })];
  const app = await open({ audit_page: page(e) });
  assert.ok(shown(app));
  assert.equal(focused.at(-1), "title-audit");
  const r = rows(app);
  assert.deepEqual(r.map((x) => x[1]), ["Device revoked", "Failed sign-in", "Device paired"]);
  assert.deepEqual(r.map((x) => x[2]), ["Desk", "mallory", "Phone"]);
  const first = app.els["audit-body"].children[0].children[0];
  assert.equal(first.textContent, new Date(e[0].at).toLocaleString());
  assert.equal(first.attrs.title, e[0].at);
  // A failed sign-in and a revoke stand out; the plain event code is the tooltip.
  assert.ok(app.els["audit-body"].children[1].children[1].classList.contains("revoked"));
  assert.equal(app.els["audit-body"].children[1].children[1].attrs.title, "login_failed");
  assert.match(app.els["audit-count"].textContent, /3 shown of 3 loaded\. That is every event/);
  assert.equal(app.els["audit-more"].hidden, true);
  assert.equal(app.els["audit-forbidden"].hidden, true);
  assert.equal(app.els["audit-empty"].hidden, true);
});

test("text from the agent is shown as text only, without control characters, and cut", async () => {
  const hostile = `<img src=x onerror=alert(1)>‮evil\nline`;
  const long = "x".repeat(500);
  const app = await open({ audit_page: page([entry(1, { actor: hostile, target: long, detail: long, action: "weird\u0007action" })]) });
  const [, event, actor, target, detail] = app.els["audit-body"].children[0].children;
  assert.equal(actor.textContent, "<img src=x onerror=alert(1)> evil line");
  assert.equal(actor.children.length, 0, "no element was made from the text");
  assert.equal(target.textContent.length, 121);
  assert.ok(target.textContent.endsWith("…"));
  assert.equal(detail.textContent.length, 161);
  assert.equal(target.attrs.title.length, 401, "the longer text is in the title, itself cut");
  assert.equal(event.textContent, "weird action");
  // An action this app does not know is listed under its own name in the filter.
  assert.ok(app.els["audit-type"].children.some((o) => o.value === "weird action"));
});

test("Load more continues from the last id, skips repeats, and ends when the page is short", async () => {
  const calls = [];
  const first = Array.from({ length: 3 }, (_, i) => entry(9 - i));
  const app = await open({
    audit_page: (a) => {
      calls.push(a.before);
      if (a.before == null) return page(first, 7);
      if (a.before === 7) return page([entry(7), entry(6), entry(5)], 5); // 7 repeats
      return page([entry(4)], null);
    },
  });
  assert.equal(app.els["audit-more"].hidden, false);
  assert.match(app.els["audit-count"].textContent, /Older events are available/);
  await app.els["audit-more"].fire("click");
  assert.deepEqual(app.els["audit-body"].children.length, 5, "the repeated id is not listed twice");
  await app.els["audit-more"].fire("click");
  assert.deepEqual(calls, [null, 7, 5]);
  assert.equal(app.els["audit-body"].children.length, 6);
  assert.equal(app.els["audit-more"].hidden, true);
  assert.equal(focused.at(-1), "audit-refresh", "focus is not left on a hidden button");
  assert.match(app.els["audit-count"].textContent, /6 shown of 6 loaded\. That is every event/);
  assert.equal(app.els["audit-more"].disabled, false);
});

test("Refresh replaces the list with the newest page", async () => {
  let n = 0;
  const app = await open({ audit_page: () => page(n++ === 0 ? [entry(2), entry(1)] : [entry(5), entry(4), entry(3)]) });
  assert.equal(app.els["audit-body"].children.length, 2);
  await app.els["audit-refresh"].fire("click");
  assert.equal(app.els["audit-body"].children.length, 3);
  assert.equal(app.message(), "");
});

test("a failed refresh keeps the list and says why in an alert", async () => {
  let n = 0;
  const app = await open({
    audit_page: () => (n++ === 0 ? page([entry(1)]) : Promise.reject("cannot reach the agent securely: connection refused.")),
    saved_agent: SIGNED_IN,
  });
  await app.els["audit-refresh"].fire("click");
  assert.equal(app.els["audit-body"].children.length, 1);
  assert.equal(app.els["audit-error"].hidden, false);
  assert.match(app.els["audit-error"].textContent, /cannot reach the agent/);
  assert.match(html, /<p id="audit-error"[^>]*role="alert"/);
  assert.equal(app.els["audit-refresh"].disabled, false);
  await app.els["audit-refresh"].fire("click"); // still failing
  n = 0;
  await app.els["audit-refresh"].fire("click"); // works again: the error is gone
  assert.equal(app.els["audit-error"].hidden, true);
});

test("an error on the first load shows the error and no table rows or empty text", async () => {
  const app = await open({ audit_page: () => Promise.reject("The agent had an internal error. Check its log on the PC.") });
  assert.ok(shown(app));
  assert.equal(app.els["audit-body"].children.length, 0);
  assert.match(app.els["audit-error"].textContent, /internal error/);
  assert.equal(app.els["audit-empty"].hidden, true);
});

test("a login the agent no longer accepts goes back to sign-in with the reason", async () => {
  let signedIn = true;
  const app = boot({
    saved_agent: () => (signedIn ? SIGNED_IN : { host: "pc:8765", fingerprint: "ab".repeat(32), signedIn: false, username: "zaid" }),
    list_devices: [device],
    audit_page: () => {
      signedIn = false;
      return Promise.reject("The agent no longer accepts this login. Sign in again.");
    },
  });
  await settle();
  await app.els["open-audit"].fire("click");
  assert.deepEqual(app.screen(), ["step-login"]);
  assert.match(app.message(), /no longer accepts this login/);
});

test("a login that is not an admin gets the forbidden state: no table, no Load more", async () => {
  const app = await open({ audit_page: { forbidden: true, entries: [], nextBefore: null } });
  assert.ok(shown(app));
  assert.equal(app.els["audit-forbidden"].hidden, false);
  assert.match(app.els["audit-forbidden"].textContent, /This login cannot read the audit log/);
  assert.match(html, /<p id="audit-forbidden"[^>]*role="alert"/);
  assert.equal(app.els["audit-wrap"].hidden, true);
  assert.equal(app.els["audit-more"].hidden, true);
  assert.equal(app.els["audit-empty"].hidden, true);
  assert.equal(app.els["audit-error"].hidden, true);
});

test("an empty audit log says so", async () => {
  const app = await open({ audit_page: page([]) });
  assert.equal(app.els["audit-empty"].hidden, false);
  assert.match(app.els["audit-empty"].textContent, /The audit log is empty/);
  assert.match(app.els["audit-count"].textContent, /0 shown of 0 loaded/);
});

test("the event and time filters narrow what is loaded and say when nothing matches", async () => {
  const e = [
    entry(1, { at: ago(60), action: "login_failed", actor: "a" }),
    entry(2, { at: ago(2 * 3600), action: "pair", actor: "b" }),
    entry(3, { at: ago(3 * 86400), action: "login_failed", actor: "c" }),
    entry(4, { at: ago(30 * 86400), action: "login", actor: "d" }),
  ];
  const app = await open({ audit_page: page(e, 1) });
  const actors = () => rows(app).map((x) => x[2]);
  assert.deepEqual(actors(), ["a", "b", "c", "d"]);

  app.els["audit-type"].value = "login_failed";
  await app.els["audit-type"].fire("change");
  assert.deepEqual(actors(), ["a", "c"]);

  app.els["audit-time"].value = "86400";
  await app.els["audit-time"].fire("change");
  assert.deepEqual(actors(), ["a"]);
  assert.match(app.els["audit-count"].textContent, /1 shown of 4 loaded/);

  app.els["audit-type"].value = "login";
  await app.els["audit-type"].fire("change");
  assert.deepEqual(actors(), []);
  assert.equal(app.els["audit-empty"].hidden, false);
  assert.match(app.els["audit-empty"].textContent, /No loaded event matches these filters\. Press Load more/);
});

test("the agent log: newest first, filtered by text and time, with its own empty and forbidden states", async () => {
  const lines = [
    { ts: ago(30 * 86400), message: "old start" },
    { ts: ago(120), message: "listening on :8765" },
    { ts: ago(60), message: "login failed for mallory" },
  ];
  let reply = { forbidden: false, lines };
  const app = await open({ audit_page: page([entry(1)]), agent_log: () => reply });
  app.els["audit-view"].value = "logs";
  await app.els["audit-view"].fire("change");
  assert.equal(app.els["log-wrap"].hidden, false);
  assert.equal(app.els["audit-wrap"].hidden, true);
  assert.equal(app.els["audit-type-wrap"].hidden, true);
  assert.equal(app.els["audit-text-wrap"].hidden, false);
  assert.equal(app.els["audit-more"].hidden, true);
  assert.deepEqual(rows(app, "log-body").map((x) => x[1]), ["login failed for mallory", "listening on :8765", "old start"]);

  app.els["audit-text"].value = "LISTEN";
  await app.els["audit-text"].fire("input");
  assert.deepEqual(rows(app, "log-body").map((x) => x[1]), ["listening on :8765"]);
  app.els["audit-text"].value = "";
  app.els["audit-time"].value = "3600";
  await app.els["audit-time"].fire("change");
  assert.equal(rows(app, "log-body").length, 2);
  app.els["audit-text"].value = "nothing like this";
  await app.els["audit-text"].fire("input");
  assert.match(app.els["audit-empty"].textContent, /No log line matches these filters/);

  reply = { forbidden: false, lines: [] };
  app.els["audit-text"].value = "";
  app.els["audit-time"].value = "0";
  await app.els["audit-refresh"].fire("click");
  assert.match(app.els["audit-empty"].textContent, /The agent's log is empty/);

  reply = { forbidden: true, lines: [] };
  await app.els["audit-refresh"].fire("click");
  assert.equal(app.els["audit-forbidden"].hidden, false);
  assert.equal(app.els["log-wrap"].hidden, true);

  // Back to the audit log: it was loaded before and is not fetched again.
  const before = app.calls.filter((c) => c === "audit_page").length;
  app.els["audit-view"].value = "audit";
  await app.els["audit-view"].fire("change");
  assert.equal(app.calls.filter((c) => c === "audit_page").length, before);
});

test("log text is cut and shown as text", async () => {
  const app = await open({ audit_page: page([]), agent_log: { forbidden: false, lines: [{ ts: "not a time", message: "<b>hi</b>‮" + "y".repeat(900) }] } });
  app.els["audit-view"].value = "logs";
  await app.els["audit-view"].fire("change");
  const [when, msg] = app.els["log-body"].children[0].children;
  assert.equal(when.textContent, "not a time");
  assert.ok(msg.textContent.startsWith("<b>hi</b> yyy"));
  assert.equal(msg.textContent.length, 401);
  assert.equal(msg.children.length, 0);
});

test("Back returns to the device list and forgets what was read", async () => {
  const app = await open({ audit_page: page([entry(1)]) });
  assert.equal(app.els["audit-body"].children.length, 1);
  await app.els["audit-back"].fire("click");
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.equal(app.els["audit-body"].children.length, 0);
  assert.equal(focused.at(-1), "title-devices");
});

test("a slow answer for the old view does not overwrite the new one", async () => {
  let release;
  const slow = new Promise((r) => (release = r));
  const app = await open({
    audit_page: page([entry(1)]),
    agent_log: () => slow,
  });
  app.els["audit-view"].value = "logs";
  const switching = app.els["audit-view"].fire("change");
  app.els["audit-view"].value = "audit";
  await app.els["audit-view"].fire("change");
  release({ forbidden: false, lines: [{ ts: ago(5), message: "late" }] });
  await switching;
  await settle();
  assert.equal(rows(app, "log-body").length, 0, "the stale log answer was dropped");
  assert.equal(app.els["audit-body"].children.length, 1);
});
