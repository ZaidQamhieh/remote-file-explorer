# Developer Experience & Automation Plan — Remote File Explorer

**Status: PLANNED, NOT STARTED.** Written 2026-06-13. Companion to
`next-waves-addendum.md`, `feature-roadmap.md`, and `FUTURE_FEATURES.md`.

This doc is **not features.** It's the meta-work that makes the app cheaper and
faster for an AI agent (Claude) to develop — less token spend, more automation,
fewer failed-CI round-trips. "Impact" below = **dev velocity / token savings**,
not user value.

## The four token sinks this project actually has

1. **Re-learning the repo every session** — re-grepping file layout, conventions,
   the Impeller/Riverpod gotchas. Pure repeated read cost.
2. **Hand-syncing two sides of one contract** — Dart client models + Go handlers
   against `protocol/openapi.yaml`, by hand. The spec drifted once already.
   Writing/reading serialization boilerplate is high-token and error-prone.
3. **Running the 226-test suite up to 3×** per change (local + sub-agent + CI),
   when only CI is free.
4. **Iterative print-debug loops** on the agent — add a print, rebuild, read,
   repeat. Each cycle is a full tool round-trip.

Everything below is sequenced to kill those four.

---

## Track 1 — Context: stop re-learning the repo (biggest immediate win)

**Impact ★★★ · Effort S · pays back every single session.**

