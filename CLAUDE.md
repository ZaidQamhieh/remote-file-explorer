# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A phone-as-file-explorer for your own PCs. Two components plus one shared contract:

- **`app/`** — Flutter (Android-first) mobile app. All UI + client orchestration.
- **`agent/`** — Go host service running on each Windows/Linux PC. Owns filesystem
  access, the transfer engine, search, thumbnails, settings, and the device/token store.
- **`protocol/openapi.yaml`** — the REST contract both sides follow. **Source of truth.**

No cloud server, no cloud database. The app reaches the agent over HTTPS/HTTP-2 on the
LAN by IP, or anywhere via the PC's **Tailscale** address — same code path. Tailscale
(WireGuard) provides NAT traversal, addressing, and an outer encryption layer.

## Commands

### Agent (Go 1.25, in `agent/`)
```sh
go vet ./...                                  # lint
go test ./...                                 # all tests
go test ./internal/transfer/ -run TestName    # single package / single test
go run ./cmd/agent -addr 127.0.0.1:8765 -name "my-pc"   # run daemon
go build -o bin/agent ./cmd/agent             # build static binary
```
Admin CLI (opens the on-disk DB directly — works whether or not the daemon is running):
```sh
go run ./cmd/agent pair          # mint a one-time pairing code + print QR
go run ./cmd/agent devices       # list paired devices
go run ./cmd/agent revoke <id>   # block a device
go run ./cmd/agent remove <id>   # delete a device row
go run ./cmd/agent jail <id> <path>  # confine a device to <path> ("" clears it)
go run ./cmd/agent status        # name, addresses, fingerprint, counts
```
Smoke test: `curl -sk https://127.0.0.1:8765/v1/health`

### App (Flutter 3.44.2 / Dart 3.12, in `app/`)
```sh
flutter pub get
flutter analyze                  # must be clean
flutter test                     # full suite
flutter test test/path/foo_test.dart                 # single file
flutter test --plain-name "description substring"     # single test by name
flutter run                      # enter agent host:port on the connect screen
```

### Release (OTA APK, from repo root)
```sh
./release.sh                     # build current pubspec version, publish to update channel
./release.sh 1.9.3+18            # bump pubspec X.Y.Z+N first, then build + publish
```
`release.sh` builds the release APK and copies it into the agent's local update channel
(`~/.rfe-agent/updates/`). **The build number (`+N`) must increase every release** — OTA
update detection compares `versionCode`, not the name.

## Architecture you can't see from one file

**Data dir resolution (agent):** `-data <dir>` flag > `$RFE_DATA_DIR` > `~/.rfe-agent`
(default). The daemon and the admin CLI resolve it identically, so a no-flag
`rfe-agent devices` talks to the same SQLite DB as a no-flag daemon (busy-timeout makes
concurrent writes safe).

**Security / trust model:** TLS with a self-signed cert; first run writes
`agent-cert.pem`/`agent-key.pem` and logs a SHA-256 fingerprint. The phone **pins that
fingerprint at pairing (TOFU)** via `HttpClient.badCertificateCallback` — a later
mismatch is rejected. Pairing mints a **revocable per-device bearer token** stored in
Keychain/Keystore. Agent-side authorization: root-path jail, optional read-only mode,
device revoke/remove, `/pair` rate-limited 10/min. Path normalization enforces the jail
against traversal/symlink escape. **There is no audit log** — don't claim one exists.

**Transfers (the core engineering — recently rebuilt; touch its UI, not its logic):**
uploads are resumable chunked sessions with per-chunk + whole-file SHA-256 and a
received-chunk bitmap in SQLite for resume, finishing with an atomic temp→final rename;
downloads use HTTP Range with resume from last offset. Both support parallelism.

**Layout:**
```
app/lib/core/      api client, models, storage, theme, ui, update
app/lib/features/  hosts, explorer, transfers, preview, pairing, search, settings
agent/cmd/agent/   main daemon + admin.go (CLI subcommands)
agent/internal/    server, fsops, transfer, search, thumbs, pairing, store, security,
                   settings, updates
agent/internal/discovery/   EMPTY placeholder — mDNS is NOT implemented
protocol/openapi.yaml        shared REST contract
```

## Hard constraints (do not violate)

- **Impeller is DISABLED** (`AndroidManifest.xml` sets `EnableImpeller=false`) due to
  3.29 glyph-atlas corruption on the owner's Samsung Mali/Xclipse GPU. The app renders on
  **Skia** — avoid expensive per-frame blurs/shaders; prefer cheap M3 surfaces and
  opacity/transform animations.
- **Riverpod stays on 2.x** (`flutter_riverpod ^2.6.1`, Notifier API). **Do not migrate
  to Riverpod 3.**
- **Android-first.** Don't break the OTA updater flow (`app/lib/core/update/`,
  `update_tile.dart`). No iOS work.
- **OpenAPI is the contract:** any agent API change ships its `protocol/openapi.yaml`
  edit **in the same commit**. The spec drifted once — don't repeat it.
- Preserve behavior on the rebuilt transfer engine, TOFU pinning, and pairing flow.

## Conventions

- **All explorer state changes go through the notifier** (`ExplorerNotifier`) — widgets
  don't call `AgentClient` directly.
- **One formatter:** use the shared `formatSize`/`formatDate` in `core/ui/` — do not
  reintroduce local `_formatSize` duplicates.
- **Per-wave commits:** a `feat:` commit, then a separate `fix:` commit for review fixes.

## Token-discipline workflow (follow this — CI is free, local re-runs are not)

CI (`.github/workflows/ci.yml`) runs the full suite (`go vet` + `go test`, `flutter
analyze` + `flutter test`) free in the cloud on every push to master/main. Therefore:

- **Run only the directly-affected test files locally** as a sanity check, then push and
  **trust CI** for the full green. Never run the whole suite 3× (local + sub-agent + CI)
  for one change.
- **Don't dispatch review/fix sub-agents for small diffs** — do them inline. Reserve
  sub-agents for large waves with disjoint file ownership (they re-read context cold).
- Don't re-read a file you just edited to verify — the edit tooling already confirmed it.

## Local hooks (Lefthook — runs the checks so I don't have to)

One-time after clone: `go install github.com/evilmartians/lefthook@latest && lefthook install`.
- **pre-commit** (staged files, fast): `dart format` check, `flutter analyze`, `gofmt` check, `go vet`.
- **pre-push** (changed side only): `go test` / `flutter test`. CI is the full-suite backstop.
Config: `lefthook.yml` (+ `.lefthook-rc` puts go/flutter on PATH for IDE-launched hooks).
Bypass once if needed: `LEFTHOOK=0 git commit …`.

## Pointers

- `docs/architecture.md` — **living code map** (file→responsibility). Read it instead of grepping.
- `docs/WAVE_RUNBOOK.md` — wave dispatch loop + the **sub-agent brief template**.
- `docs/architecture.md`, `docs/development.md` — deeper architecture + dev setup.
- `HANDOFF.md` — deployment runbook.
- `docs/feature-roadmap.md`, `docs/next-waves-addendum.md` — planned features (waves).
- `docs/dev-experience-and-automation.md` — the plan this CLAUDE.md is step 1 of.
