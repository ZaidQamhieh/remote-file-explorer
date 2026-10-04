# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A phone-as-file-explorer for your own PCs. Two components plus one shared contract:

- **`mobile/`** — React Native (Expo, Android-only) app. All UI + client orchestration. The Flutter app it replaced
  (v1.42.x) is in git history at tag `v1.42.5`.
- **`agent/`** — Go host service running on each Windows/Linux PC. Owns filesystem
  access, the transfer engine, search, thumbnails, settings, and the device/token store.
- **`protocol/openapi.yaml`** — the REST contract both sides follow. **Source of truth.**

No cloud server, no cloud database. The app reaches the agent over HTTPS/HTTP-2 on the
LAN by IP, optionally via the PC's **Tailscale** address, or through a user-configured
direct HTTPS address. Tailscale (WireGuard) provides NAT traversal, addressing, and an
outer encryption layer; direct internet access requires the PC owner to configure routing.

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
go run ./cmd/agent setup         # first-run folder setup + per-user service + pairing QR
go run ./cmd/agent devices       # list paired devices
go run ./cmd/agent revoke <id>   # block a device
go run ./cmd/agent remove <id>   # delete a device row
go run ./cmd/agent jail <id> <path>  # confine a device to <path> ("" clears it)
go run ./cmd/agent status        # name, addresses, fingerprint, counts
```
New agent databases default to a dedicated `RFE Files` folder under the signed-in user's home.
Unrestricted filesystem access must be explicitly selected with an empty `-roots` value or owner
settings; existing saved root policies are preserved.
Smoke test: `curl -sk https://127.0.0.1:8765/v1/health`

### Rust sidecars (in `agent-rs/`, toolchain pinned in `rust-toolchain.toml`)
```sh
cargo fmt --all --check && cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo build --release -p rfe-indexd -p rfe-thumbd     # binaries in target/release
# Go vs Rust differential tests (Go is the oracle; they skip without built sidecars):
RFE_SIDECAR_DIR=$PWD/target/release go test -run 'Sidecar|Renderer' ./internal/server ./internal/sidecar ./internal/thumbs   # from agent/
tools/package-agent.sh linux amd64 <version> agent-rs/target/release out.tar.gz       # agent + sidecars + manifest
```
Sidecars are on by default only for a verified package (`rfe-sidecars.txt` beside them); `RFE_SIDECARS=off` disables,
`indexd|thumbd|all` enables a dev build. `rfe-agent status` shows their state. Details: vault note
`sidecar-release-and-install`.

### App (React Native / Expo 57, in `mobile/`)
```sh
npm ci
npx tsc --noEmit                 # typecheck
npx eslint .                     # lint
npx jest                         # full suite (the live contract suite skips itself without an agent)
npx jest path/to/foo.test.ts     # single file
RFE_AGENT_BIN=<built agent> npx jest contract   # live contract test against a real agent
(cd android && ./gradlew :rfe-transport:testReleaseUnitTest)   # JVM tests of the Kotlin module (after `npx expo prebuild`)
npx expo run:android             # dev build; enter agent host:port on the connect screen
```

### Release (OTA APK)
The Android app is `mobile/` (React Native). Set `expo.version` and
`expo.android.versionCode` in `mobile/app.json` (the code **must increase every release**: OTA detection compares
`versionCode`, and it started above the Flutter build's 80 and is 81 for v2.0.0), commit, push, then tag `vX.Y.Z` (becomes the Latest
release) or `vX.Y.Z-rc.N` (pre-release, never Latest) and push the tag. `.github/workflows/release.yml` runs the CI
gates, builds and signs the APK with the production key from repo secrets, checks the signing certificate, and
publishes the GitHub Release plus `latest.json` that the app's updater reads (`releases/latest`). A push to an
`rn/**` branch runs the same pipeline as a dry run and keeps the APK as a workflow artifact. Agent releases
(`agent-v*`) are published with `--latest=false`: the updater needs the newest *app* release to hold the Latest flag.
Local signed build: `mobile/scripts/build-release-apk.sh`. See `docs/upgrade-to-react-native.md`.
CI runs per area: on branch pushes `release.yml` (APK build) only runs when `mobile/**`, `protocol/**`,
`.github/actions/**` or the release/mobile workflows change, `ci.yml` (agent gates) when `agent/**`, `agent-rs/**` or
`tools/**` change, `desktop.yml` for `desktop/**`; a tag always runs everything (path filters are not evaluated for tags).

