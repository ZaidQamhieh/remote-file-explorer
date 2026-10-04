// A small WebDriver client for the real app, and a throwaway agent to talk to.

import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import net from "node:net";

const DRIVER = "http://127.0.0.1:4444";
export const KEYS = { tab: "", enter: "", shiftTab: "", space: "" };

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function call(method, path, body) {
  const r = await fetch(DRIVER + path, {
    method,
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const j = await r.json();
  if (j.value && j.value.error) throw new Error(`${method} ${path}: ${j.value.error}: ${j.value.message}`);
  return j.value;
}

export async function waitFor(what, fn, timeout = 15000) {
  const end = Date.now() + timeout;
  let last;
  while (Date.now() < end) {
    try {
      const v = await fn();
      if (v) return v;
    } catch (e) {
      last = e;
    }
    await sleep(100);
  }
  throw new Error(`timed out waiting for ${what}${last ? ` (${last.message})` : ""}`);
}

export class App {
  static async start() {
    const caps = { alwaysMatch: { "tauri:options": { application: process.env.RFE_DESKTOP_BIN } } };
    const v = await call("POST", "/session", { capabilities: caps });
    const app = new App(v.sessionId);
    await waitFor("the window", () => app.visible("#step-connect"));
    return app;
  }

  constructor(id) {
    this.id = id;
  }

  req(method, path, body) {
    return call(method, `/session/${this.id}${path}`, body);
  }

  async find(css) {
    const el = await this.req("POST", "/element", { using: "css selector", value: css });
    return Object.values(el)[0];
  }

  async visible(css) {
    return this.script("const e = document.querySelector(arguments[0]); return !!e && !e.hidden && e.offsetParent !== null;", [css]);
  }

  script(code, args = []) {
    return this.req("POST", "/execute/sync", { script: code, args });
  }

  async text(css) {
    return this.req("GET", `/element/${await this.find(css)}/text`);
  }

  async value(css) {
    return this.script("return document.querySelector(arguments[0]).value;", [css]);
  }

  async click(css) {
    // Like a person: wait until it is there and enabled, scroll to it, and press it again if the
    // screen was still changing under the pointer.
    await waitFor(`${css} to be pressed`, async () => {
      const ready = await this.script(
        "const e = document.querySelector(arguments[0]); if (!e || e.disabled || e.hidden || e.offsetParent === null) return false; e.scrollIntoView({ block: 'center' }); return true;",
        [css]
      );
      if (!ready) return false;
      try {
        await this.req("POST", `/element/${await this.find(css)}/click`, {});
        return true;
      } catch (e) {
        if (/not interactable|stale element|intercepted/.test(e.message)) return false;
        throw e;
      }
    });
  }

  /** Replaces the contents of a field by typing, as a user does. */
  async fill(css, text) {
    const id = await this.find(css);
    await this.req("POST", `/element/${id}/clear`, {});
    await this.req("POST", `/element/${id}/value`, { text });
  }

  /** Sends keys to whatever has focus (Tab, Enter, text). */
  async press(keys) {
    const actions = [];
    for (const ch of keys) actions.push({ type: "keyDown", value: ch }, { type: "keyUp", value: ch });
    await this.req("POST", "/actions", { actions: [{ type: "key", id: "kbd", actions }] });
  }

  async focused() {
    return this.script("const a = document.activeElement; return a ? (a.id || a.tagName) : null;");
  }

  async rows(css) {
    return this.script("return document.querySelectorAll(arguments[0]).length;", [css]);
  }

  async shot(file) {
    const b64 = await this.req("GET", "/screenshot");
    const png = Buffer.from(b64, "base64");
    if (file && process.env.E2E_SHOTS) writeFileSync(join(process.env.E2E_SHOTS, file), png);
    return png;
  }

  async rect() {
    return this.req("GET", "/window/rect");
  }

  async setRect(r) {
    return this.req("POST", "/window/rect", r);
  }

  async end() {
    try {
      await this.req("DELETE", "");
    } catch {
      /* the window may already be gone */
    }
  }
}

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
    s.on("error", reject);
  });
}

function agentCli(args) {
  return execFileSync(process.env.RFE_AGENT_BIN, args, { encoding: "utf8" });
}

/** A throwaway agent on a random port with its own data, and one account. */
export class Agent {
  static async start(user = "owner", password = "e2e-password") {
    const port = await freePort();
    const data = mkdtempSync(join(tmpdir(), "rfe-e2e-agent-"));
    const roots = mkdtempSync(join(tmpdir(), "rfe-e2e-roots-"));
    const host = `127.0.0.1:${port}`;
    const child = spawn(
      process.env.RFE_AGENT_BIN,
      ["-addr", host, "-name", "rfe-e2e", "-data", data, "-roots", roots],
      // No notify-send and no session bus: pairing requests never reach a real desktop.
      { env: { PATH: "/nonexistent-rfe-test-path" }, stdio: "ignore" }
    );
    const agent = new Agent(child, host, data, roots, user, password);
    await waitFor("the agent", () => new Promise((ok) => net.connect(port, "127.0.0.1").on("connect", function () { this.end(); ok(true); }).on("error", () => ok(false))));
    agentCli(["adduser", "-password", password, "-data", data, user]);
    return agent;
  }

  constructor(child, host, data, roots, user, password) {
    Object.assign(this, { child, host, data, roots, user, password });
  }

  fingerprint() {
    const line = agentCli(["status", "-data", this.data]).split("\n").find((l) => l.startsWith("fingerprint:"));
    return line.replace("fingerprint:", "").replace(/[^0-9a-fA-F]/g, "").toLowerCase();
  }

  devices() {
    return agentCli(["devices", "-data", this.data]);
  }

  /** A fresh one-time pairing code, as `rfe-agent pair` prints it on its first line. */
  pairCode() {
    const first = agentCli(["pair", "-data", this.data]).split("\n")[0];
    const m = first.match(/^Pairing code:\s*(\S+)/);
    if (!m) throw new Error(`unexpected pair output: ${first}`);
    return m[1];
  }

  /** `rfe-agent pair requests`: the waiting approve-on-PC requests. */
  pairRequests() {
    return agentCli(["pair", "requests", "-data", this.data]);
  }

  /** What the owner does on the PC: "accept" or "reject" the waiting request with this id. */
  answerPairRequest(verb, id) {
    return agentCli(["pair", verb, "-data", this.data, id]);
  }

  /** The id of the waiting request that shows this match code. */
  pairRequestId(matchCode) {
    const line = this.pairRequests().split("\n").find((l) => l.includes(matchCode));
    if (!line) throw new Error(`no waiting request with match code ${matchCode}`);
    return line.trim().split(/\s+/)[0];
  }

  revoke(id) {
    return agentCli(["revoke", "-data", this.data, id]);
  }

  stop() {
    this.child.kill();
    rmSync(this.data, { recursive: true, force: true });
    rmSync(this.roots, { recursive: true, force: true });
  }
}

/** Forgets what the app saved, so the next test starts as a first run. */
export function resetAppState() {
  const dir = process.env.E2E_APP_DATA;
  rmSync(join(dir, "state.json"), { force: true });
  mkdirSync(dir, { recursive: true });
}