| # | Item | Why it saves tokens |
|---|---|---|
| 1.1 | **Repo `CLAUDE.md`** at root: build/test/release commands, the hard constraints (Impeller OFF, Riverpod pinned 2.6.1, Android-first), the invariants (OpenAPI contract in the same commit; no direct client calls from widgets; use `formatSize` not local dupes), and the workflow (feat-then-fix commits, when to dispatch sub-agents). | I currently re-derive all of this by reading code + memory each session. One file read replaces dozens of grep/read calls. **Single highest-leverage item in this doc.** |
| 1.2 | **Living code map** — keep `architecture.md` as a file→responsibility table + module-boundary diagram, updated when structure changes (e.g. after UI Wave A's explorer split). | Lets me jump straight to the right file instead of fan-out searching. |
| 1.3 | **`WAVE_RUNBOOK.md`** — the dispatch template: how a wave is scoped, the analyze+test gate, the commit/push/CI loop, the release call. | Makes orchestration mechanical instead of re-reasoned each wave. |

## Track 2 — One source of truth via codegen (biggest structural win)

**Impact ★★★ · Effort M · kills sink #2 permanently.**

| # | Item | Why it saves tokens |
|---|---|---|
| 2.1 | **Generate from `openapi.yaml`** — Dart client models (and ideally Go types/handler stubs) generated, not hand-written. | Stops me hand-writing + hand-reading parallel model classes on both sides. The contract becomes the only thing to edit; drift becomes impossible by construction. |
| 2.2 | **`freezed` + `json_serializable`** for Dart models. | Eliminates hand-written `fromJson`/`toJson`/`copyWith`/equality — the single most token-heavy, mechanical boilerplate in a Flutter app. `build_runner` regenerates it for free. |
| 2.3 | **Contract tests app↔agent** generated/derived from the spec (or a spec-driven mock). | Drift is caught by a failing test (free, in CI) instead of by me reading both sides to spot the mismatch. |

> Note: `build_runner` codegen must respect the **Riverpod 2.6.1 pin** — use
> `freezed`/`json_serializable` (model codegen, version-safe); only add
> `riverpod_generator` if it's confirmed compatible with the pinned Notifier API.

## Track 3 — Catch errors locally & free, before a round-trip

**Impact ★★ · Effort S · turns paid failures into free ones.**

| # | Item | Why it saves tokens |
|---|---|---|
| 3.1 | **Pre-commit hook** — `dart format`, `flutter analyze`, `go vet` on **staged files only**. | A formatting/analyze error caught here costs zero tokens; the same error caught by CI costs a push, a log read, and a fix cycle. |
| 3.2 | **Stricter lints** (e.g. `very_good_analysis`) + **`custom_lint` rules** encoding the architecture invariants: "no `AgentClient` calls from widgets", "no local `_formatSize`", "category icons via `EntryLeading`". | Moves convention enforcement from code-review (my tokens) to analyze-time (free). The Wave A/C acceptance criteria become machine-checked. |
| 3.3 | **`dart format --set-exit-if-changed`** + analyze as required CI gates. | Makes "is it clean" a binary I never have to eyeball. |

## Track 4 — Test & verify cheaply (kill the 3× suite + manual verify)

**Impact ★★ · Effort S–M.**

| # | Item | Why it saves tokens |
|---|---|---|
| 4.1 | **`scripts/test-affected.sh`** — map changed files → their test files, run only those locally; trust CI for the full green. | Codifies the policy already in `PROGRESS.md`. Turns a multi-minute full run into seconds, and removes the temptation to re-run everything. |
| 4.2 | **Fake / in-memory agent + seed fixtures** — run the app and integration tests against a local fake `AgentClient` with no real PC. | Removes the biggest *manual* verification cost: today checking real behavior needs a paired host. A fake agent makes flows testable headlessly. |
| 4.3 | **Coverage report in CI** (artifact or summary). | Tells me exactly where tests are missing so I write the right test once, not exploratory ones. |
| 4.4 | **Golden/widget harness** for the stable, non-blur surfaces only. | Catches visual regressions automatically (Skia-safe components only — Impeller is off, goldens of shader-heavy widgets would be flaky). |

## Track 5 — Automate build / release / debug (move work to free cloud)

**Impact ★★★ · Effort S–M · overlaps `FUTURE_FEATURES.md` #1–#2 — that doc owns the feature spec; here is the dev-velocity rationale.**

| # | Item | Why it saves tokens |
|---|---|---|
| 5.1 | **CD job** (`FUTURE_FEATURES.md` #1) — tag `v*` → build APK on a GitHub runner → GitHub Release + `latest.json`. | Removes the local `release.sh` Gradle build (~60s + 77 MB artifact) from the session entirely. The full suite + build run only on free runners. |
| 5.2 | **CI caching** — cache Flutter SDK, Gradle, and Go module/build caches. | Faster green = less time I sit waiting before the next step; cheaper iteration. |
| 5.3 | **Structured agent logging + `--dev` verbose mode + log export** (pairs with addendum N3). | Kills sink #4: diagnose from a log dump instead of an add-print → rebuild → read loop. One read replaces N round-trips. |
| 5.4 | **Branch protection / required checks** — analyze + tests must pass before merge. | Stops a bad push sitting on master, which otherwise becomes a debug-the-regression session later. |
| 5.5 | **Conventional commits → auto-changelog** (feeds addendum O3 changelog viewer). | Removes hand-writing release notes each release. |

## Track 6 — Codify the token-discipline policy (the meta-lever)

**Impact ★★★ · Effort S · this is mostly writing rules down so every session follows them.**

Put these in the repo `CLAUDE.md` (Track 1.1) so they bind every session, not
just the ones that remember:

- **Run affected tests only locally; trust CI for the full suite.** Never run the
  226-suite three times for one change.
- **Don't dispatch review/fix sub-agents for small diffs** — do them inline. A
  sub-agent re-reads context from cold; reserve it for genuinely large, parallel
  waves with disjoint file ownership.
- **One `feat:` + one `fix:` commit per wave**, push, let CI confirm green.
- **Edit the OpenAPI contract in the same commit** as any agent change.
- **Don't re-read a file you just edited to verify** — the tooling already
  confirms the write.

---

## Priority (do in this order)

1. **Track 1.1 — repo `CLAUDE.md`** + **Track 6** (write the policy into it). One
   small file, pays back immediately and every session. Do this first, today.
2. **Track 2 (codegen + freezed/json_serializable)** — the structural fix for the
   contract-drift + boilerplate sink. Highest *ongoing* token savings.
3. **Track 3 (pre-commit + lints)** — cheap, converts paid CI failures to free
   local ones.
4. **Track 5.1 (CD job)** — already half-specified in `FUTURE_FEATURES.md`;
   removes local builds from the loop.
5. **Track 4 (affected-tests script, fake agent)** then the rest of 5 and the
   golden harness.

**If only one thing ships: the repo `CLAUDE.md` (Track 1.1 + 6).** It's an
afternoon of work and it cuts the per-session "re-learn the repo" tax forever,
which is the tax I pay most often.
