// The host app catalog screen: what is listed, when Launch exists, that it takes two presses and
// sends only the catalog id, and that each refusal shows its own message.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, deferred, focused, SIGNED_IN, SIGNED_OUT } from "./harness.mjs";

const id = (c) => "app_" + c.repeat(64);
const app = (o = {}) => ({ id: id("a"), name: "Editor", launchable: true, category: "Development", ...o });
const catalog = (apps, o = {}) => ({ platform: "linux", launchAllowed: true, apps, ...o });
const device = { id: "d1", label: "Laptop", created: 1, lastSeen: 0, revoked: false, current: true, lastAddress: "", lastVersion: "", viaLogin: true };

async function open(handlers) {
  const a = boot({ saved_agent: SIGNED_IN, list_devices: [device], ...handlers });
  await settle();
  await a.els["open-apps"].fire("click");
  return a;
}
const rowButton = (a, row) => a.els["apps-list"].children[row].children[3].children[0];
const rowText = (a, row, col) => a.els["apps-list"].children[row].children[col].textContent;

test("the apps screen opens from the devices screen with its heading focused", async () => {
  const a = boot({ saved_agent: SIGNED_IN, list_devices: [device], list_host_apps: catalog([app()]) });
  await settle();
  focused.length = 0;
  await a.els["open-apps"].fire("click");
  assert.equal(a.els["step-apps"].hidden, false);
  assert.equal(a.els["step-devices"].hidden, true);
  assert.equal(focused.at(-1), "title-apps");
  assert.deepEqual(a.calls.filter((c) => c === "list_host_apps"), ["list_host_apps"]);
});

test("each app is a row with its name, category and a short id (the full id in the title)", async () => {
  const a = await open({ list_host_apps: catalog([app(), app({ id: id("b"), name: "Terminal", category: "" })]) });
  assert.equal(a.els["apps-list"].children.length, 2);
  assert.equal(rowText(a, 0, 0), "Editor");
  assert.equal(rowText(a, 0, 1), "Development");
  assert.equal(rowText(a, 0, 2), "app_aaaaaaaa...");
  assert.equal(a.els["apps-list"].children[0].children[2].attrs.title, id("a"));
  assert.equal(a.els["apps-wrap"].hidden, false);
  assert.equal(a.els["apps-empty"].hidden, true);
  assert.equal(a.els["apps-note"].hidden, true);
  assert.equal(a.message(), "");
});

test("a host with no apps: the empty message, no table, no error", async () => {
  const a = await open({ list_host_apps: catalog([]) });
  assert.equal(a.els["apps-empty"].hidden, false);
  assert.equal(a.els["apps-wrap"].hidden, true);
  assert.equal(a.message(), "");
});

test("slow list: loading text, then the rows", async () => {
  const gate = deferred();
  const a = await open({ list_host_apps: () => gate.promise });
  assert.match(a.message(), /Loading apps/);
  assert.equal(a.els["apps-empty"].hidden, true, "not 'no apps' while loading");
  gate.resolve(catalog([app()]));
  await settle();
  assert.equal(a.message(), "");
  assert.equal(a.els["apps-list"].children.length, 1);
});

test("Launch needs a second press, which sends only the catalog id", async () => {
  const sent = [];
  const a = await open({
    list_host_apps: catalog([app()]),
    launch_host_app: (args) => (sent.push(args), null),
  });
  const b = rowButton(a, 0);
  assert.equal(b.textContent, "Launch");
  assert.equal(b.attrs["aria-label"], "Launch Editor");
  await b.fire("click");
  assert.equal(b.textContent, "Launch?");
  assert.match(b.attrs["aria-label"], /Launch Editor\? Press again to confirm/);
  assert.deepEqual(sent, [], "one press must not launch");
  await b.fire("click");
  assert.equal(JSON.stringify(sent), JSON.stringify([{ id: id("a") }]), "exactly the id, nothing else");
  assert.match(a.message(), /Asked the PC to open Editor/);
  assert.ok(!a.els.message.classList.contains("error"));
  assert.equal(b.textContent, "Launch", "armed state is cleared");
  assert.equal(b.disabled, false);
});

test("arming another row disarms the first, so a stray second press cannot launch the wrong app", async () => {
  const sent = [];
  const a = await open({
    list_host_apps: catalog([app(), app({ id: id("b"), name: "Terminal" })]),
    launch_host_app: (args) => (sent.push(args), null),
  });
  const first = rowButton(a, 0);
  const second = rowButton(a, 1);
  await first.fire("click");
  await second.fire("click");
  assert.equal(first.textContent, "Launch");
  assert.equal(second.textContent, "Launch?");
  await first.fire("click");
  assert.deepEqual(sent, [], "the first press after disarming only arms again");
});

test("an entry the host cannot start has no Launch button", async () => {
  const a = await open({ list_host_apps: catalog([app({ launchable: false })]) });
  assert.equal(a.els["apps-list"].children[0].children[3].children.length, 0);
  assert.match(rowText(a, 0, 3), /Cannot be launched/);
});

