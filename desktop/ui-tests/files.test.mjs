// The file browser screen: locations, folders, breadcrumbs, sorting, keyboard, empty, error and
// loading states, the agent's permissions and refusals, and the hook the transfers screen uses.
// Drives desktop/ui/app.js against the fake DOM with `invoke` answered by the test.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { El, boot, settle, deferred, SIGNED_IN, SIGNED_OUT } from "./harness.mjs";

// Objects made inside the app's sandbox have another Object prototype; compare plain copies.
const plain = (x) => JSON.parse(JSON.stringify(x));
const entry = (o = {}) => ({ name: "f", path: "/r/f", isDir: false, size: 1, mimeType: "text/plain", mode: "-rw-r--r--", modified: "2026-01-02T03:04:05Z", created: "", isSymlink: false, symlinkTarget: "", childCount: null, ...o });
const CAPS = { browse: true, download: true, upload: true, modify: true, delete: true, share: true };
const roots = (o = {}) => ({ locations: [{ path: "/r", label: "r", totalBytes: 0, freeBytes: 0, isOS: false }], source: "roots", readOnly: false, accessDenied: false, caps: CAPS, ...o });
const crumbsOf = (path) => {
  const parts = path.split("/").filter(Boolean);
  return [{ label: "/", path: "/" }, ...parts.map((p, i) => ({ label: p, path: "/" + parts.slice(0, i + 1).join("/") }))];
};
const page = (path, entries, nextCursor = null) => ({ path, crumbs: crumbsOf(path), entries, nextCursor });

// Which element last took focus (the harness records ids, and rows have none).
let lastFocus = null;
const realFocus = El.prototype.focus;
El.prototype.focus = function () {
  lastFocus = this;
  realFocus.call(this);
};

const open = async (handlers, extra) => {
  const app = boot({ saved_agent: SIGNED_IN, list_devices: [], ...handlers }, extra);
  await settle();
  await app.els["open-files"].fire("click");
  return app;
};
const names = (app) => app.els["files-rows"].children.map((tr) => tr.children[0].children[0].textContent);
const rowBtn = (app, i) => app.els["files-rows"].children[i].children[0].children[0];
const actions = (app, i) => app.els["files-rows"].children[i].children[4].children;
const trail = (app) => app.els["files-trail"].children.map((li) => li.children[0].textContent);
const key = (app, id, k, target = { tagName: "BUTTON" }) => {
  let prevented = false;
  for (const fn of app.els[id].listeners.keydown || []) fn({ key: k, target, preventDefault: () => (prevented = true) });
  return prevented;
};
const screens = (app) => ["step-connect", "step-login", "step-devices", "step-files"].filter((s) => !app.els[s].hidden);

const FILES = [
  entry({ name: "zeta.txt", path: "/r/zeta.txt", size: 5 }),
  entry({ name: "alpha", path: "/r/alpha", isDir: true, mimeType: "", childCount: 3 }),
  entry({ name: "big.bin", path: "/r/big.bin", size: 5 * 1024 * 1024, modified: "2025-01-01T00:00:00Z" }),
  entry({ name: "beta", path: "/r/beta", isDir: true, mimeType: "", childCount: 1000, modified: "2024-01-01T00:00:00Z" }),
  entry({ name: "file10.txt", path: "/r/file10.txt", size: 1 }),
  entry({ name: "file2.txt", path: "/r/file2.txt", size: 2 }),
];

test("Files opens the locations the agent offers; a location opens its folder with a trail", async () => {
  const calls = [];
  const app = await open({
    files_roots: roots(),
    files_list: (a) => (calls.push(plain(a)), page(a.path, FILES)),
  });
  assert.deepEqual(screens(app), ["step-files"]);
  assert.equal(app.els["files-locations-table"].hidden, false);
  assert.equal(app.els["files-locations"].children.length, 1);
  assert.deepEqual(trail(app), ["Locations"]);
  assert.equal(app.message(), "");

  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-list-wrap"].hidden, false);
  assert.deepEqual(calls, [{ path: "/r", cursor: null, limit: 500 }]);
  // The trail starts at the location, not at the top of the drive.
  assert.deepEqual(trail(app), ["Locations", "r"]);
  // Folders first, then files; names in natural order.
  assert.deepEqual(names(app), ["alpha", "beta", "big.bin", "file2.txt", "file10.txt", "zeta.txt"]);
  const alpha = app.els["files-rows"].children[0];
  assert.equal(alpha.children[1].textContent, "Folder");
  assert.equal(alpha.children[2].textContent, "3 items");
  assert.equal(app.els["files-rows"].children[1].children[2].textContent, "1000+ items");
  assert.equal(app.els["files-rows"].children[2].children[2].textContent, "5.0 MB");
  assert.equal(rowBtn(app, 0).attrs["aria-label"], "Open folder alpha");
  assert.equal(rowBtn(app, 2).attrs["aria-label"], "Select file big.bin");
});

