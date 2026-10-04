// The Transfers screen: what it shows for each state, that its controls reach the right commands,
// and the `window.rfeTransfers` hooks for the file browser. Drives desktop/ui/app.js against the
// fake DOM with `invoke` answered by the test.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { boot, settle, focused, SIGNED_IN } from "./harness.mjs";

const plain = (x) => JSON.parse(JSON.stringify(x));
const html = readFileSync(new URL("../ui/index.html", import.meta.url), "utf8");

const t = (o = {}) => ({
  id: "t1",
  direction: "download",
  state: "running",
  name: "report.pdf",
  remotePath: "/srv/report.pdf",
  localPath: "",
  done: 512,
  total: 1024,
  error: "",
  verified: false,
  ...o,
});

// A transfer that stays "running" keeps the screen's polling loop going; hiding the screen ends it.
const opened = [];
afterEach(() => {
  for (const app of opened.splice(0)) app.els["step-transfers"].hidden = true;
});

async function open(list, extra = {}) {
  const calls = [];
  const app = boot({
    saved_agent: SIGNED_IN,
    list_devices: [],
    transfer_folder: "/home/zaid/Downloads/RFE Desktop",
    transfer_list: () => (typeof list === "function" ? list() : list),
    ...Object.fromEntries(
      ["transfer_download", "transfer_upload", "transfer_cancel", "transfer_retry", "transfer_clear_finished"].map((n) => [
        n,
        (args) => {
          calls.push([n, args]);
          return extra[n] ? extra[n](args) : n === "transfer_download" || n === "transfer_upload" ? "t9" : undefined;
        },
      ])
    ),
  });
  opened.push(app);
  await settle();
  await app.els["open-transfers"].fire("click");
  return { app, calls };
}

const row = (app, i = 0) => {
  const li = app.els["transfer-list"].children[i];
  const [name, status, bar, actions] = li.children;
  return { li, name, status, bar, cancel: actions.children[0], retry: actions.children[1] };
};

test("the screen has a labelled heading, labelled fields and a list", () => {
  assert.match(html, /<h2 id="title-transfers" tabindex="-1">/);
  for (const id of ["download-path", "upload-path", "upload-dir"]) {
    assert.match(html, new RegExp(`<label for="${id}">`), id);
  }
  assert.match(html, /<ul id="transfer-list"[^>]*aria-label="Transfers"/);
});

test("opening it shows the folder, focuses the heading and lists the transfers", async () => {
  const { app } = await open([t(), t({ id: "t2", direction: "upload", name: "up.bin", state: "done", done: 10, total: 10, verified: true })]);
  assert.equal(app.els["step-transfers"].hidden, false);
  assert.equal(focused.at(-1), "title-transfers");
  assert.equal(app.els["transfers-folder"].textContent, "/home/zaid/Downloads/RFE Desktop");
  assert.equal(app.els["transfer-list"].children.length, 2);
  assert.equal(app.els["transfers-empty"].hidden, true);
});

test("each row has a labelled progress bar with its value", async () => {
  const { app } = await open([t()]);
  const r = row(app);
  assert.equal(r.bar.attrs.role, "progressbar");
  assert.equal(r.bar.attrs["aria-label"], "Downloading report.pdf");
  assert.equal(r.bar.attrs["aria-valuenow"], "50");
  assert.equal(r.bar.attrs["aria-valuemin"], "0");
  assert.equal(r.bar.attrs["aria-valuemax"], "100");
  assert.match(r.status.textContent, /50% \(512 B of 1\.0 KB\)/);
  assert.equal(r.name.textContent, "Download: report.pdf");
});

test("a state says what it means and offers only the controls that apply", async () => {
  const cases = [
    [t({ state: "queued", done: 0, total: 0 }), /Waiting for a free slot/, false],
    [t({ state: "running", done: 1024, total: 1024 }), /Checking the file/, false],
    [t({ state: "done", localPath: "/d/report.pdf", verified: true }), /saved as \/d\/report\.pdf\. Verified by the computer\./, true],
    [t({ state: "failed", error: "cannot reach the agent securely: x" }), /Failed: cannot reach/, false],
    [t({ state: "cancelled" }), /Cancelled/, true],
  ];
  for (const [item, text, cancelHidden] of cases) {
    const { app } = await open([item]);
    const r = row(app);
    assert.match(r.status.textContent, text, item.state);
    assert.equal(r.cancel.hidden, cancelHidden, `${item.state} cancel`);
    assert.equal(r.retry.hidden, !(item.state === "failed" || item.state === "cancelled"), `${item.state} retry`);
  }
  const { app } = await open([t({ state: "failed", error: "x" })]);
  assert.equal(row(app).status.classList.contains("failed"), true);
  assert.equal(row(app).cancel.attrs["aria-label"], "Give up on report.pdf");
});

test("an upload row is labelled as an upload", async () => {
  const { app } = await open([t({ direction: "upload", name: "up.bin", remotePath: "/srv/up.bin", localPath: "/home/me/up.bin" })]);
  assert.equal(row(app).bar.attrs["aria-label"], "Uploading up.bin");
  assert.equal(row(app).name.textContent, "Upload: up.bin");
});

