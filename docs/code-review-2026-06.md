# Code Review — Remote File Explorer (2026-06-16)

Full-project review of the Go host agent (~9.5K LOC) and Flutter app (~18.6K
LOC). Reviewed against a clean static baseline and the project's own knowledge
graph (`graphify-out/`, god nodes used to target hotspots).

## Headline: the codebase is healthy

| Check | Result |
|-------|--------|
| `gofmt -l` | 0 unformatted files |
| `go vet ./...` | clean |
| `go test ./...` | all pass |
| `dart analyze` | No issues found |
| `TODO`/`FIXME`/`HACK` markers | 0 |
| Dart test files | 48 |

There are **no correctness bugs or lint failures to fix**. The work here is
about *maintainability and safety margin*: isolating the security boundary,
closing test-coverage gaps in security-critical code, and breaking up a few
god files. Documentation in the reviewed files (`fsops.go`, `pairing.go`,
`tls.go`) is genuinely excellent — keep that standard.

---

## Done in this pass (applied + verified)

1. **Isolated the agent's security boundary.** `fsops.go` (818 lines) mixed the
   path-jail (`Resolve`/`resolveReal`/`isUnder`) and access-control model
   (read-only / per-device jail `SettingsView` wrappers) with ordinary file
   CRUD. Extracted all of it into `agent/internal/fsops/jail.go` (pure
   code-move, same package). `fsops.go` is now ~560 lines and the trust
   boundary is auditable in one file. Verified: `go build`/`vet`/`test` green.

2. **Closed the two most dangerous test gaps.** `security` (TLS identity) and
   `pairing` (device auth) had **0% coverage** — the most security-sensitive
   packages in the agent were entirely unverified.
   - `internal/security/tls_test.go` → **78%** (cert generation, key perms
     0600, idempotent load, fingerprint format, cert properties).
   - `internal/pairing/pairing_test.go` → **85%** (code alphabet/length,
     TTL fallback, single-use consume, uniqueness, payload JSON).

3. **Fixed comment drift** in `tls.go`: the SAN comment claimed a Tailscale DNS
   name that isn't actually in the cert. Corrected to describe what the SANs
   really cover and why pinning makes the DNS name unnecessary.

### Coverage after this pass

| Package | Before | After |
|---------|-------:|------:|
| `security` | 0.0% | **78.0%** |
| `pairing` | 0.0% | **85.0%** |
| `settings` | 86.3% | 86.3% |
| `store` | 80.9% | 80.9% |
| `updates` | 73.9% | 73.9% |
| `fsops` | 72.8% | 72.8% |
| `transfer` | 71.2% | 71.2% |
| `server` | 46.5% | 46.5% |

---

## Recommended next (not applied — higher risk / your call)

### P1 — Test gaps still open
- **`cmd/agent` (0%)** — the CLI entrypoint (`runServe`, admin subcommands).
  The 123-line `runServe` is hard to test as-is; see refactor below.
- **`server` is only 46.5%** — the HTTP layer is the largest attack surface.
  Worth raising the floor, especially error/forbidden paths.
- `netinfo`, `thumbs` (0%) — lower priority (best-effort, platform-dependent).

### P1 — Break up the Dart god-classes (mechanical, low-risk)
`agent_client.dart` is a 966-line god-class with ~40 methods spanning health,
pairing, listing, search, settings, devices, CRUD, trash, archive, thumbnails,
transfers, and releases. **Split by domain using Dart extensions** — pure code
movement, no call-site changes, analyzer-verified:
```
agent_client.dart            // class + _dio + _get/_post/_patch/_delete core
agent_client.transfers.dart  // extension TransferApi on AgentClient
agent_client.trash.dart      // extension TrashApi on AgentClient
agent_client.archive.dart    // extension ArchiveApi on AgentClient
agent_client.admin.dart      // extension AdminApi (devices/settings/releases)
```
Same treatment fits `explorer_screen.dart` (1077 lines; `_ExplorerScreenState`
alone is ~900) and `search_screen.dart` (884) — extract `_build*` widget
clusters into private widget classes / `widgets/` files.

### P2 — Long Go functions worth decomposing
- `cmd/agent/main.go::runServe` (123 lines) — split flag parsing, cert/identity
  setup, and server wiring into helpers; this also makes `cmd/agent` testable.
- `server.New` (85) — table-drive the route registration.
- `search.go::parseSearchFilters` (82) — extract per-filter parsers.
- `store.migrate` (76) — fine as-is (linear migration list), low priority.

---

## How this review was targeted
The hotspots above came from the project knowledge graph (`graphify-out/`,
rebuild with `tools/rebuild-graph.sh`). God nodes — `New()`, `writeError()`,
the OpenAPI contract, `AgentClient`, `opsFromContext()` — pointed straight at
the files carrying the most structural weight. Re-run a review after the P1
splits land to confirm the god-class count drops.