test("loading shows a status, then the folder; a slow old answer does not replace a newer one", async () => {
  const slow = deferred();
  const dirs = [entry({ name: "slow", path: "/r/slow", isDir: true, mimeType: "" }), entry({ name: "fast", path: "/r/fast", isDir: true, mimeType: "" })];
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => (path === "/r" ? page(path, dirs) : path === "/r/slow" ? slow.promise : page(path, [entry({ name: "x", path: path + "/x" })])),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  const waiting = rowBtn(app, 1).fire("click"); // "slow" sorts after "fast"
  await settle();
  assert.equal(app.message(), "Loading folder...");
  assert.equal(app.els["files-list-wrap"].hidden, false, "the old folder stays until the new one arrives");
  await rowBtn(app, 0).fire("click"); // fast
  assert.deepEqual(names(app), ["x"]);
  assert.deepEqual(trail(app), ["Locations", "r", "fast"]);
  slow.resolve(page("/r/slow", [entry({ name: "stale", path: "/r/slow/stale" })]));
  await waiting;
  await settle();
  assert.deepEqual(names(app), ["x"], "the late answer for an old request did not replace the screen");
  assert.equal(app.message(), "");
});

test("a folder that cannot be opened shows the agent's refusal and stays where it was", async () => {
  const refusal = "The agent says: path is outside allowed root: /elsewhere (FORBIDDEN)";
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => (path === "/r" ? page("/r", [entry({ name: "go", path: "/elsewhere", isDir: true })]) : Promise.reject(refusal)),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  await rowBtn(app, 0).fire("click");
  assert.equal(app.message(), refusal);
  assert.ok(app.els.message.classList.contains("error"));
  assert.equal(app.els.message.attrs.role, "alert");
  assert.deepEqual(names(app), ["go"]);
  assert.deepEqual(screens(app), ["step-files"]);
});

test("no location open to this login says why, for each reason", async () => {
  for (const [r, text] of [
    [roots({ locations: [], accessDenied: true }), /confined this computer to a folder it does not allow/],
    [roots({ locations: [], caps: { ...CAPS, browse: false } }), /not allowed to browse/],
    [roots({ locations: [] }), /has not shared a folder/],
  ]) {
    const app = await open({ files_roots: r });
    assert.equal(app.els["files-locations-empty"].hidden, false);
    assert.match(app.els["files-locations-empty"].textContent, /^No folder is open to this login\./);
    assert.match(app.els["files-locations-empty"].textContent, text);
    assert.equal(app.els["files-locations-table"].hidden, true);
  }
});

