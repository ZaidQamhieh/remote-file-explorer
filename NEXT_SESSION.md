# NEXT_SESSION — start here

_Handoff written 2026-06-13. Read this first, then `CLAUDE.md`._

## What happened last session

Planned future work and developer/automation infrastructure. **No code changed; three
new docs/files were created, all untracked (not committed):**

1. **`CLAUDE.md`** (repo root) — the repo guide for Claude: commands, hard constraints
   (Impeller off, Riverpod 2.x, OpenAPI-in-same-commit), conventions, and the
   token-discipline workflow. Facts verified against the real repo. **Read it first.**
2. **`docs/next-waves-addendum.md`** — net-new feature waves. **Wave 0 (settings
   architecture: app-wide defaults + per-device overrides — owner-requested, DO FIRST)**
   through Wave T. 56 features, each with effort/impact/why-it's-a-gap.
3. **`docs/dev-experience-and-automation.md`** — 6-track plan to cut token cost &
   automate. `CLAUDE.md` was step 1 of it.

Reading copies of docs #2 and #3 also live in `~/Desktop/NEXT WAVE/`.

## Do first this session

1. **Commit the three untracked files** (one `docs:`/`chore:` commit is fine):
   `CLAUDE.md`, `docs/next-waves-addendum.md`, `docs/dev-experience-and-automation.md`.
   We're on branch `master`; CI runs on push.

## Then pick one (in priority order)

- **Wave 0 — settings architecture** (`next-waves-addendum.md`). Owner's explicit
  priority. Two-tier model: app defaults + opt-in per-device overrides, a
  `SettingsResolver`, migration that collapses matching per-host values. Foundational —
  later settings waves depend on it.
- **Dev-experience Track 2 — codegen** (`dev-experience-and-automation.md`): OpenAPI →
  Dart models + `freezed`/`json_serializable`. Biggest *ongoing* token saver. Must
  respect the Riverpod 2.x pin (model codegen only unless `riverpod_generator` is
  confirmed compatible).
- **Dev-experience Track 3 — pre-commit hook**: `dart format` + `flutter analyze` +
  `go vet` on staged files. Cheap; converts paid CI failures into free local ones.

## Owner's standing preferences (from this session)

- Cares about **token cost** — lean on free CI, run only affected tests locally, don't
  dispatch sub-agents for small diffs. (Codified in `CLAUDE.md`.)
- Wanted **app-wide settings** instead of everything being per-PC — that's Wave 0.
- Arabic-first (Birzeit); RTL/localization is Wave O and genuinely wanted.

## Suggested first words to the user

"I read NEXT_SESSION and CLAUDE.md. Want me to commit the three planning files first,
then start Wave 0 (settings architecture)?"