test("text from a file name is shown as text, never as markup", async () => {
  const evil = '<img src=x onerror="alert(1)">';
  const { app } = await open([t({ name: evil, error: evil, state: "failed" })]);
  assert.equal(row(app).name.textContent, "Download: " + evil);
  assert.match(row(app).status.textContent, /Failed: <img/);
  assert.equal(row(app).li.children.length, 4, "no element was made from the name");
});

test("Cancel and Retry send the row's own id, and the row keeps focus", async () => {
  const { app, calls } = await open([t({ id: "tX", state: "failed", error: "boom" })]);
  focused.length = 0;
  await row(app).retry.fire("click");
  await row(app).cancel.fire("click");
  assert.deepEqual(plain(calls), [
    ["transfer_retry", { id: "tX" }],
    ["transfer_cancel", { id: "tX" }],
  ]);
  assert.ok(focused.length >= 2, "focus returned to the row");
});

test("a refused start shows the reason as an alert and keeps what was typed", async () => {
  const { app } = await open([], {
    transfer_upload: () => Promise.reject("that path is a symbolic link; type the real path of the file"),
  });
  app.els["upload-path"].value = " /home/me/link ";
  app.els["upload-dir"].value = "/srv";
  await app.els["upload-form"].fire("submit");
  assert.match(app.message(), /symbolic link/);
  assert.equal(app.els.message.attrs.role, "alert");
  assert.equal(app.els["upload-path"].value, " /home/me/link ");
  assert.equal(app.els["upload-form"].disabled, false);
});

test("Download and Upload send trimmed paths and clear the field", async () => {
  const { app, calls } = await open([]);
  app.els["download-path"].value = "  /srv/a.txt ";
  await app.els["download-form"].fire("submit");
  app.els["upload-path"].value = "/home/me/b.txt";
  app.els["upload-dir"].value = " /srv ";
  await app.els["upload-form"].fire("submit");
  assert.deepEqual(plain(calls), [
    ["transfer_download", { remotePath: "/srv/a.txt" }],
    ["transfer_upload", { localPath: "/home/me/b.txt", remoteDir: "/srv" }],
  ]);
  assert.equal(app.els["download-path"].value, "");
  assert.equal(app.els["upload-path"].value, "");
});

test("it polls while something moves and stops when nothing does", async () => {
  let n = 0;
  const { app } = await open(() => {
    n++;
    return [t({ state: n < 3 ? "running" : "done", done: n < 3 ? 1 : 1024 })];
  });
  await settle();
  await settle();
  const after = n;
  await settle();
  assert.equal(n, after, "no more polling once the transfer ended");
  assert.ok(after >= 3);
  assert.match(row(app).status.textContent, /^Done/);
  assert.equal(app.els["transfers-status"].textContent, "report.pdf finished.");
});

test("a failure that happens while watching is announced", async () => {
  let n = 0;
  const { app } = await open(() => [t({ state: ++n < 2 ? "running" : "failed", error: "no room" })]);
  await settle();
  assert.match(app.message(), /report\.pdf failed: no room/);
  assert.equal(app.els.message.attrs.role, "alert");
});

test("Clear finished is offered only when something is finished", async () => {
  const a = await open([t()]);
  assert.equal(a.app.els["transfers-clear"].disabled, true);
  const b = await open([t({ state: "done" })]);
  assert.equal(b.app.els["transfers-clear"].disabled, false);
  await b.app.els["transfers-clear"].fire("click");
  assert.ok(b.calls.some(([n]) => n === "transfer_clear_finished"));
});

test("Back returns to the screen it was opened from", async () => {
  const { app } = await open([]);
  await app.els["transfers-back"].fire("click");
  assert.equal(app.els["step-transfers"].hidden, true);
  assert.deepEqual(app.screen(), ["step-devices"]);
});

test("window.rfeTransfers starts transfers by path for the file browser", async () => {
  const calls = [];
  const answers = {
    saved_agent: SIGNED_IN,
    list_devices: [],
    list_pins: [],
    transfer_list: [],
    transfer_download: (a) => (calls.push(["download", a]), "id-1"),
    transfer_upload: (a) => (calls.push(["upload", a]), "id-2"),
  };
  const win = {
    __TAURI__: { core: { invoke: async (name, args) => (typeof answers[name] === "function" ? answers[name](args) : answers[name]) } },
  };
  const app = boot({}, { window: win });
  opened.push(app);
  await settle();
  assert.equal(typeof win.rfeTransfers.download, "function");
  assert.equal(typeof win.rfeTransfers.upload, "function");
  assert.equal(await win.rfeTransfers.download("/srv/a.txt"), "id-1");
  assert.equal(await win.rfeTransfers.upload("/home/me/b.txt", "/srv"), "id-2");
  assert.deepEqual(plain(calls), [
    ["download", { remotePath: "/srv/a.txt" }],
    ["upload", { localPath: "/home/me/b.txt", remoteDir: "/srv" }],
  ]);
  answers.transfer_upload = () => Promise.reject("that is not a regular file");
  await assert.rejects(win.rfeTransfers.upload("/tmp", "/srv"), /not a regular file/);
});
