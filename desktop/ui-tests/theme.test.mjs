// The light and dark themes stay in step: every colour the light theme defines has a dark value,
// and the page tells the browser it supports both so form controls and scrollbars follow.
//
//   node --test desktop/ui-tests/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const css = readFileSync(new URL("../ui/style.css", import.meta.url), "utf8");

function vars(block) {
  return new Map([...block.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
}

const light = css.match(/:root\s*{([^}]*)}/)[1];
const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];

test("every light-theme colour has a different dark value", () => {
  const l = vars(light);
  const d = vars(dark);
  for (const [name, value] of l) {
    if (!/^#[0-9a-f]{3,8}$/i.test(value)) continue; // sizes such as --radius are shared
    assert.ok(d.has(name), `${name} has no dark value`);
    assert.notEqual(d.get(name), value, `${name} is the same in both themes`);
  }
});

test("the dark theme defines nothing the light theme lacks", () => {
  const l = vars(light);
  for (const name of vars(dark).keys()) assert.ok(l.has(name), `${name} only exists in dark`);
});

test("the page declares both colour schemes", () => {
  assert.match(light, /color-scheme:\s*light dark/);
});

test("text and background keep a readable contrast in both themes", () => {
  const lum = (hex) => {
    const n = parseInt(hex.slice(1), 16);
    const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  };
  const ratio = (a, b) => {
    const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
    return (x + 0.05) / (y + 0.05);
  };
  for (const [theme, block] of [["light", light], ["dark", dark]]) {
    const v = vars(block);
    // WCAG AA for body text is 4.5:1.
    for (const fg of ["--text", "--muted", "--danger", "--ok", "--accent"]) {
      for (const bg of ["--bg", "--surface"]) {
        const r = ratio(v.get(fg), v.get(bg));
        assert.ok(r >= 4.5, `${theme}: ${fg} on ${bg} is ${r.toFixed(2)}:1`);
      }
    }
    const r = ratio(v.get("--accent-text"), v.get("--accent"));
    assert.ok(r >= 4.5, `${theme}: button text on --accent is ${r.toFixed(2)}:1`);
  }
});