### Desktop app (Tauri, `desktop/`)
PC control app for the local agent; not part of the Android release (`desktop.yml` is its gate). From `desktop/src-tauri`: `RFE_AGENT_BIN=<built agent> cargo test --locked`,
`cargo fmt --all --check`, `cargo clippy --all-targets --locked -- -D warnings`. No desktop release exists yet.
Versioning: `desktop/src-tauri/Cargo.toml` and `tauri.conf.json` carry the same version (`desktop/src-tauri/tests/versions.rs`
fails when they differ). A release is the tag `desktop-vX.Y.Z` (`desktop-vX.Y.Z-rc.N` for a pre-release) on a commit with
that version, published with `--latest=false` like `agent-v*`, because the Android updater needs the newest *app* release to
hold the Latest flag. `release.yml` only runs for `v*` tags, so `desktop-v*` never starts an APK build.
Docs: `desktop/README.md`, `desktop/docs/user-guide.md` (troubleshooting), `keystore.md`. A message the user can see needs a row there;
`desktop/src-tauri/tests/docs.rs` fails for an agent error code without one and lists the app's own messages by stem. Also run `node --test desktop/ui-tests/*.test.mjs`.

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
device revoke/remove, `/pair` rate-limited 10/min, and independent per-device
browse/download/upload/modify/delete/share grants. Existing devices preserve their effective
access on upgrade; new code-paired devices start browse-only; password-authenticated owner
devices bypass these file grants, while global policy, roots, jail, and read-only controls still
apply. Server file operations use rooted filesystem handles to prevent symlink escapes during
access. **Audit log:** account/device/share events only
(pair, register, login incl. failures, device revoke/remove/limit change, share
mint/revoke, agent restart) — `audit_log` table, admin-only `GET /v1/audit`,
`rfe-agent audit` CLI. **File operations are deliberately not recorded**; they
arrive at transfer volume and would bury everything else.

**Transfers (the core engineering — recently rebuilt; touch its UI, not its logic):**
uploads are resumable chunked sessions with per-chunk + whole-file SHA-256 and a
received-chunk bitmap in SQLite for resume, finishing with an atomic temp→final rename;
downloads use HTTP Range with resume from last offset. Both support parallelism.

**Layout:**
```
mobile/src/app/    Expo Router routes (screens only)
mobile/src/core/   pinned agent client, security, storage, models
mobile/src/features/  hosts, explorer, transfers, preview, pairing, search, settings, photoBackup, update ...
mobile/modules/rfe-transport/   Kotlin Expo module (pinned TLS, uploads, MediaStore, installer)
agent/cmd/agent/   main daemon + admin.go (CLI subcommands)
agent/internal/    server (incl. search), fsops, transfer, thumbs, pairing, store,
                   security, settings, updates, mdns, netinfo, sidecar
agent-rs/          Rust sidecars rfe-indexd, rfe-thumbd (+ rfe-proto); protocol in protocol/sidecar.md
agent/internal/webui/   web companion; edit the Vite + React + TypeScript SPA in web/src/
                        (`web/package.json`; build with `cd agent/internal/webui/web && npm run build`)
                        to generate ../dist/, which Go embeds into the agent binary; do not edit dist/ directly
protocol/openapi.yaml        shared REST contract
```

## Hard constraints (do not violate)

- **Android-first.** Don't break the OTA updater flow (`mobile/src/features/update/`; the app reads
  `releases/latest/download/latest.json`, so the newest *app* release must hold the Latest flag). No iOS work.
