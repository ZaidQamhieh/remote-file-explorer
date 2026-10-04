# Accessibility audit

Status 2026-10-04: the markup and behaviour that can be checked without assistive technology are
fixed and tested. **Not done:** a run with Orca, and a keyboard-only run through every flow in the real
window. Both need a display; the task (rfe-80r) stays open for them.

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

## Still to do on a real display

1. Keyboard only, no mouse, each flow to the end: connect, compare, sign in (account, code, approve on
   the PC), devices, refresh, sign out, Settings (every control), forget an agent, find agents.
2. Orca (GNOME): each screen is announced when it appears; errors interrupt; the match code is read
   digit by digit; the tables read as tables.
3. Look at the focus ring on every control in both themes, and at 200% scaling.

Record the result here, with the desktop environment and Orca version.