test("without the launch right the list shows, buttons do not, and a note says why", async () => {
  const a = await open({ list_host_apps: catalog([app()], { launchAllowed: false }) });
  assert.equal(a.els["apps-list"].children.length, 1);
  assert.equal(a.els["apps-list"].children[0].children[3].children.length, 0);
  assert.match(rowText(a, 0, 3), /Launching not allowed/);
  assert.equal(a.els["apps-note"].hidden, false);
});

test("text from the host is shown as text, never as markup", async () => {
  const name = '<img src=x onerror="alert(1)">';
  const a = await open({ list_host_apps: catalog([app({ name, category: "<b>x</b>" })]) });
  assert.equal(rowText(a, 0, 0), name);
  assert.equal(rowText(a, 0, 1), "<b>x</b>");
  assert.equal(rowButton(a, 0).attrs["aria-label"], "Launch " + name);
});

const refusals = {
  view: "This computer is not allowed to see the host's apps. On the PC's agent, turn on app viewing for this computer, then refresh.",
  launch: "This computer may see the host's apps but not start them. On the PC's agent, turn on app launching for this computer.",
  gone: "That app is no longer in the host's catalog. It may have been uninstalled. Refresh the list.",
  notLaunchable: "The host has no way to start that app. It is listed but cannot be launched from here.",
  busy: "The host is already starting another app. Wait a moment, then try again.",
  session: "Nobody is signed in to a graphical desktop on the host, so there is nowhere to open the app. Sign in at the PC, then try again.",
};

test("a refused list shows its reason as an alert and no stale or empty list", async () => {
  const a = await open({ list_host_apps: () => Promise.reject(refusals.view) });
  assert.equal(a.els["step-apps"].hidden, false, "stays on the apps screen with the reason");
  assert.equal(a.message(), refusals.view);
  assert.equal(a.els.message.attrs.role, "alert");
  assert.equal(a.els["apps-wrap"].hidden, true);
  assert.equal(a.els["apps-empty"].hidden, true, "a refusal is not 'no apps'");
  assert.equal(a.els["apps-refresh"].disabled, false);
});

test("refresh after a refusal can succeed and replaces the message", async () => {
  let ok = false;
  const a = await open({ list_host_apps: () => (ok ? catalog([app()]) : Promise.reject(refusals.view)) });
  assert.equal(a.message(), refusals.view);
  ok = true;
  await a.els["apps-refresh"].fire("click");
  assert.equal(a.message(), "");
  assert.equal(a.els["apps-list"].children.length, 1);
});

test("403, 404, 409 and 503 on launch each show their own message", async () => {
  const seen = [];
  for (const [name, text] of Object.entries(refusals).filter(([n]) => n !== "view")) {
    const a = await open({
      list_host_apps: catalog([app()]),
      launch_host_app: () => Promise.reject(text),
    });
    const b = rowButton(a, 0);
    await b.fire("click");
    await b.fire("click");
    assert.equal(a.message(), text, name);
    assert.ok(a.els.message.classList.contains("error"), name);
    assert.equal(a.els.message.attrs.role, "alert", name);
    assert.equal(b.disabled, false, name);
    assert.equal(a.els["step-apps"].hidden, false, name);
    seen.push(a.message());
  }
  assert.equal(new Set(seen).size, seen.length, "two refusals read the same");
});

test("a launch while the list is long gone for the app: the list stays so Refresh can fix it", async () => {
  const a = await open({
    list_host_apps: catalog([app()]),
    launch_host_app: () => Promise.reject(refusals.gone),
  });
  const b = rowButton(a, 0);
  await b.fire("click");
  await b.fire("click");
  assert.equal(a.els["apps-list"].children.length, 1);
});

test("the agent drops this computer's login: back to sign-in with the reason", async () => {
  let saved = SIGNED_IN;
  const a = await open({
    saved_agent: () => saved,
    list_host_apps: () => {
      saved = { ...SIGNED_OUT, fingerprint: "ab".repeat(32), username: "zaid" };
      return Promise.reject("The agent no longer accepts this login. Sign in again.");
    },
  });
  assert.equal(a.els["step-login"].hidden, false);
  assert.equal(a.els["step-apps"].hidden, true);
  assert.match(a.message(), /no longer accepts this login/);
  assert.equal(a.els.username.value, "zaid");
});

test("Back returns to the devices screen and clears the message", async () => {
  const a = await open({ list_host_apps: () => Promise.reject(refusals.view) });
  await a.els["apps-back"].fire("click");
  assert.equal(a.els["step-devices"].hidden, false);
  assert.equal(a.els["step-apps"].hidden, true);
  assert.equal(a.message(), "");
});

test("the screen is reachable from Settings and Back from there returns to it", async () => {
  const a = await open({ list_host_apps: catalog([app()]), app_settings: { logLevel: "info", appVersion: "1", clientVersion: "c", minAgentForApproval: "m", dataDir: "/d", platform: "linux" }, list_pins: [] });
  await a.els["open-settings"].fire("click");
  assert.equal(a.els["step-settings"].hidden, false);
  await a.els["settings-back"].fire("click");
  assert.equal(a.els["step-apps"].hidden, false);
});
