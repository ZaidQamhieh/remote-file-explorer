// The per-device actions in the devices table: who gets them, the two-press confirmation (and the
// stronger one on this computer's own device), the refresh after every action, and the 403 and 404
// states. Drives desktop/ui/app.js against a fake DOM with `invoke` answered by the test.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, focused, deferred, SIGNED_IN } from "./harness.mjs";

const device = (o = {}) => ({ id: "d1", label: "Laptop", created: 1, lastSeen: 0, revoked: false, current: false, lastAddress: "", lastVersion: "", viaLogin: false, ...o });
const me = device({ id: "me", label: "This PC", current: true, viaLogin: true });
const phone = device({ id: "ph", label: "Phone" });

const access = (o = {}) => ({ id: "ph", label: "Phone", viaLogin: false, jailRoot: "", readOnly: false, viewApps: false, launchApps: false, browse: true, download: false, upload: false, modify: false, delete: false, share: false, ...o });

// The buttons in one row's last cell.
const buttons = (app, row) => app.els.devices.children[row].children.at(-1).children[0]?.children ?? [];
const named = (app, row, text) => buttons(app, row).find((b) => b.textContent.startsWith(text));

function start(extra = {}) {
  let list = [me, phone];
  const seen = [];
  // Arguments are made inside the app's own vm context; copy them so deepEqual compares plain data.
  const note = (name, a) => seen.push([name, JSON.parse(JSON.stringify(a))]);
  const app = boot({
    saved_agent: SIGNED_IN,
    list_pins: [],
    list_devices: () => list,
    revoke_device: (a) => (note("revoke_device", a), { signedOut: !!a.confirmSelf }),
    remove_device: (a) => (note("remove_device", a), { signedOut: !!a.confirmSelf }),
    device_access: (a) => (note("device_access", a), access({ id: a.id })),
    set_device_access: (a) => (note("set_device_access", a), access({ id: a.id })),
    ...extra,
  });
  return { app, seen, setList: (l) => (list = l) };
}

test("an admin session gets Access, Revoke and Remove on an active device, and no rename", async () => {
  const { app } = start();
  await settle();
  assert.deepEqual(app.screen(), ["step-devices"]);
  assert.deepEqual(buttons(app, 1).map((b) => b.textContent), ["Access", "Revoke", "Remove"]);
  assert.equal(buttons(app, 1)[0].attrs["aria-label"], "Change access for Phone");
  assert.equal(buttons(app, 1)[1].attrs["aria-label"], "Revoke Phone");
  assert.equal(buttons(app, 0)[1].attrs["aria-label"], "Revoke This PC (this computer)");
  assert.ok(!buttons(app, 1).some((b) => /rename/i.test(b.textContent)));
  assert.equal(app.els["da-hint"].hidden, false);
});

test("a revoked device can only be removed", async () => {
  const { app } = start({ list_devices: () => [me, device({ id: "x", label: "Old", revoked: true })] });
  await settle();
  assert.deepEqual(buttons(app, 1).map((b) => b.textContent), ["Remove"]);
});

test("an ordinary session sees no actions, only the empty cell", async () => {
  const { app } = start({ list_devices: () => [device({ id: "me", label: "This PC", current: true, viaLogin: false })] });
  await settle();
  assert.equal(buttons(app, 0).length, 0);
  assert.equal(app.els["da-hint"].hidden, true);
  assert.equal(app.els["devices-note"].hidden, false);
});

test("revoke needs two presses, then the list is refreshed and the result said", async () => {
  const { app, seen, setList } = start();
  await settle();
  const before = app.calls.filter((c) => c === "list_devices").length;
  const revoke = named(app, 1, "Revoke");
  await revoke.fire("click");
  assert.deepEqual(seen, [], "the first press only arms");
  assert.equal(revoke.textContent, "Revoke?");
  assert.match(revoke.attrs["aria-label"], /Revoke\? Phone Press again to confirm/);

  setList([me, device({ ...phone, revoked: true })]);
  await revoke.fire("click");
  assert.deepEqual(seen, [["revoke_device", { id: "ph", confirmSelf: false }]]);
  assert.equal(app.calls.filter((c) => c === "list_devices").length, before + 1, "refreshed");
  assert.equal(app.message(), "Revoked Phone.");
  assert.ok(!app.els.message.classList.contains("error"));
  assert.deepEqual(buttons(app, 1).map((b) => b.textContent), ["Remove"], "the table shows it revoked");
});

test("remove needs two presses and says what it did", async () => {
  const { app, seen, setList } = start();
  await settle();
  const remove = named(app, 1, "Remove");
  await remove.fire("click");
  assert.deepEqual(seen, []);
  setList([me]);
  await remove.fire("click");
  assert.deepEqual(seen, [["remove_device", { id: "ph", confirmSelf: false }]]);
  assert.equal(app.message(), "Removed Phone.");
  assert.equal(app.els.devices.children.length, 1);
});