test("an empty folder says so", async () => {
  const app = await open({ files_roots: roots(), files_list: ({ path }) => page(path, []) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-empty"].hidden, false);
  assert.equal(names(app).length, 0);
});

test("the agent cannot be reached: the error is an alert and nothing stale is shown", async () => {
  const app = await open({ files_roots: () => Promise.reject("cannot reach the agent securely: timed out") });
  assert.match(app.message(), /cannot reach the agent/);
  assert.equal(app.els.message.attrs.role, "alert");
  assert.equal(app.els["files-locations-table"].hidden, true);
  assert.equal(app.els["files-locations-empty"].hidden, true, "no 'no folder' claim when the question was never answered");
});

test("the agent refuses the saved login: back to sign-in with the reason", async () => {
  let n = 0;
  const app = await open({
    saved_agent: () => (n++ === 0 ? SIGNED_IN : { ...SIGNED_OUT, fingerprint: "ab".repeat(32), username: "zaid" }),
    files_roots: () => Promise.reject("The agent no longer accepts this login. Sign in again."),
    list_devices: () => Promise.reject("not signed in"),
  });
  assert.deepEqual(screens(app), ["step-login"]);
  assert.match(app.message(), /no longer accepts this login/);
});

test("sorting: a column toggles direction, folders stay first, the header says which", async () => {
  const app = await open({ files_roots: roots(), files_list: ({ path }) => page(path, FILES) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-th-name"].attrs["aria-sort"], "ascending");
  await app.els["files-sort-name"].fire("click");
  assert.equal(app.els["files-th-name"].attrs["aria-sort"], "descending");
  assert.deepEqual(names(app), ["beta", "alpha", "zeta.txt", "file10.txt", "file2.txt", "big.bin"]);
  await app.els["files-sort-size"].fire("click");
  assert.equal(app.els["files-th-name"].attrs["aria-sort"], "none");
  assert.equal(app.els["files-th-size"].attrs["aria-sort"], "ascending");
  assert.deepEqual(names(app), ["alpha", "beta", "file10.txt", "file2.txt", "zeta.txt", "big.bin"]);
  await app.els["files-sort-modified"].fire("click");
  assert.deepEqual(names(app).slice(0, 2), ["beta", "alpha"], "oldest folder first");
  assert.match(app.els["files-status"].textContent, /^Sorted by modified, ascending\./);
});

test("keyboard: one tab stop, arrows and Home/End move, Enter opens, Backspace goes up", async () => {
  const lists = [];
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => (lists.push(path), page(path, path === "/r" ? FILES : [entry({ name: "inner.txt", path: path + "/inner.txt" })])),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  // Focus lands on the first row; only that row is in the tab order.
  assert.equal(lastFocus, rowBtn(app, 0));
  assert.equal(rowBtn(app, 0).attrs.tabindex, "0");
  assert.equal(rowBtn(app, 1).attrs.tabindex, "-1");
  assert.ok(key(app, "files-table", "ArrowDown"));
  assert.equal(lastFocus, rowBtn(app, 1));
  assert.equal(rowBtn(app, 0).attrs.tabindex, "-1");
  assert.equal(rowBtn(app, 1).attrs.tabindex, "0");
  key(app, "files-table", "ArrowUp");
  key(app, "files-table", "ArrowUp");
  assert.equal(lastFocus, rowBtn(app, 0), "stops at the first row");
  key(app, "files-table", "End");
  assert.equal(lastFocus, rowBtn(app, 5));
  key(app, "files-table", "ArrowDown");
  assert.equal(lastFocus, rowBtn(app, 5), "stops at the last row");
  key(app, "files-table", "Home");
  assert.equal(lastFocus, rowBtn(app, 0));
  // Enter on a folder's name is its click (it is a button).
  await rowBtn(app, 0).fire("click");
  assert.deepEqual(lists.at(-1), "/r/alpha");
  assert.deepEqual(trail(app), ["Locations", "r", "alpha"]);
  assert.deepEqual(names(app), ["inner.txt"]);
  // Backspace goes up one folder, then back to the locations, then leaves.
  assert.ok(key(app, "step-files", "Backspace"));
  await settle();
  assert.deepEqual(lists.at(-1), "/r");
  assert.deepEqual(trail(app), ["Locations", "r"]);
  key(app, "step-files", "Backspace");
  await settle();
  assert.deepEqual(trail(app), ["Locations"]);
  assert.equal(app.els["files-locations-wrap"].hidden, false);
  key(app, "step-files", "Backspace");
  await settle();
  assert.deepEqual(screens(app), ["step-devices"]);
  // Typing in a box must keep Backspace for itself.
  assert.equal(key(app, "step-files", "Backspace", { tagName: "INPUT" }), false);
});

test("the trail's earlier steps are buttons that go there; the current one is not", async () => {
  const app = await open({ files_roots: roots(), files_list: ({ path }) => page(path.startsWith("/r/a") ? "/r/a/b" : path, [entry({ name: "d", path: "/r/a", isDir: true, mimeType: "" })]) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  await rowBtn(app, 0).fire("click");
  const li = app.els["files-trail"].children;
  assert.deepEqual(trail(app), ["Locations", "r", "a", "b"]);
  assert.equal(li[3].children[0].attrs["aria-current"], "page");
  assert.equal(li[2].children[0].attrs["aria-label"], "Go to folder a");
});

test("a file's Enter hands the entry to window.rfeFileActions.onFileSelected", async () => {
  const picked = [];
  const handlers = { saved_agent: SIGNED_IN, list_devices: [], files_roots: roots(), files_list: ({ path }) => page(path, FILES) };
  const window = {
    rfeFileActions: { onFileSelected: (e) => picked.push(e) },
    __TAURI__: { core: { invoke: (n, a) => Promise.resolve().then(() => (typeof handlers[n] === "function" ? handlers[n](a) : handlers[n])) } },
  };
  const app = boot(handlers, { window });
  await settle();
  await app.els["open-files"].fire("click");
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  await rowBtn(app, 2).fire("click");
  assert.equal(picked.length, 1);
  assert.equal(picked[0].name, "big.bin");
  assert.equal(picked[0].path, "/r/big.bin");
  // A folder is opened, not handed over.
  await rowBtn(app, 0).fire("click");
  assert.equal(picked.length, 1);
});

test("without a transfers screen the default hook only says which file was chosen", async () => {
  const app = await open({ files_roots: roots(), files_list: ({ path }) => page(path, FILES) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  await rowBtn(app, 2).fire("click");
  assert.equal(app.els["files-status"].textContent, "Selected /r/big.bin.");
});

test("a symlink is asked about: the agent's refusal is shown, a folder opens, a file is selected", async () => {
  const link = (name, target) => entry({ name, path: "/r/" + name, isSymlink: true, symlinkTarget: target, mimeType: "application/octet-stream" });
  const picked = [];
  const meta = {
    "/r/escape": () => Promise.reject("The agent says: path is outside allowed root: /r/escape (FORBIDDEN)"),
    "/r/dirlink": () => entry({ name: "docs", path: "/r/docs", isDir: true }),
    "/r/filelink": () => entry({ name: "a.txt", path: "/r/a.txt" }),
  };
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => page(path, path === "/r" ? [link("dirlink", "/r/docs"), link("escape", "/tmp/outside"), link("filelink", "/r/a.txt")] : []),
    files_meta: ({ path }) => meta[path](),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  const text = (i) => app.els["files-rows"].children[i].children[0].children[1].textContent;
  assert.equal(text(1), " → /tmp/outside");
  assert.equal(app.els["files-rows"].children[1].children[1].textContent, "Link");

  await rowBtn(app, 1).fire("click");
  assert.match(app.message(), /^The agent says: path is outside allowed root/);
  assert.deepEqual(trail(app), ["Locations", "r"], "still in the folder it was in");

  app.els["files-status"].textContent = "";
  await rowBtn(app, 2).fire("click");
  assert.equal(app.els["files-status"].textContent, "Selected /r/a.txt.");
  void picked;

  await rowBtn(app, 0).fire("click");
  assert.deepEqual(trail(app), ["Locations", "r", "docs"], "a link to a folder opens the folder it resolves to");
});

test("names are text, never markup", async () => {
  const evil = '<img src=x onerror="alert(1)">';
  const app = await open({ files_roots: roots(), files_list: ({ path }) => page(path, [entry({ name: evil, path: "/r/" + evil })]) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(rowBtn(app, 0).textContent, evil);
  assert.equal(rowBtn(app, 0).children.length, 0);
});

test("more entries: Load more appends the next page and goes away at the end", async () => {
  const calls = [];
  const app = await open({
    files_roots: roots(),
    files_list: (a) => {
      calls.push(plain(a));
      return a.cursor ? page(a.path, [entry({ name: "z2", path: "/r/z2" })], null) : page(a.path, [entry({ name: "a1", path: "/r/a1" })], "a1");
    },
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-more-block"].hidden, false);
  assert.deepEqual(names(app), ["a1"]);
  await app.els["files-more"].fire("click");
  assert.deepEqual(calls.at(-1), { path: "/r", cursor: "a1", limit: 500 });
  assert.deepEqual(names(app), ["a1", "z2"]);
  assert.equal(app.els["files-more-block"].hidden, true);
});

test("an agent that allows only browsing: no change buttons, and the note says why", async () => {
  const app = await open({ files_roots: roots({ caps: { ...CAPS, modify: false, delete: false } }), files_list: ({ path }) => page(path, FILES) });
  assert.equal(app.els["files-note"].hidden, false);
  assert.match(app.els["files-note"].textContent, /may look but not change/);
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-new-folder"].hidden, true);
  assert.equal(actions(app, 0).length, 0);
});

test("a read-only agent: no change buttons, and the note says so", async () => {
  const app = await open({ files_roots: roots({ readOnly: true }), files_list: ({ path }) => page(path, FILES) });
  assert.match(app.els["files-note"].textContent, /The agent is read-only/);
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-new-folder"].hidden, true);
  assert.equal(actions(app, 0).length, 0);
});

test("only the allowed changes are offered: modify without delete", async () => {
  const app = await open({ files_roots: roots({ caps: { ...CAPS, delete: false } }), files_list: ({ path }) => page(path, FILES) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-new-folder"].hidden, false);
  assert.deepEqual(actions(app, 0).map((b) => b.textContent), ["Rename"]);
});

test("delete needs a second press, moves to the trash and removes the row; a refusal keeps it", async () => {
  const trashed = [];
  let refuse = false;
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => page(path, FILES),
    files_trash: ({ path }) => (refuse ? Promise.reject("The agent says: device lacks delete permission (CAPABILITY_DENIED)") : (trashed.push(path), null)),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  const del = actions(app, 3)[1];
  assert.equal(del.attrs["aria-label"], "Delete file2.txt");
  await del.fire("click");
  assert.deepEqual(trashed, [], "the first press only arms it");
  assert.equal(del.textContent, "Delete?");
  assert.match(del.attrs["aria-label"], /Press again/);
  assert.match(app.message(), /^Press Delete again to move file2\.txt to the trash/);
  refuse = true;
  await del.fire("click");
  assert.match(app.message(), /device lacks delete permission \(CAPABILITY_DENIED\)/);
  assert.ok(names(app).includes("file2.txt"));
  refuse = false;
  // The button is still armed after a refusal: one more press tries again.
  await del.fire("click");
  assert.deepEqual(trashed, ["/r/file2.txt"]);
  assert.ok(!names(app).includes("file2.txt"));
  assert.match(app.message(), /^Moved to the trash: file2\.txt/);
  // Escape cancels an armed delete.
  const next = actions(app, 3)[1];
  await next.fire("click");
  key(app, "step-files", "Escape");
  assert.equal(next.textContent, "Delete");
});

test("new folder: the box, the agent's answer, and its refusal text in place", async () => {
  const made = [];
  let refuse = "";
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => page(path, FILES),
    files_create_folder: ({ parent, name }) => (refuse ? Promise.reject(refuse) : (made.push(plain([parent, name])), entry({ name, path: parent + "/" + name, isDir: true, mimeType: "" }))),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  await app.els["files-new-folder"].fire("click");
  assert.equal(app.els["files-name-form"].hidden, false);
  assert.equal(app.els["files-name-label"].textContent, "Folder name");
  assert.equal(lastFocus, app.els["files-name"]);

  refuse = "The agent says: destination already exists (CONFLICT)";
  app.els["files-name"].value = "alpha";
  await app.els["files-name-form"].fire("submit");
  assert.equal(app.message(), refuse);
  assert.equal(app.els["files-name-form"].hidden, false, "the box stays open to fix the name");

  refuse = "";
  app.els["files-name"].value = "neu";
  await app.els["files-name-form"].fire("submit");
  assert.deepEqual(made.at(-1), ["/r", "neu"]);
  assert.equal(app.els["files-name-form"].hidden, true);
  assert.ok(names(app).includes("neu"));
  assert.equal(rowBtn(app, names(app).indexOf("neu")), lastFocus);
});

test("rename: prefilled with the name, replaces the row, Escape closes the box", async () => {
  const calls = [];
  const app = await open({
    files_roots: roots(),
    files_list: ({ path }) => page(path, FILES),
    files_rename: (a) => (calls.push(plain(a)), entry({ name: a.newName, path: "/r/" + a.newName, size: 5 })),
  });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  const at = names(app).indexOf("zeta.txt");
  await actions(app, at)[0].fire("click");
  assert.equal(app.els["files-name-label"].textContent, "New name for zeta.txt");
  assert.equal(app.els["files-name"].value, "zeta.txt");
  key(app, "step-files", "Escape", { tagName: "INPUT" });
  assert.equal(app.els["files-name-form"].hidden, true);
  assert.equal(lastFocus, rowBtn(app, at), "focus returns to the row it came from");

  await actions(app, at)[0].fire("click");
  app.els["files-name"].value = "omega.txt";
  await app.els["files-name-form"].fire("submit");
  assert.deepEqual(calls, [{ path: "/r/zeta.txt", newName: "omega.txt" }]);
  assert.ok(names(app).includes("omega.txt") && !names(app).includes("zeta.txt"));
});

test("the screen and its controls have names for assistive technology", async () => {
  const app = await open({ files_roots: roots(), files_list: ({ path }) => page(path, FILES) });
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  assert.equal(app.els["files-table"].attrs["aria-label"], "Contents of /r");
  assert.equal(app.els["files-status"].attrs.role, undefined, "the status line is marked up in the page");
  for (let i = 0; i < 6; i++) {
    for (const b of actions(app, i)) assert.match(b.attrs["aria-label"], /^(Rename|Delete) /);
    assert.ok(rowBtn(app, i).attrs["aria-label"]);
  }
});
