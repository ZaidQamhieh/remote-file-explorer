// The shape of the window: panels dragged to a size, one click to open, the menu button, the interface
// size, and the same screens at the sizes a screen really has. Pictures go to E2E_SHOTS when it is set.
//
//   desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { App, Agent, waitFor, sleep, resetAppState, KEYS } from "./lib.mjs";

let agent;
let app;

before(async () => {
  agent = await Agent.start();
  // Something to look at: folders and files of different kinds.
  for (const d of ["android", "checksums", "desktop", "symbols"]) mkdirSync(join(agent.roots, d));
  mkdirSync(join(agent.roots, "desktop", "inner"));
  writeFileSync(join(agent.roots, "notes.txt"), "hello\n");
  writeFileSync(join(agent.roots, "release.apk"), Buffer.alloc(4096));
  writeFileSync(join(agent.roots, "backup.tar.zst"), Buffer.alloc(8192));
  resetAppState();
  app = await App.start();
  await app.signInAccount(agent, "layout-pc");
  await app.go("files");
  await waitFor("the listing", () => app.visible("[data-rows] .li"));
});

after(async () => {
  if (app) await app.end();
  agent?.stop();
});

const path = () => app.script("return A.mainPane.path;");
const cssVar = (n) => app.script("return document.getElementById('main').style.getPropertyValue(arguments[0]);", [n]);
const px = async (n) => parseInt(await cssVar(n), 10);

test("one click on a folder opens it", async () => {
  await app.click('[data-rows] .li[data-i="0"]');
  await waitFor("the folder to open", async () => (await path()) !== "/");
  const inside = await path();
  assert.match(inside, /rfe-e2e-roots-/);
  await waitFor("its folders", () => app.has(/android/, "[data-rows]"));
  await app.click('[data-rows] .li[data-i="0"]');
  await waitFor("android to open", async () => /android$/.test(await path()));
  await app.script("A.mainPane.go(arguments[0]);", [inside]);
  await waitFor("the folders again", () => app.has(/symbols/, "[data-rows]"));
});

test("the round icon selects without opening", async () => {
  const here = await path();
  await app.click('[data-rows] .li[data-i="1"] .lead');
  await waitFor("the row to be selected", async () => (await app.script("return A.mainPane.sel.size;")) === 1);
  assert.equal(await path(), here, "it did not open");
  await app.script("A.mainPane.sel.clear(); A.mainPane.selChanged();");
});

test("the side panel is dragged wider and narrower, within limits", async () => {
  const w0 = await px("--sidew");
  assert.equal(w0, 372);
  await app.drag("#rszSide", -120, 0);
  const w1 = await px("--sidew");
  assert.ok(w1 >= w0 + 90 && w1 <= w0 + 150, "wider by about 120: " + w1);
  await app.drag("#rszSide", -500, 0);
  assert.equal(await px("--sidew"), 640, "stops at the limit");
  await app.drag("#rszSide", 600, 0);
  assert.equal(await px("--sidew"), 300, "stops at the other limit");
  const real = await app.script("return document.getElementById('side').getBoundingClientRect().width;");
  assert.ok(Math.abs(real - 300) < 2, "the panel really is that wide: " + real);
  await app.script("A.S.sideW = 372; window.dispatchEvent(new Event('resize'));");
});

test("the transfers strip is dragged taller and folds away when dragged down", async () => {
  await app.script("A.state.sheetOpen = true; A.renderAll();");
  const h0 = await px("--sheet");
  await app.drag("[data-hdl]", 0, -100);
  const h1 = await px("--sheet");
  assert.ok(h1 >= h0 + 70 && h1 <= h0 + 130, "taller by about 100: " + h1);
  await app.drag("[data-hdl]", 0, 300);
  assert.equal(await px("--sheet"), 66, "folded");
  await app.click("[data-hdl]");
  await waitFor("it opens again", async () => (await px("--sheet")) > 100);
});

test("the menu button puts the labels beside the icons and back", async () => {
  await app.click("#rail [data-menu]");
  assert.equal(await app.script("return document.getElementById('app').classList.contains('wide');"), true);
  const w = await app.script("return document.getElementById('rail').getBoundingClientRect().width;");
  assert.ok(w > 200, "a wide rail: " + w);
  await app.shot("9-menu-open.png");
  await app.click("#rail [data-menu]");
  assert.equal(await app.script("return document.getElementById('app').classList.contains('wide');"), false);
});