test("this computer's own device: a stronger warning first, then it signs out", async () => {
  const { app, seen } = start();
  await settle();
  const revoke = named(app, 0, "Revoke");
  await revoke.fire("click");
  assert.deepEqual(seen, []);
  assert.equal(revoke.textContent, "Sign this computer out?");
  assert.match(app.message(), /This is the computer you are using\. Revoke signs you out here/);
  assert.match(app.message(), /Press the button again to sign this computer out/);
  assert.equal(app.els.message.attrs.role, "alert", "the warning interrupts a screen reader");
  assert.match(revoke.attrs["aria-label"], /^Press the button again to sign this computer out/);

  await revoke.fire("click");
  assert.deepEqual(seen, [["revoke_device", { id: "me", confirmSelf: true }]]);
  assert.deepEqual(app.screen(), ["step-connect"], "the session is over");
  assert.equal(app.els.devices.children.length, 0);
  assert.match(app.message(), /^Revoked This PC\. This computer is signed out; sign in again/);
});

test("a refused action (403): the reason shows as an alert and the list is reloaded", async () => {
  const { app, seen } = start({
    revoke_device: () => Promise.reject("This login is not an admin session, so the agent will not change other devices. Sign in with the account (not a pairing code or an approval on the PC) to revoke, remove or change access."),
  });
  await settle();
  const before = app.calls.filter((c) => c === "list_devices").length;
  const revoke = named(app, 1, "Revoke");
  await revoke.fire("click");
  await revoke.fire("click");
  assert.match(app.message(), /not an admin session/);
  assert.ok(app.els.message.classList.contains("error"));
  assert.equal(app.els.message.attrs.role, "alert");
  assert.equal(app.calls.filter((c) => c === "list_devices").length, before + 1);
  assert.equal(revoke.disabled, false, "usable again");
  assert.deepEqual(seen, []);
});

test("a device that is already gone (404): the message shows and the row is gone after the refresh", async () => {
  const { app, setList } = start({
    remove_device: () => Promise.reject("That device is no longer on the agent (it may already have been removed). The list has been refreshed."),
  });
  await settle();
  setList([me]);
  const remove = named(app, 1, "Remove");
  await remove.fire("click");
  await remove.fire("click");
  assert.match(app.message(), /no longer on the agent/);
  assert.ok(app.els.message.classList.contains("error"));
  assert.equal(app.els.devices.children.length, 1);
});

test("the agent refuses the saved login during an action: back to sign-in with the reason", async () => {
  let listed = 0;
  let saved = 0;
  const { app } = start({
    saved_agent: () => (saved++ === 0 ? SIGNED_IN : { host: "pc:8765", fingerprint: "ab".repeat(32), signedIn: false, username: "zaid" }),
    list_devices: () => (listed++ === 0 ? [me, phone] : Promise.reject("The agent no longer accepts this login. Sign in again.")),
    revoke_device: () => Promise.reject("The agent no longer accepts this login. Sign in again."),
  });
  await settle();
  const revoke = named(app, 1, "Revoke");
  await revoke.fire("click");
  await revoke.fire("click");
  assert.deepEqual(app.screen(), ["step-login"]);
  assert.match(app.message(), /no longer accepts this login/);
  assert.ok(app.els.message.classList.contains("error"));
});

test("Access opens the editor with the device's settings and moves focus to it", async () => {
  const { app, seen } = start({ device_access: (a) => access({ id: a.id, download: true, jailRoot: "/srv/files" }) });
  await settle();
  focused.length = 0;
  await named(app, 1, "Access").fire("click");
  assert.equal(app.els["da-editor"].hidden, false);
  assert.equal(app.els["da-editor-title"].textContent, "Access for Phone");
  assert.equal(app.els["da-browse"].checked, true);
  assert.equal(app.els["da-download"].checked, true);
  assert.equal(app.els["da-upload"].checked, false);
  assert.equal(app.els["da-jail"].value, "/srv/files");
  assert.equal(focused.at(-1), "da-editor-title");
  assert.equal(app.els["da-editor-hint"].textContent, "");
  assert.equal(seen.length, 0, "opening changes nothing");
});

test("saving sends only what changed, then closes the editor and refreshes", async () => {
  const { app, seen } = start({ device_access: (a) => access({ id: a.id, jailRoot: "/srv/files" }) });
  await settle();
  await named(app, 1, "Access").fire("click");
  app.els["da-upload"].checked = true;
  app.els["da-readonly"].checked = true;
  const before = app.calls.filter((c) => c === "list_devices").length;
  await app.els["da-save"].fire("click");
  assert.deepEqual(seen.at(-1), ["set_device_access", { id: "ph", patch: { upload: true, readOnly: true }, confirmSelf: false }]);
  assert.equal(app.els["da-editor"].hidden, true);
  assert.equal(app.calls.filter((c) => c === "list_devices").length, before + 1);
  assert.equal(app.message(), "Saved the access of Phone.");
});

