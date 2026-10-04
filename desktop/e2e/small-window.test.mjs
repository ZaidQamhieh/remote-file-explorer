// Layout at the size a 200% display gives this window. The compositor's scale option does not reach
// the WebKit window here (window.devicePixelRatio stays 1), so 200% of the 1280x800 screen is checked
// as what it comes to in CSS pixels: 640x400, and 520 wide, the narrowest the window may be. On
// every screen nothing may need a sideways scroll, in the page or inside a table.
//
//   desktop/e2e/run.sh

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { App, Agent, waitFor, sleep, resetAppState } from "./lib.mjs";

let agent;
let app;

before(async () => {
  agent = await Agent.start();
  resetAppState();
  app = await App.start();
  await app.fill("#host", agent.host);
  await app.click('#connect-form button[type="submit"]');
  await waitFor("the trust step", () => app.visible("#step-trust"));
  await app.click("#trust");
  await waitFor("the sign-in step", () => app.visible("#step-login"));
  await app.fill("#username", agent.user);
  await app.fill("#password", agent.password);
  await app.click('#login-form button[type="submit"]');
  await waitFor("the device list", () => app.visible("#step-devices"));
});

after(async () => {
  if (app) await app.end();
  agent?.stop();
});

// What is wider than its box, if anything: the page itself, or a table wrapper that would scroll.
const overflow = () =>
  app.script(`
    const bad = [];
    const de = document.documentElement;
    if (de.scrollWidth > de.clientWidth) bad.push("page " + de.scrollWidth + ">" + de.clientWidth);
    for (const w of document.querySelectorAll(".table-wrap")) {
      if (w.offsetParent !== null && w.scrollWidth > w.clientWidth) bad.push((w.querySelector("tbody")?.id || "table") + " " + w.scrollWidth + ">" + w.clientWidth);
    }
    return bad.join("; ");
  `);

const SIZES = [
  { name: "640x400", width: 640, height: 400 },
  { name: "520x400", width: 520, height: 400 },
];

const SCREENS = [
  { name: "devices", open: null, step: "#step-devices", back: null },
  { name: "settings", open: "#open-settings", step: "#step-settings", back: "#settings-back" },
  { name: "transfers", open: "#open-transfers", step: "#step-transfers", back: "#transfers-back" },
  { name: "health", open: "#open-health", step: "#step-health", back: "#health-back" },
  { name: "audit", open: "#open-audit", step: "#step-audit", back: "#audit-back" },
  { name: "pairing requests", open: "#open-pair-inbox", step: "#step-pair-inbox", back: "#inbox-back" },
  { name: "apps", open: "#open-apps", step: "#step-apps", back: "#apps-back" },
  { name: "pair a phone", open: "#open-pairing", step: "#step-pairing", back: "#pcodes-back" },
  { name: "files", open: "#open-files", step: "#step-files", back: "#files-back" },
];

for (const size of SIZES) {
  test(`every screen fits without a sideways scroll at ${size.name}`, async () => {
    const r = await app.rect();
    await app.setRect({ x: r.x, y: r.y, width: size.width, height: size.height });
    await waitFor("the size", async () => (await app.script("return window.innerWidth;")) <= size.width);
    const problems = [];
    for (const s of SCREENS) {
      if (s.open) await app.click(s.open);
      await waitFor(`${s.name} to show`, () => app.visible(s.step));
      await sleep(s.name === "devices" ? 100 : 1200);
      const bad = await overflow();
      if (bad) problems.push(`${s.name}: ${bad}`);
      await app.shot(`8-${size.name}-${s.name.replace(/\W+/g, "-")}.png`);
      if (s.back) {
        await app.click(s.back);
        await waitFor("the device list again", () => app.visible("#step-devices"));
      }
    }
    assert.deepEqual(problems, [], problems.join("\n"));
  });
}
