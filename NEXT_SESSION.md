<!-- NEXT_SESSION_STATUS: HANDOFF -->
# NEXT_SESSION — cross-session handoff

Carryover for work **left unfinished** in a prior session. The `SessionStart`
hook (`.claude/hooks/next-session-guard.sh`) surfaces this file automatically at
the start of every session in this repo — but **only when the status marker on
line 1 reads `HANDOFF`**. When it reads `CLEAR`, there is nothing to resume and
the hook stays silent.

This is repo-local, incomplete-work carryover only. Durable project state,
architecture, and backlog live in the Obsidian wiki (`entities/rfe-backlog.md`),
not here.

## Contract (mirrored in `CLAUDE.md` §"Cross-session handoff")
- **Task finished this session** → set line 1 to `CLEAR` and reset
  `## Open handoff` to the "None" placeholder. Don't leave a resolved handoff to
  rot (that's what made the old version stale).
- **Task NOT finished** → set line 1 to `HANDOFF` and fill `## Open handoff`
  with: the goal, what's done, what's left, exact files/lines to start from, and
  how to verify. Write it so a cold session resumes with zero re-derivation.

---

## Open handoff

### GOAL: finish the RFE production-readiness audit remediation.

Full 85-finding audit lives in the wiki:
`concepts/rfe-production-readiness-audit-2026-07.md` — it has per-finding
**file:line + why + fix + example**. Read it before touching any finding below;
it is the source of truth.

### PROGRESS (as of 2026-07-19): 33 / 85 closed. No partials left.
- **Critical: 2/2 done** ✅ (PR-01 trash traversal, PR-02 settings authz).
- **High: 26/62 → 36 open.**
- **Medium: 5/17** (PR-43, 46, 48, 52, 85).
- **Low: 2/4** (PR-77, 78).

Closed: PR-01,02,03,04,05,06,07,08,09,10,11,12,13,20,41,42,43,44,45,46,47,48,50,
51,52,53,60,69,70,71,77,78,85.

**RECONCILED 2026-07-19:** the 07-15 handoff undercounted. Sessions 07-16→19 also
landed **PR-05, PR-06, PR-12, PR-42, PR-45, PR-46, PR-47, PR-70** (all in the
uncommitted `agent/**` tree, each with a regression test) but never updated this
file or the log. Verified green on the current dirty tree: gofmt/vet clean, 321
tests, govulncheck 0 reachable, redocly 0 errors. Read-only invariant confirmed
airtight across every mutating route. **COMMITTED 2026-07-19** on `master`:
`4e09ddf` (server: agent/protocol/.github/docs/hygiene, 47 files) + `9706ee2`
(android config PR-69/20/77, split out — not Go/OpenAPI-gated, wants a real
Android build). Frozen shad tree stayed staged & untouched. **Not pushed.**

**Prior batch 3 (2026-07-15): PR-03, PR-04 (finished), PR-50, PR-53 (finished).**
- **PR-03** — `adminOnly` middleware (`settings_handlers.go`) + an admin router
  group in `server.go` now gates `/metrics`, `/users`, `/users/{username}`,
  `/logs`, `/agent/restart`. `/transfers/list` scopes rows to the caller and
  withholds aggregates + device/user lists from non-admins (their filter params
  are ignored, not honoured). `DELETE /transfers/{id}` and share revoke/list are
  owner-scoped via `callerOwnsTransfer` / the new `callerOwnsShare`; non-owners
  get 404, never 403, so foreign IDs aren't confirmed. New `share_tokens.device_id`
  column records the minting device.
- **PR-04** — new `requireWritable` middleware wraps the three mutating transfer
  routes (open/chunk/complete) in `registerTransferRoutes`; the resumable-upload
  read-only bypass is closed. Honours the per-device flag via the context ops.
- **PR-50** — new `publish()` in `transfer.go`: `os.Link` (EEXIST = atomic
  conflict) with an `O_EXCL` copy fallback, replacing the Stat-then-rename TOCTOU.
  New `transfers.overwrite` column persists the session's flag so Complete
  re-checks it. `SetTransferStatus` errors are surfaced, not dropped.
- **PR-53** — all 38 `"INTERNAL", err.Error()` sinks → `writeInternal`; WOL's two
  raw OS-error sinks now log + return a stable code. Remaining `err.Error()` in
  responses are sentinel/validation text that echoes the caller's own input
  (`handleFsError`, hash mismatches) — reviewed, deliberately kept.

**Behaviour changes to know about (owner should sanity-check):**
1. The web companion allows a **pair-code** session, which is NOT admin. Such a
   session now gets 403 on Metrics/Users/Logs/Restart and a self-scoped
   Transfers page. `api()` surfaces this as "admin device required" text rather
   than crashing, so it degrades honestly — but if the web UI should hide those
   pages for non-admin sessions, that's an unmade UI decision. Login/register
   sessions (the normal path) are unaffected. The phone app calls none of these.
2. Legacy rows with no recorded owner (transfers, share links) are admin-only.
3. `transfers.overwrite` defaults to 0 for pre-migration rows, so a legacy
   session completing after upgrade conflicts rather than clobbering.

### HARD SCOPE RULES (do not break)
1. **Do NOT touch the frozen shad migration tree** — the ~39 uncommitted
   `app/lib/**` + specific `app/test/**` + `pubspec.*` files pending owner
   emulator sign-off. ~30 open Highs live there; they wait.
2. **Do NOT commit or push** without owner approval — owner gates on "show me on
   emulator first." Scope every commit with `git commit --only <paths>`; the
   index has pre-existing staged shad content that must not be swept in.
3. Fix root causes in the shared code path; add a regression test per security fix.

### VERIFY (must stay green — run from `agent/`) — all green as of this session
307 race tests pass (was 294; this batch added 13), govulncheck 0 reachable,
Redocly 0 errors, gofmt/vet clean.
`gofmt -l .` empty · `go vet ./...` · `go test -race ./...` ·
`go run golang.org/x/vuln/cmd/govulncheck@latest ./...` (0 reachable) ·
`npx @redocly/cli@latest lint protocol/openapi.yaml` (0 errors).

### DO NEXT — SAFE server-side / config items (no frozen-tree coupling)
PR-05,06,12,42,45,46,47,70 are DONE (see reconcile note above). What's left `[S]`:
- **PR-81** — adversarial Go route/security matrix test. Table-driven: every
  mutating route × read-only → assert 403. The invariant is already enforced +
  has per-handler read-only tests, so this is regression-armor, not a bug fix.
  Harness: handlers take `fsops.New(root, true)` for a read-only Ops; call
  directly (see `transferhandlers_test.go:373`). Zero risk, no owner decision.
- **PR-84** — CI coverage floors + platform assurance gates. `.github/workflows/ci.yml`.
- **PR-72** — refresh stale product/version docs (README/docs). pubspec desc is `[F]`.
- **PR-80** — repo hygiene: `.idea/` untracking is already staged (D); confirm
  `.gitignore` covers it, sweep stale comments.
- **PR-59** — SSE: remove-vs-complete is an OWNER DECISION — both directions touch
  the frozen client (`agent_client.dart`, `sse_listener.dart`). Do NOT do unilaterally.
- **PR-79** — split god files (LOW; defer until abstractions settle).

### COMPLETE OPEN-FINDINGS REGISTER (60 items open — nothing omitted)
Zone: `[S]`=safe server/CI (work now) · `[F]`=frozen client/app (needs emulator
sign-off) · `[D]`=deferred coupling. Titles are summaries; full file:line + fix
in the audit note. `*`=partially done, finish the rest.

HIGH (36 open) — PR-05,06,12,42,45,47,70 now CLOSED (2026-07-19), removed below:
- PR-14 [F] — QR handoff filename local path traversal
- PR-15 [F] — photo-backup remote paths accept unsafe segments
- PR-16 [F] — cross-host image caches leak data (key missing hostId/version)
- PR-17 [F] — portable backup exports the private device identity key
- PR-18 [F] — app lock fails OPEN on startup / unavailable auth
- PR-19 [F] — recent-app task thumbnails retain sensitive content
- PR-21 [F] — backup restore is destructive and non-atomic
- PR-22 [F] — backup import: resource abuse + weak offline passphrase
- PR-23 [F] — address fallback replays non-idempotent POST/PATCH/PUT/DELETE
- PR-24 [F] — downloads resume arbitrary files, no digest/range integrity
- PR-25 [F] — update downloads race across isolates, size-only verify (+release.yml)
- PR-26 [F] — Android loopback video likely violates cleartext policy (+manifest)
- PR-27 [F] — loopback video endpoint exposes the playing file to local apps
- PR-28 [F] — preview loaders trust metadata instead of byte limits (OOM)
- PR-29 [F] — offline pinning has no aggregate quota / safe eviction
- PR-30 [F] — photo-backup completion not durable, manual-only, serial delay
- PR-31 [F] — sync silently creates incomplete/stale replicas, raw paths
- PR-32 [F] — search "regex" is fake glob; stale-request guards incomplete
- PR-33 [F] — duplicate finder misses pages, hashes at maximum cost
- PR-34 [F] — explorer/destination-picker ABA stale-response races
- PR-35 [F] — batch mutations lose/strand user data, no rollback
- PR-36 [F] — host-card widget identity + client lifetime unsafe (no ValueKey)
- PR-37 [F] — pairing persistence non-transactional (host/token/fingerprint split)
- PR-38 [F] — text edits made during save are falsely marked saved
- PR-39 [F] — media pager autoplays neighbors, leaks async resources
- PR-40 [F] — iOS scaffold missing camera/photo/local-network privacy strings
- PR-56 [F] — offline fallback masks 401/403/404/TLS-pin failures (agent_client.dart:1119)
- PR-57 [F] — native save cancellation reported as success, staging deleted
- PR-59 [S] — SSE half-finished (server never emits) + unsafe client parser
- PR-61 [D] — unauth /health leaks topology; any device sends WoL; 443 binds all
- PR-62 [F] — shad root removes ScaffoldMessenger (feedback no-ops/throws)
- PR-64 [F] — disabled photo ShadSwitch keyboard-crash; settings a11y regress
- PR-66 [F] — remote path manipulation duplicated + Windows-incorrect
- PR-68 [F] — hard-coded strings bypass localization; missing a11y semantics
- PR-73 [F] — flutter_markdown discontinued; 66 pkgs stale; Gradle/AGP/Kotlin (pubspec+gradle)
- PR-74 [F] — temp preview/share files collide + retain sensitive content
- PR-81 [S] — Go security invariants lack adversarial route/matrix coverage
- PR-82 [F] — core Flutter networking/workflows barely integration-tested

MEDIUM (12 open) — PR-46 now CLOSED (2026-07-19):
- PR-49 [F] — listing cache rewrites one large JSON blob per host, races
- PR-54 [F] — one malformed persisted JSON bricks whole app areas
- PR-55 [F] — device identity generation is race/corruption-prone
- PR-58 [F] — queue persistence writes can reorder stale snapshots
- PR-63 [F] — shad theme ignores dynamic/accent/AMOLED appearance
- PR-65 [F] — reduced-motion preference does not reduce motion
- PR-67 [F] — CSV preview knowingly incorrect + eagerly expensive
- PR-72 [S] — product/version docs stale/misleading (README/docs; pubspec desc is [F])
- PR-75 [D] — Android FileProvider exposes overly broad roots
- PR-76 [S] — native save + notification permission lifecycle fragile (MainActivity.kt)
- PR-83 [F] — several tests assert implementation/fake behavior
- PR-84 [S] — coverage floors + platform assurance not gated in CI

LOW (2 open):
- PR-79 [S] — nine god files combine unrelated responsibilities (split AFTER abstractions)
- PR-80 [S] — repo hygiene: tracked .idea/ files, stale/misleading comments

### DEFERRED (coupling — needs owner decision, do NOT change unilaterally)
- **PR-61** — minimal unauth `/health` + WoL admin-gate: the shipped app reads
  `/health` unauthenticated for address/MAC and sends WoL from the non-admin
  phone. Changing either breaks the live client.
- **PR-75** — FileProvider narrowing: needs Dart update/share paths in the frozen
  tree.

### FROZEN until emulator sign-off (client Highs — ~30)
PR-14,15,16,17,18,19,21–40, 56,57,62,64,66,68,73,74,82 — all `app/lib/**` or
shad UI or `pubspec`. See the audit note per finding.

### COMMITTED 2026-07-19 (was the uncommitted fix-session work)
Landed on `master` as `4e09ddf` (server) + `9706ee2` (android). PR-46 replaced
the ad-hoc migration chain with `PRAGMA user_version` versioning. Android config
(gradle signing PR-69, manifest PR-20/77) is committed but **not build-verified** —
confirm with a real Android release build. Neither commit is **pushed**.
- **NOTE PR-46 note below is now historical** — the versioned migration shipped.

**The batch also changed the DB schema** (additive `ALTER TABLE`s:
`share_tokens.device_id`, `transfers.overwrite`, both `DEFAULT` + guarded by the
existing duplicate-column check). Migration is still the ad-hoc non-versioned
chain PR-46 flags — these follow the established pattern rather than fixing it.