test("a bigger interface size makes the page bigger and keeps the layout whole", async () => {
  const before = await app.script("return window.innerWidth;");
  await app.script("A.S.uiSize = 130; A.applyZoom();");
  await waitFor("the zoom", async () => (await app.script("return window.innerWidth;")) < before * 0.9);
  const after = await app.script("return window.innerWidth;");
  assert.ok(after >= 1100 - 2, "at least the layout's width in CSS pixels: " + after);
  const sideways = await app.script("const de = document.documentElement; return de.scrollWidth > de.clientWidth + 1;");
  assert.equal(sideways, false, "no sideways scroll");
  await app.shot("9-size-130.png");
  await app.script("A.S.uiSize = 'auto'; A.applyZoom();");
  await app.script("A.S.uiSize = 100; A.applyZoom();");
  await waitFor("back to normal", async () => (await app.script("return window.innerWidth;")) >= before - 2);
});

test("both panels dragged to their limits at the smallest window still leave a usable list", async () => {
  await app.go("files");
  await app.setRect({ x: 0, y: 0, width: 1100, height: 700 });
  await sleep(700);
  await app.script("A.state.sheetOpen = true; A.renderAll();");
  await app.drag("[data-hdl]", 0, -250);
  await app.drag("#rszSide", -300, 0);
  const box = await app.script("const r = document.querySelector('[data-rows]'); return [r.clientWidth, r.clientHeight];");
  assert.ok(box[1] >= 150, "the list is tall enough for rows: " + box);
  assert.ok(box[0] >= 400, "the list is wide enough for names: " + box);
  const nameW = await app.script("const n = document.querySelector('[data-rows] .li'); return n ? n.children[1].getBoundingClientRect().width : 0;");
  assert.ok(nameW >= 120, "the names column keeps room: " + nameW);
  await app.shot("9-limits-1100x700.png");
  await app.script("A.S.sideW = 372; A.S.sheetH = 252; A.state.sheetOpen = false; window.dispatchEvent(new Event('resize'));");
  await app.setRect({ x: 0, y: 0, width: 1440, height: 900 });
});

test("a narrow window gets the drawer: the labels over the page, closed by Escape", async () => {
  await app.setRect({ x: 0, y: 0, width: 1100, height: 700 });
  await sleep(700);
  await app.click("#rail [data-menu]");
  assert.equal(await app.script("return document.getElementById('app').classList.contains('drawer');"), true);
  await app.shot("9-drawer-1100x700.png");
  await app.press(KEYS.escape);
  await waitFor("Escape to close it", async () => !(await app.script("return document.getElementById('app').classList.contains('drawer');")));
  await app.setRect({ x: 0, y: 0, width: 1440, height: 900 });
});

test("at 125 percent on a big screen the real window is bigger, whole and in proportion", async () => {
  await app.setRect({ x: 0, y: 0, width: 2560, height: 1300 });
  await sleep(600);
  const css0 = await app.script("return window.innerWidth;");
  await app.script("A.S.uiSize = 125; A.applyZoom();");
  await waitFor("the zoom", async () => (await app.script("return window.innerWidth;")) < css0 * 0.85);
  for (const view of ["files", "tools", "settings", "servers"]) {
    // The driver's pointer coordinates do not follow the page zoom, so the page is moved by script here.
    await app.script("A.go(arguments[0]);", [view]);
    await waitFor(`${view} to draw`, () => app.has({ files: /Name/, tools: /Favorites/, settings: /Interface size/, servers: /Servers/ }[view], "#stage"));
    await sleep(700);
    await app.shot(`9-zoom125-${view}-2560x1300.png`);
    const sideways = await app.script("const de = document.documentElement; return de.scrollWidth > de.clientWidth + 1 || de.scrollHeight > de.clientHeight + 1;");
    assert.equal(sideways, false, `${view}: the page scrolls at 125 percent`);
  }
  await app.script("A.S.uiSize = 100; A.applyZoom(); A.go('files');");
  await app.setRect({ x: 0, y: 0, width: 1440, height: 900 });
});

const SIZES = [[1100, 700], [1440, 900], [2000, 1100], [2560, 1300]];
for (const view of ["files", "tools"]) {
  test(`${view} at every size`, async () => {
    await app.go(view);
    await waitFor(`${view} to draw`, () => app.has(view === "tools" ? /Favorites/ : /Name/, "#stage"));
    for (const [width, height] of SIZES) {
      await app.setRect({ x: 0, y: 0, width, height });
      await sleep(900);
      await app.shot(`9-${view}-${width}x${height}.png`);
      const sideways = await app.script("const de = document.documentElement; return de.scrollWidth > de.clientWidth + 1 || de.scrollHeight > de.clientHeight + 1;");
      assert.equal(sideways, false, `${view} ${width}x${height}: the page scrolls`);
    }
    await app.setRect({ x: 0, y: 0, width: 1440, height: 900 });
  });
}
