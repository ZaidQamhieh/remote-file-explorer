// The pairing-request inbox screen: its states (loading, empty, list, forbidden, error), the
// refresh timer that runs only while the screen is open, two-press accept, and rows that stay put.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { boot, settle, focused, SIGNED_IN } from "./harness.mjs";

const req = (o = {}) => ({
  id: "r1",
  label: "Phone A",
  matchCode: "1234 5678",
  address: "192.168.1.5",
  replaces: "",
  ageSeconds: 35,
  expiresInSeconds: 85,
  ...o,
});
const inbox = (requests, o = {}) => ({ forbidden: false, requests, limit: 3, ttlSeconds: 120, ...o });

// A timer the test drives: nothing runs by itself, `tick` runs the one active interval.
function timers() {
  const t = { fns: [], active: null, cleared: 0 };
  return {
    t,
    extra: {
      setInterval: (fn) => {
        t.fns.push(fn);
        t.active = t.fns.length;
        return t.active;
      },
      clearInterval: (id) => {
        t.cleared++;
        if (id === t.active) t.active = null;
      },
    },
    async tick(n = 1) {
      for (let i = 0; i < n; i++) {
        if (t.active) t.fns[t.active - 1]();
        await settle();
      }
    },
  };
}

async function open(handlers) {
  const tm = timers();
  const calls = { list: 0, answers: [] };
  const app = boot(
    {
      saved_agent: SIGNED_IN,
      list_devices: [],
      list_pair_requests: () => {
        calls.list++;
        return typeof handlers.list === "function" ? handlers.list() : handlers.list;
      },
      answer_pair_request: (a) => {
        calls.answers.push(a);
        return typeof handlers.answer === "function" ? handlers.answer(a) : handlers.answer || "done";
      },
      ...(handlers.extra || {}),
    },
    tm.extra
  );
  await settle();
  await app.els["open-pair-inbox"].fire("click");
  const shown = () => !app.els["step-pair-inbox"].hidden;
  const rows = () => app.els["inbox-rows"].children;
  const cells = (row) => row.children.map((c) => c.textContent);
  const buttons = (row) => row.children[5].children[0].children;
  return { app, tm, calls, shown, rows, cells, buttons };
}

test("a request is listed with device, address, age, time left and match code", async () => {
  const p = await open({ list: inbox([req()]) });
  assert.ok(p.shown());
  assert.equal(p.app.els["step-devices"].hidden, true);
  assert.equal(p.rows().length, 1);
  assert.deepEqual(p.cells(p.rows()[0]).slice(0, 5), ["Phone A", "192.168.1.5", "35 s", "1 min 25 s", "1234 5678"]);
  assert.equal(p.app.els["inbox-wrap"].hidden, false);
  assert.equal(p.app.els["inbox-empty"].hidden, true);
  assert.equal(p.app.els["inbox-forbidden"].hidden, true);
  assert.match(p.app.els["inbox-status"].textContent, /1 request waiting/);
  assert.equal(focused.at(-1), "title-pair-inbox");
});

test("what the asking device sends is shown as text, and a takeover is called out", async () => {
  const evil = '<img src=x onerror="alert(1)"> Phone';
  const p = await open({ list: inbox([req({ label: evil, replaces: "Old tablet" })]) });
  const device = p.rows()[0].children[0];
  assert.equal(device.textContent, evil);
  assert.match(device.children[0].textContent, /Takes over the paired device Old tablet.*browse-only/);
  const [accept, reject] = p.buttons(p.rows()[0]);
  assert.equal(accept.attrs["aria-label"], `Accept ${evil}, code 1234 5678`);
  assert.equal(reject.attrs["aria-label"], `Reject ${evil}, code 1234 5678`);
});

test("no requests: the empty message shows and no table", async () => {
  const p = await open({ list: inbox([]) });
  assert.equal(p.app.els["inbox-empty"].hidden, false);
  assert.equal(p.app.els["inbox-wrap"].hidden, true);
  assert.equal(p.app.els["inbox-status"].textContent, "");
});

test("slow agent: loading text first, then the list", async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  const p = await open({ list: () => gate });
  assert.equal(p.app.els["inbox-status"].textContent, "Loading pairing requests...");
  release(inbox([req()]));
  await settle();
  assert.equal(p.rows().length, 1);
  assert.notEqual(p.app.els["inbox-status"].textContent, "Loading pairing requests...");
});

test("three waiting: the limit is explained", async () => {
  const ids = ["a", "b", "c"].map((id) => req({ id, label: id }));
  const p = await open({ list: inbox(ids) });
  assert.equal(p.app.els["inbox-limit"].hidden, false);
  const two = await open({ list: inbox(ids.slice(0, 2)) });
  assert.equal(two.app.els["inbox-limit"].hidden, true);
});

