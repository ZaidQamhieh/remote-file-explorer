// Finding agents on the network: it fills in the address and nothing else. Same fake DOM as the
// other UI tests.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { boot, settle, deferred, SIGNED_OUT } from "./harness.mjs";

const FOUND = [
  { name: "office-pc", hostport: "192.168.1.20:8765", otherAddresses: [], version: "1.43.0", known: false },
  { name: "laptop", hostport: "10.0.0.7:8765", otherAddresses: [], version: "1.42.7", known: true },
];
const base = (more = {}) => ({ saved_agent: SIGNED_OUT, list_pins: [], ...more });

// Everything that could send a credential or trust a certificate.
const RISKY = ["probe_agent", "login", "pair_with_code", "request_pairing", "poll_pairing"];

test("found agents are listed with their name, address and version; a trusted one says so", async () => {
  const app = boot(base({ discover_agents: FOUND }));
  await settle();
  await app.els.discover.fire("click");
  assert.equal(app.els.found.children.length, 2);
  assert.equal(app.els["found-wrap"].hidden, false);
  const row = (i) => app.els.found.children[i].children.map((c) => c.textContent);
  assert.deepEqual(row(0).slice(0, 3), ["office-pc", "192.168.1.20:8765", "1.43.0"]);
  assert.match(row(1)[1], /\(trusted before\)/);
  assert.equal(app.els["discover-status"].textContent, "2 agents found.");
});

test("choosing one only fills in the address: no probe, no sign-in, same screen", async () => {
  const app = boot(base({ discover_agents: FOUND }));
  await settle();
  await app.els.discover.fire("click");
  const use = app.els.found.children[0].children[3].children[0];
  await use.fire("click");
  assert.equal(app.els.host.value, "192.168.1.20:8765");
  assert.deepEqual(app.screen(), ["step-connect"]);
  assert.match(app.message(), /compare the fingerprint/);
  for (const name of RISKY) assert.ok(!app.calls.includes(name), `${name} was called`);
});

test("the fingerprint step is still the only way forward from a filled-in address", async () => {
  const app = boot(
    base({
      discover_agents: FOUND,
      probe_agent: { fingerprint: "cd".repeat(32), previous: "", changed: false },
    })
  );
  await settle();
  await app.els.discover.fire("click");
  await app.els.found.children[0].children[3].children[0].fire("click");
  await app.els["connect-form"].fire("submit");
  assert.deepEqual(app.screen(), ["step-trust"], "the trust screen comes before any sign-in");
  assert.ok(!app.calls.includes("login") && !app.calls.includes("pair_with_code"));
  assert.equal(app.els.fingerprint.textContent, "cd".repeat(32));
});

test("nothing found: says so and points at typing the address", async () => {
  const app = boot(base({ discover_agents: [] }));
  await settle();
  await app.els.discover.fire("click");
  assert.equal(app.els["found-wrap"].hidden, true);
  assert.match(app.els["discover-status"].textContent, /No agents found.*type the address/);
});

test("slow search: a busy line and a disabled button, then the list", async () => {
  const gate = deferred();
  const app = boot(base({ discover_agents: () => gate.promise }));
  await settle();
  const pressed = app.els.discover.fire("click");
  await settle();
  assert.match(app.message(), /Looking for agents/);
  assert.equal(app.els.discover.disabled, true);
  gate.resolve(FOUND);
  await pressed;
  await settle();
  assert.equal(app.message(), "");
  assert.equal(app.els.discover.disabled, false);
  assert.equal(app.els.found.children.length, 2);
});

test("discovery failing shows the reason and leaves the manual address box working", async () => {
  const app = boot(
    base({ discover_agents: () => Promise.reject("cannot start network discovery: no interface") })
  );
  await settle();
  await app.els.discover.fire("click");
  assert.match(app.message(), /cannot start network discovery/);
  assert.equal(app.els["found-wrap"].hidden, true);
  assert.equal(app.els["connect-form"].disabled, false);
  assert.deepEqual(app.screen(), ["step-connect"]);
});

test("text from the network is shown as text, never as markup", async () => {
  const evil = { name: "<img src=x onerror=alert(1)>", hostport: "10.0.0.9:8765", otherAddresses: [], version: "<b>1</b>", known: false };
  const app = boot(base({ discover_agents: [evil] }));
  await settle();
  await app.els.discover.fire("click");
  const cells = app.els.found.children[0].children;
  assert.equal(cells[0].textContent, evil.name);
  assert.equal(cells[0].innerHTML, undefined, "no HTML is ever assigned");
});