- **`android/` is generated** (Expo CNG) and never committed: change native config in `mobile/app.json` and
  `mobile/plugins/withRfeAndroid.js`.
- **OpenAPI is the contract:** any agent API change ships its `protocol/openapi.yaml`
  edit **in the same commit**. The spec drifted once — don't repeat it.
- Preserve behavior of the transfer engine, TOFU pinning, and the approve-on-PC pairing flow.
- Same package id and release keystore as the Flutter app, so updates install in place. Never change either.

## Conventions

- **All network calls go through the one pinned agent client** (`mobile/src/core/api/agentClient.ts`); screens
  don't build requests themselves.
- **Per-wave commits:** a `feat:` commit, then a separate `fix:` commit for review fixes.
- **Auto commit/push/release, no permission-asking:** once a change is done and
  verified (tests green), commit and push it without stopping to ask first —
  same for tagging and pushing a release (`vX.Y.Z`). Owner said the back-and-forth
  wastes time. Still stop for genuinely destructive/irreversible git ops outside this
  scope (force-push, reset --hard, branch delete).

## Token-discipline workflow (follow this — CI is free, local re-runs are not)

CI runs the full suites free in the cloud: `ci.yml` (agent: `go vet` + `go test`, cross-builds, OpenAPI lint) and
`mobile.yml` (tsc, eslint, jest, contract test, JVM tests); `release.yml` calls both before building. Therefore:

- **Run only the directly-affected test files locally** as a sanity check, then push and
  **trust CI** for the full green. Never run the whole suite 3× (local + sub-agent + CI)
  for one change.
- **Don't dispatch review/fix sub-agents for small diffs** — do them inline. Reserve
  sub-agents for large waves with disjoint file ownership (they re-read context cold).
- Don't re-read a file you just edited to verify — the edit tooling already confirmed it.

## Local hooks (Lefthook — runs the checks so I don't have to)

One-time after clone: `go install github.com/evilmartians/lefthook@latest && lefthook install`.
- **pre-commit** (staged files, fast): `gofmt` check, `go vet`.
- **pre-push** (changed side only): `go test`. CI is the full-suite backstop.
Config: `lefthook.yml` (+ `.lefthook-rc` puts go on PATH for IDE-launched hooks).
Bypass once if needed: `LEFTHOOK=0 git commit …`.

## Ops (host-side — moved from global ~/.claude/CLAUDE.md, 2026-07-02)

- **Back up `~/.rfe-keystore/`** — losing it = un-updatable app.
- `graphify query "..."` (graph at `graphify-out/`) answers code-structure questions only; the
  graph is code-only, so grep/Read normally for anything else. Never `/graphify --update` on this
  repo (restores the unpruned hairball) — use `tools/rebuild-graph.sh`.
- Agent redeploy only when `agent/`, `agent-rs/` or `protocol/openapi.yaml` changes; deploy the agent, both
  sidecars and `rfe-sidecars.txt` together (see the Rust sidecars commands above). Restart:
  `systemctl --user restart rfe-agent.service` (needs `export XDG_RUNTIME_DIR=/run/user/$(id -u)`).
- After copying new binary: re-run `sudo setcap cap_net_bind_service=+ep`. Note
  `/proc/<pid>/exe` md5 check is Permission-denied on setcap'd binaries — verify via
  disk checksum + restart timing instead.

## Project state

Current state, open work, blockers and runbooks live in the knowledge vault card `rfe`
(`vault read rfe`), not in this repo. Unfinished work is recorded in that card's `## Next`.

## Pointers

- `docs/architecture.md` — **living code map** (file→responsibility). Read it instead of grepping.
- `docs/WAVE_RUNBOOK.md` — wave dispatch loop + the **sub-agent brief template**.
- `docs/architecture.md`, `docs/development.md` — deeper architecture + dev setup.
- `HANDOFF.md` — deployment runbook.
- `docs/feature-roadmap.md`, `docs/next-waves-addendum.md` — planned features (waves).
- `docs/dev-experience-and-automation.md` — the plan this CLAUDE.md is step 1 of.