test("a changed folder limit is sent, an emptied one clears it", async () => {
  const { app, seen } = start({ device_access: (a) => access({ id: a.id, jailRoot: "/srv/files" }) });
  await settle();
  await named(app, 1, "Access").fire("click");
  app.els["da-jail"].value = "";
  await app.els["da-save"].fire("click");
  assert.deepEqual(seen.at(-1)[1].patch, { jailRoot: "" });
});

test("saving with nothing changed says so and sends nothing", async () => {
  const { app, seen } = start();
  await settle();
  await named(app, 1, "Access").fire("click");
  await app.els["da-save"].fire("click");
  assert.equal(seen.filter((s) => s[0] === "set_device_access").length, 0);
  assert.match(app.message(), /No setting was changed, so there is nothing to save/);
  assert.equal(app.els["da-editor"].hidden, false);
});

test("launch apps keeps view apps on, and view apps off turns launch off", async () => {
  const { app } = start();
  await settle();
  await named(app, 1, "Access").fire("click");
  app.els["da-launchapps"].checked = true;
  await app.els["da-launchapps"].fire("change");
  assert.equal(app.els["da-viewapps"].checked, true);
  app.els["da-viewapps"].checked = false;
  await app.els["da-viewapps"].fire("change");
  assert.equal(app.els["da-launchapps"].checked, false);
});

test("a refused save (400 from the agent) keeps the editor open with the reason", async () => {
  const { app } = start({ set_device_access: () => Promise.reject("The agent refused that change: jailRoot must resolve within the agent's configured roots") });
  await settle();
  await named(app, 1, "Access").fire("click");
  app.els["da-jail"].value = "/etc";
  await app.els["da-save"].fire("click");
  assert.match(app.message(), /The agent refused that change/);
  assert.ok(app.els.message.classList.contains("error"));
  assert.equal(app.els["da-editor"].hidden, false);
  assert.equal(app.els["da-save"].disabled, false);
});

test("changing this computer's own access needs a second press and shows the warning", async () => {
  const { app, seen } = start({ device_access: (a) => access({ id: a.id, label: "This PC", viaLogin: true }) });
  await settle();
  await named(app, 0, "Access").fire("click");
  assert.match(app.els["da-editor-hint"].textContent, /signed in with an account/);
  app.els["da-readonly"].checked = true;
  await app.els["da-save"].fire("click");
  assert.equal(seen.filter((s) => s[0] === "set_device_access").length, 0);
  assert.equal(app.els["da-editor-self"].hidden, false);
  assert.equal(app.els["da-save"].textContent, "Save access to this computer?");
  await app.els["da-save"].fire("click");
  assert.deepEqual(seen.at(-1), ["set_device_access", { id: "me", patch: { readOnly: true }, confirmSelf: true }]);
});

test("Cancel closes the editor and clears the message", async () => {
  const { app } = start();
  await settle();
  await named(app, 1, "Access").fire("click");
  await app.els["da-cancel"].fire("click");
  assert.equal(app.els["da-editor"].hidden, true);
  assert.equal(app.message(), "");
});

test("an open editor closes when its device disappears from the list", async () => {
  const { app, setList } = start();
  await settle();
  await named(app, 1, "Access").fire("click");
  assert.equal(app.els["da-editor"].hidden, false);
  setList([me]);
  await app.els.refresh.fire("click");
  assert.equal(app.els["da-editor"].hidden, true);
});

test("the action buttons carry the row's name, so they differ for a screen reader", async () => {
  const { app } = start();
  await settle();
  const labels = [0, 1].flatMap((i) => buttons(app, i).map((b) => b.attrs["aria-label"]));
  assert.equal(new Set(labels).size, labels.length);
  assert.ok(labels.every((l) => /Laptop|Phone|This PC/.test(l)));
});

test("a slow device list for the agent the user left never draws over the newer one", async () => {
  const slow = deferred();
  let calls = 0;
  const app = boot({
    saved_agent: SIGNED_IN,
    list_pins: [],
    list_devices: () => (calls++ === 0 ? slow.promise : [device({ id: "new", label: "Second agent PC", current: true })]),
  });
  await settle();
  app.els.refresh.fire("click");
  await settle();
  assert.equal(app.els.devices.children.length, 1);
  slow.resolve([me, phone]); // the first agent answers last
  await settle();
  assert.equal(app.els.devices.children.length, 1, "the older answer must be dropped");
  assert.match(app.els.devices.children[0].children[0].textContent, /Second agent PC/);
});
