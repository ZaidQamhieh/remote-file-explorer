// A minimal fake DOM built from desktop/ui/index.html, and a way to run desktop/ui/app.js against
// it with `invoke` answered by the test. Checks behaviour (which screen, which message), not looks.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const ui = new URL("../ui/", import.meta.url);
const html = readFileSync(new URL("index.html", ui), "utf8");
const source = readFileSync(new URL("app.js", ui), "utf8");

export class El {
  constructor(tag = "div", attrs = {}) {
    this.tag = tag;
    this.id = attrs.id || "";
    this.hidden = "hidden" in attrs;
    this.value = attrs.value || "";
    this.textContent = "";
    this.disabled = false;
    this.dataset = {};
    this.children = [];
    this.listeners = {};
    // className and classList are one thing in a real DOM.
    this.names = new Set((attrs.class || "").split(/\s+/).filter(Boolean));
    this.classList = {
      toggle: (n, on) => {
        on ? this.names.add(n) : this.names.delete(n);
      },
      contains: (n) => this.names.has(n),
    };
  }
  get className() {
    return [...this.names].join(" ");
  }
  set className(v) {
    this.names = new Set(String(v).split(/\s+/).filter(Boolean));
  }
  addEventListener(type, fn) {
    (this.listeners[type] ||= []).push(fn);
  }
  append(...kids) {
    this.children.push(...kids);
  }
  replaceChildren(...kids) {
    this.children = kids;
  }
  focus() {}
  select() {}
  querySelector() {
    return this;
  }
  async fire(type) {
    const ev = { target: this, currentTarget: this, submitter: this, preventDefault() {} };
    for (const fn of this.listeners[type] || []) fn(ev);
    await settle();
  }
}

export const settle = async () => {
  for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r));
  await new Promise((r) => setTimeout(r, 5)); // the polling loop's (shortened) wait
  for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r));
};

// An invoke() the test controls: answers come from `handlers`, or from a promise it holds open.
export function boot(handlers, extra = {}) {
  const els = {};
  for (const m of html.matchAll(/<(\w+)([^>]*\bid="([^"]+)"[^>]*)>/g)) {
    const attrs = { id: m[3] };
    if (/\bhidden\b/.test(m[2])) attrs.hidden = "";
    const v = m[2].match(/\bvalue="([^"]*)"/);
    if (v) attrs.value = v[1];
    const c = m[2].match(/\bclass="([^"]*)"/);
    if (c) attrs.class = c[1];
    els[m[3]] = new El(m[1], attrs);
  }
  const calls = [];
  const invoke = (name, args) => {
    calls.push(name);
    const h = handlers[name];
    if (!h) return Promise.reject(`unexpected command ${name}`);
    return Promise.resolve().then(() => (typeof h === "function" ? h(args) : h));
  };
  const ctx = {
    window: { __TAURI__: { core: { invoke } } },
    document: {
      getElementById: (id) => els[id] || assert.fail(`no element #${id}`),
      createElement: (tag) => new El(tag),
    },
    setTimeout: (fn) => setTimeout(fn, 0),
    ...extra,
    // keep the polling loop's two-second wait out of the test
  };
  vm.runInNewContext(source, ctx);
  const screen = () => ["step-connect", "step-trust", "step-login", "step-approve", "step-devices", "step-settings"].filter((s) => !els[s].hidden);
  return { els, calls, screen, message: () => (els.message.hidden ? "" : els.message.textContent) };
}

export const deferred = () => {
  let resolve, reject;
  const promise = new Promise((a, b) => ((resolve = a), (reject = b)));
  return { promise, resolve, reject };
};

export const SIGNED_OUT = { host: "pc:8765", fingerprint: "", signedIn: false, username: "" };
export const SIGNED_IN = { host: "pc:8765", fingerprint: "ab".repeat(32), signedIn: true, username: "zaid" };
