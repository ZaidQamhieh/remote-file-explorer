# Accessibility audit

Status 2026-10-04: keyboard-only runs of every sign-in route and the main actions pass in the real
window (`e2e/keyboard.test.mjs`), and the AT-SPI tree, which is what Orca reads, was checked
(`e2e/a11y.test.mjs`). **Not done:** a run with Orca itself (it is not installed on the test machine,
and speech output was not heard), and a check at a true 200% display scale (see below).

## What was found and fixed

| Finding | Fix |
|---|---|
| After a screen change focus stayed on a control that had just been hidden, so a keyboard or screen reader user landed nowhere | The new screen's heading (`h2`, `tabindex="-1"`) takes focus and is read out |
| Errors and progress were both a polite `role="status"` | Errors are `role="alert"`; progress and results stay `status` |
| "Forget" and "Use" buttons were identical rows apart | Each has an `aria-label` naming its row; the armed "Forget?" says to press again to confirm |
| Table headers had no `scope`; the action column's header was empty | `scope="col"`, and the empty header has the visually hidden text "Action" |
| Form controls in the dark theme could keep light-theme defaults | `color-scheme: light dark` |

## What is checked automatically

`ui-tests/a11y.test.mjs` (also run in CI): the page language, unique ids, a label or `aria-label` on every
field, a name and a type on every button, no positive `tabindex`, scoped table headers, a focusable
heading on every screen, focus moving on a screen change, alert versus status, and the labels of
buttons built at run time. `ui-tests/theme.test.mjs`: text, secondary text, accent, error and success
colours reach 4.5:1 (WCAG AA) on both backgrounds in both themes.

## Already true from the structure

- One column, DOM order is reading order, so the tab order is the visual order. Nothing sets a positive
  `tabindex`.
- Every input has a visible `label`; hints are plain paragraphs.
- Focus rings are the browser's `:focus-visible` outline in the accent colour, 2px with an offset.
- Destructive actions (forget an agent, create a new device key) need a second press and say so in
  their text.
- The pairing match code is plain text with an `aria-label`.

## Keyboard audit, real window (2026-10-04, KWin virtual session, WebKitGTK)

Run by `e2e/keyboard.test.mjs`; the tests fail if a stop shows no focus outline.

- Tab order follows reading order on every screen. Header links come first (Settings, Files,
  Transfers, Sign out, Hosts), then the screen. Sign out was moved after Transfers so a destructive
  action is not between two navigation links.
- Connect: address, Check certificate, Find agents. Sign-in: username, password, Sign in, Back, pairing
  code, ask the PC to approve, new device key. Devices: Refresh, per-row Access / Revoke / Remove
  (named with the device), Apps, Health, Pairing, Audit, Requests. Settings: Forget, keystore test, log
  level, report, host actions, Add another host.
- Completed with the keyboard alone: connect and compare, sign in with an account, sign in with a pairing
  code, approve on the PC (including Cancel), sign out, Refresh, Find agents, open Settings, Forget
  (first press arms, the label says to press again), Revoke on the device's own row (arms, says so).
- Focus lands on the new screen's heading after every screen change.

## AT-SPI tree (what Orca speaks from), 2026-10-04

`e2e/a11y.test.mjs` reads the tree from a private accessibility bus. Found: a heading per screen, the
address field named "Agent address", buttons named by their text, device-row buttons named with the
device, the device list as a `table` with six `column header` nodes and a row of six cells. The text of
table cells is not exposed as nodes by WebKit, so the words themselves were not checked here.

## Layout at small sizes

The compositor's `--scale 2` did not change `window.devicePixelRatio` (it stays 1), so a 200% run of
`e2e/run.sh` is not a 200% run. The layout is checked instead at what 200% of a 1280x800 screen comes
to, 640x400 CSS pixels, and at 520 wide (the narrowest window): `e2e/small-window.test.mjs` fails if any
screen or table needs a sideways scroll. It found overflows in the device list, saved hosts and file
locations; they are fixed with wrapping rules under `@media (max-width: 700px)` in `style.css`.

## Still not done

1. Orca itself: each screen announced, errors interrupting, the match code read digit by digit.
2. A true 200% display scale (needs a real session; the remembered window size and the second-launch
   focus were also only partly driven: a second launch hands over and exits, covered by
   `e2e/window.test.mjs`; the saved size could not be driven because WebDriver's close ends the app
   without the close event).

Record the result here, with the desktop environment and Orca version.
