// The file browser offers a Download for a selected file and hands the path to window.rfeTransfers.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, SIGNED_IN } from "./harness.mjs";

const plain = (x) => JSON.parse(JSON.stringify(x));
const entry = (o) => ({ name: "f", path: "/r/f", isDir: false, size: 1, mimeType: "text/plain", mode: "-rw-r--r--", modified: "2026-01-02T03:04:05Z", created: "", isSymlink: false, symlinkTarget: "", childCount: null, ...o });
const CAPS = { browse: true, download: true, upload: true, modify: true, delete: true, share: true };
const ROOTS = { locations: [{ path: "/r", label: "r", totalBytes: 0, freeBytes: 0, isOS: false }], source: "roots", readOnly: false, accessDenied: false, caps: CAPS };
const FILES = [entry({ name: "dir", path: "/r/dir", isDir: true, mimeType: "", childCount: 2 }), entry({ name: "a b.txt", path: "/r/a b.txt" })];
const page = (path) => ({ path, crumbs: [{ label: "/", path: "/" }, { label: "r", path: "/r" }], entries: FILES, nextCursor: null });
const rowBtn = (app, i) => app.els["files-rows"].children[i].children[0].children[0];

const start = async (download) => {
  const downloads = [];
  const handlers = {
    saved_agent: SIGNED_IN,
    list_devices: [],
    files_roots: ROOTS,
    files_list: ({ path }) => page(path),
    transfer_list: [],
    transfer_download: (a) => (downloads.push(plain(a)), download ? download(a) : "id-1"),
  };
  const app = boot(handlers);
  await settle();
  await app.els["open-files"].fire("click");
  await app.els["files-locations"].children[0].children[0].children[0].fire("click");
  return { app, downloads };
};

test("a folder offers no download; a selected file offers one named after it", async () => {
  const { app } = await start();
  assert.equal(app.els["files-download"].hidden, true);
  await rowBtn(app, 0).fire("click");
  assert.equal(app.els["files-download"].hidden, true);
  await rowBtn(app, 1).fire("click");
  assert.equal(app.els["files-download"].hidden, false);
  assert.equal(app.els["files-download"].textContent, "Download a b.txt");
});

test("pressing Download starts the transfer by the file's path and says so", async () => {
  const { app, downloads } = await start();
  await rowBtn(app, 1).fire("click");
  await app.els["files-download"].fire("click");
  await settle();
  assert.deepEqual(downloads, [{ remotePath: "/r/a b.txt" }]);
  assert.match(app.message(), /Download of a b\.txt started/);
  assert.equal(app.els["files-download"].disabled, false);
});

test("a refused download shows the reason and keeps the button usable", async () => {
  const { app } = await start(() => Promise.reject("The download folder is not writable."));
  await rowBtn(app, 1).fire("click");
  await app.els["files-download"].fire("click");
  await settle();
  assert.match(app.message(), /not writable/);
  assert.equal(app.els["files-download"].disabled, false);
});

test("Refresh drops the offer, so a stale file is not downloaded by mistake", async () => {
  const { app, downloads } = await start();
  await rowBtn(app, 1).fire("click");
  await app.els["files-refresh"].fire("click");
  await settle();
  assert.equal(app.els["files-download"].hidden, true);
  await app.els["files-download"].fire("click");
  assert.deepEqual(downloads, []);
});