test("a login that is not an account gets the warning, no table, and no polling", async () => {
  const p = await open({ list: inbox([], { forbidden: true }) });
  assert.equal(p.app.els["inbox-forbidden"].hidden, false);
  // The warning's words are fixed in the page, which the harness does not copy into the fake DOM.
  assert.match(readFileSync(new URL("../ui/index.html", import.meta.url), "utf8"), /id="inbox-forbidden"[^>]*>This login cannot answer pairing requests/);
  assert.equal(p.app.els["inbox-wrap"].hidden, true);
  assert.equal(p.app.els["inbox-empty"].hidden, true);
  assert.equal(p.tm.t.active, null, "the timer is stopped");
  const before = p.calls.list;
  await p.tm.tick(9);
  assert.equal(p.calls.list, before);
  // Refresh asks again.
  await p.app.els["inbox-refresh"].fire("click");
  assert.equal(p.calls.list, before + 1);
});

test("the list is asked for again every third second, only while the screen is open", async () => {
  const p = await open({ list: inbox([req()]) });
  assert.equal(p.calls.list, 1);
  await p.tm.tick(2);
  assert.equal(p.calls.list, 1);
  await p.tm.tick(1);
  assert.equal(p.calls.list, 2);
  await p.tm.tick(3);
  assert.equal(p.calls.list, 3);

  await p.app.els["inbox-back"].fire("click");
  assert.deepEqual([p.shown(), p.app.els["step-devices"].hidden], [false, false]);
  assert.equal(p.tm.t.active, null, "leaving stops the timer");
  const after = p.calls.list;
  await p.tm.tick(9);
  assert.equal(p.calls.list, after, "nothing is asked while another screen shows");

  // Opening it again starts over with a fresh list.
  await p.app.els["open-pair-inbox"].fire("click");
  assert.equal(p.calls.list, after + 1);
  assert.ok(p.tm.t.active);
});

test("opening Settings from the inbox stops the timer and Back returns to a fresh list", async () => {
  const p = await open({
    list: inbox([req()]),
    extra: { app_settings: { logLevel: "info", appVersion: "1", clientVersion: "d", minAgentForApproval: "x", dataDir: "/d", platform: "linux" }, list_pins: [] },
  });
  await p.app.els["open-settings"].fire("click");
  assert.equal(p.shown(), false);
  assert.equal(p.tm.t.active, null);
  const before = p.calls.list;
  await p.app.els["settings-back"].fire("click");
  assert.ok(p.shown());
  assert.equal(p.calls.list, before + 1);
  assert.ok(p.tm.t.active);
});

test("the time left counts down each second and an expired row cannot be answered", async () => {
  // Listed with 2 seconds left; no refresh arrives before it runs out.
  const p = await open({ list: inbox([req({ ageSeconds: 118, expiresInSeconds: 2 })]) });
  const row = p.rows()[0];
  assert.equal(p.cells(row)[3], "2 s");
  await p.tm.tick(1);
  assert.equal(p.cells(row)[3], "1 s");
  await p.tm.tick(1);
  assert.equal(p.cells(row)[3], "expired");
  assert.deepEqual(p.buttons(row).map((b) => b.disabled), [true, true]);
});

test("a request that is no longer listed leaves the table and the others stay as they were", async () => {
  let list = inbox([req({ id: "a", label: "A" }), req({ id: "b", label: "B" })]);
  const p = await open({ list: () => list });
  const [rowA, rowB] = p.rows();
  const [acceptB] = p.buttons(rowB);
  list = inbox([req({ id: "b", label: "B", ageSeconds: 40, expiresInSeconds: 80 })]);
  await p.tm.tick(3);
  assert.equal(p.rows().length, 1);
  assert.equal(p.rows()[0], rowB, "the same row object, not a rebuilt copy");
  assert.equal(p.buttons(rowB)[0], acceptB, "so a focused button is not replaced");
  assert.equal(p.cells(rowB)[2], "40 s");
  assert.notEqual(p.rows()[0], rowA);
  // A new request is added after the existing ones.
  list = inbox([req({ id: "b", label: "B" }), req({ id: "c", label: "C" })]);
  await p.tm.tick(3);
  assert.deepEqual(p.rows().map((r) => r.children[0].textContent), ["B", "C"]);
  assert.equal(p.rows()[0], rowB);
});

test("accept takes two presses, then answers that request and shows the result", async () => {
  let list = inbox([req({ id: "r1", label: "Phone A" }), req({ id: "r2", label: "Phone B", matchCode: "8765 4321" })]);
  const p = await open({
    list: () => list,
    answer: () => {
      list = inbox([req({ id: "r2", label: "Phone B", matchCode: "8765 4321" })]);
      return "done";
    },
  });
  const [accept] = p.buttons(p.rows()[0]);
  assert.equal(accept.textContent, "Accept");
  await accept.fire("click");
  assert.deepEqual(p.calls.answers, [], "the first press only arms the button");
  assert.equal(accept.textContent, "Press again to accept");
  assert.match(accept.attrs["aria-label"], /Press again to accept Phone A, code 1234 5678/);

  await accept.fire("click");
  assert.deepEqual(JSON.parse(JSON.stringify(p.calls.answers)), [{ id: "r1", approve: true }]);
  assert.equal(p.rows().length, 1);
  assert.equal(p.rows()[0].children[0].textContent, "Phone B");
  assert.equal(p.app.message(), "Accepted Phone A.");
  assert.equal(p.app.els.message.classList.contains("error"), false);
  assert.equal(focused.at(-1), "title-pair-inbox");
});

test("an armed accept disarms by itself", async () => {
  const p = await open({ list: inbox([req()]) });
  const [accept] = p.buttons(p.rows()[0]);
  await accept.fire("click");
  assert.equal(accept.textContent, "Press again to accept");
  await p.tm.tick(8);
  assert.equal(accept.textContent, "Accept");
  await accept.fire("click");
  assert.deepEqual(p.calls.answers, [], "a press after it disarmed arms it again, it does not accept");
});

test("reject is one press and answers the request it belongs to", async () => {
  let list = inbox([req({ id: "r1", label: "Phone A" }), req({ id: "r2", label: "Phone B" })]);
  const p = await open({
    list: () => list,
    answer: (a) => {
      list = inbox(list.requests.filter((r) => r.id !== a.id));
      return "done";
    },
  });
  const [, reject] = p.buttons(p.rows()[1]);
  await reject.fire("click");
  assert.deepEqual(JSON.parse(JSON.stringify(p.calls.answers)), [{ id: "r2", approve: false }]);
  assert.deepEqual(p.rows().map((r) => r.children[0].textContent), ["Phone A"]);
  assert.equal(p.app.message(), "Rejected Phone B.");
});

test("answering a request that is already gone says so and is not an error", async () => {
  let list = inbox([req()]);
  const p = await open({
    list: () => list,
    answer: () => {
      list = inbox([]);
      return "gone";
    },
  });
  const [, reject] = p.buttons(p.rows()[0]);
  await reject.fire("click");
  assert.equal(p.app.message(), "That request already expired or was answered on the PC.");
  assert.equal(p.app.els.message.classList.contains("error"), false);
  assert.equal(p.rows().length, 0);
  assert.equal(p.app.els["inbox-empty"].hidden, false);
});

test("answering fails: the error shows, the row stays and its buttons work again", async () => {
  const p = await open({
    list: inbox([req()]),
    answer: () => Promise.reject("cannot reach the agent securely: timed out"),
  });
  const [, reject] = p.buttons(p.rows()[0]);
  await reject.fire("click");
  assert.match(p.app.message(), /cannot reach the agent/);
  assert.ok(p.app.els.message.classList.contains("error"));
  assert.equal(p.rows().length, 1);
  assert.deepEqual(p.buttons(p.rows()[0]).map((b) => b.disabled), [false, false]);
});

test("a refresh that fails shows the error and keeps the list; the next good one clears it", async () => {
  let fail = false;
  const p = await open({ list: () => (fail ? Promise.reject("cannot reach the agent securely: timed out") : inbox([req()])) });
  fail = true;
  await p.tm.tick(3);
  assert.match(p.app.message(), /cannot reach the agent/);
  assert.ok(p.app.els.message.classList.contains("error"));
  assert.equal(p.rows().length, 1);
  fail = false;
  await p.tm.tick(3);
  assert.equal(p.app.message(), "");
});

test("the agent refused the saved login: back to sign-in with the reason", async () => {
  let n = 0;
  const tm = timers();
  const app = boot(
    {
      saved_agent: () => (n++ === 0 ? SIGNED_IN : { host: "pc:8765", fingerprint: "ab".repeat(32), signedIn: false, username: "zaid" }),
      list_devices: [],
      list_pair_requests: () => Promise.reject("The agent no longer accepts this login. Sign in again."),
    },
    tm.extra
  );
  await settle();
  await app.els["open-pair-inbox"].fire("click");
  assert.deepEqual(["step-login"].filter((s) => !app.els[s].hidden), ["step-login"]);
  assert.equal(app.els["step-pair-inbox"].hidden, true);
  assert.match(app.message(), /no longer accepts this login/);
  assert.equal(tm.t.active, null);
});

test("the inbox markup: a labelled table, a focusable heading, buttons with names", async () => {
  const html = readFileSync(new URL("../ui/index.html", import.meta.url), "utf8");
  assert.match(html, /<section id="step-pair-inbox"/);
  assert.match(html, /<h2 id="title-pair-inbox" tabindex="-1">/);
  const section = html.slice(html.indexOf('<section id="step-pair-inbox"'), html.indexOf("</section>", html.indexOf('<section id="step-pair-inbox"')));
  for (const m of section.matchAll(/<th\b([^>]*)>/g)) assert.match(m[1], /scope="col"/);
  assert.match(section, /<span class="sr-only">Actions<\/span>/);
});
