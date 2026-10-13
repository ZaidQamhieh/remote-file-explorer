# CLAUDE.md

## What this is

A phone-as-file-explorer for your own PCs. No cloud server or database; the app reaches the agent over HTTPS/HTTP-2
on the LAN by IP, via the PC's Tailscale address, or a user-configured direct HTTPS address; direct internet access requires the PC owner to configure routing.

- **`mobile/`** - React Native (Expo, Android-only) app. All UI and client orchestration.
- **`agent/`** - Go host service on each Windows/Linux PC: filesystem access, transfer engine, search, thumbnails,
  settings, device/token store.
- Previous v1.42.x is in git history at tag `v1.42.5`.
- **`protocol/openapi.yaml`** - the REST contract both sides follow. **Source of truth.**

## Commands

To verify, run `check` (all the gates below in one call: one line per check, failure excerpts, full logs on disk, the real exit code) or `check <group>` (`go`, `rust`, `desktop`, `mobile`; `check --list`). Don't pipe it through `head`/`tail`.

### Agent (Go 1.26, in `agent/`)
```sh
go vet ./...                                  # lint
go test ./...                                 # all tests
go test ./internal/transfer/ -run TestName    # single package / single test
go run ./cmd/agent -addr 127.0.0.1:8765 -name "my-pc"   # run daemon
go build -o bin/agent ./cmd/agent             # build static binary
```
Admin CLI (opens the on-disk DB directly; works whether or not the daemon is running):
```sh
go run ./cmd/agent pair          # mint a one-time pairing code + print QR
go run ./cmd/agent setup         # first-run folder setup + per-user service + pairing QR
go run ./cmd/agent devices       # list paired devices
go run ./cmd/agent revoke <id>   # block a device
go run ./cmd/agent remove <id>   # delete a device row
go run ./cmd/agent jail <id> <path>  # confine a device to <path> ("" clears it)
go run ./cmd/agent status        # name, addresses, fingerprint, counts
```
New agent databases default to a dedicated `RFE Files` folder under the signed-in user's home. Unrestricted access
must be selected explicitly (empty `-roots` value or owner settings); saved root policies are preserved.
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
Set `expo.version` and `expo.android.versionCode` in `mobile/app.json` (the code **must increase every release**: OTA
detection compares it; 81 for v2.0.0), commit, push, then tag `vX.Y.Z` (becomes Latest) or `vX.Y.Z-rc.N` (pre-release,
never Latest) and push the tag. `.github/workflows/release.yml` runs the CI gates, builds and signs the APK, checks the
certificate, and publishes the GitHub Release plus `latest.json` (the app's updater reads `releases/latest`). A push to
an `rn/**` branch runs it as a dry run. Agent (`agent-v*`) and desktop (`desktop-v*`) releases are published with
`--latest=false`: the updater needs the newest *app* release to hold the Latest flag. Local signed build:
`mobile/scripts/build-release-apk.sh`.

### Desktop app (Tauri, `desktop/`)
PC control app, not part of the Android release (`desktop.yml` is its gate). From `desktop/src-tauri`:
`RFE_AGENT_BIN=<built agent> cargo test --locked`, `cargo fmt --all --check`,
`cargo clippy --all-targets --locked -- -D warnings`; also `node --test desktop/ui-tests/*.test.mjs`.
`desktop/src-tauri/Cargo.toml` and `tauri.conf.json` must carry the same version (`tests/versions.rs` fails otherwise).
A user-visible message needs a row in `desktop/docs/user-guide.md` (`tests/docs.rs` fails for an agent error code without one, and lists the app's own messages by stem). Release = tag
`desktop-vX.Y.Z` (`-rc.N` for pre-release); `release.yml` only runs for `v*` tags.

## Architecture you can't see from one file

**Data dir (agent):** `-data <dir>` flag > `$RFE_DATA_DIR` > `~/.rfe-agent`. The daemon and the admin CLI resolve it
identically, so a no-flag `rfe-agent devices` talks to the same SQLite DB as a no-flag daemon (busy-timeout makes concurrent writes safe).

**Security / trust model:** self-signed TLS; first run writes `agent-cert.pem`/`agent-key.pem` and logs a SHA-256
fingerprint. The phone **pins that fingerprint at pairing (TOFU)**; a later mismatch is rejected. Pairing mints a
**revocable per-device bearer token** stored in Keychain/Keystore. Agent-side authorization: root-path jail, optional
read-only mode, device revoke/remove, `/pair` rate-limited 10/min, and per-device browse/download/upload/modify/delete/share
grants. Existing devices keep their effective access on upgrade; new code-paired devices start browse-only;
password-authenticated owner devices bypass the file grants, but global policy, roots, jail and read-only still apply.
File operations use rooted filesystem handles to prevent symlink escapes. **Audit log:** account/device/share events only
(pair, register, login incl. failures, device revoke/remove/limit change, share mint/revoke, agent restart) in the
`audit_log` table, admin-only `GET /v1/audit`, `rfe-agent audit` CLI. **File operations are deliberately not recorded.**

**Transfers (touch the UI, not the logic):** uploads are resumable chunked sessions (per-chunk + whole-file SHA-256,
received-chunk bitmap in SQLite, atomic temp -> final rename); downloads use HTTP Range with resume. Both support parallelism.

**Layout:**
```
mobile/src/app/    Expo Router routes (screens only)
mobile/src/core/   pinned agent client, security, storage, models
mobile/src/features/  hosts, explorer, transfers, preview, pairing, search, settings, photoBackup, update ...
mobile/modules/rfe-transport/   Kotlin Expo module (pinned TLS, uploads, MediaStore, installer)
agent/cmd/agent/   main daemon + admin.go (CLI subcommands)
agent/internal/    server (incl. search), fsops, transfer, thumbs, pairing, store,
                   security, settings, updates, mdns, netinfo, sidecar
agent/internal/webui/   web companion; edit the Vite + React + TypeScript SPA in web/src/, build with
                        `cd agent/internal/webui/web && npm run build` (generates ../dist/, which Go embeds); never edit dist/
agent-rs/          Rust sidecars rfe-indexd, rfe-thumbd (+ rfe-proto); protocol in protocol/sidecar.md
protocol/openapi.yaml        shared REST contract
```

## Hard constraints (do not violate)

- **Android-first.** Don't break the OTA updater flow (`mobile/src/features/update/`; the app reads
  `releases/latest/download/latest.json`, so the newest *app* release must hold the Latest flag). No iOS work.
- **`android/` is generated** (Expo CNG) and never committed: change native config in `mobile/app.json` and
  `mobile/plugins/withRfeAndroid.js`.
- **OpenAPI is the contract:** any agent API change ships its `protocol/openapi.yaml`
  edit **in the same commit**.
- Preserve behavior of the transfer engine, TOFU pinning, and the approve-on-PC pairing flow.
- Same package id and release keystore as the Flutter app, so updates install in place. Never change either.

## Conventions

- **All network calls go through the one pinned agent client** (`mobile/src/core/api/agentClient.ts`); screens
  don't build requests themselves.
- **Per-wave commits:** a `feat:` commit, then a separate `fix:` commit for review fixes.
- Tagging and pushing a release (`vX.Y.Z`) after the checks are green needs no confirmation; force-push and `reset --hard` still do.

## Testing (CI is free, local re-runs are not)

CI runs the full suites in the cloud: `ci.yml` (agent: `go vet` + `go test`, cross-builds, OpenAPI lint) and
`mobile.yml` (tsc, eslint, jest, contract test, JVM tests); `release.yml` calls both before building. So:
**run only the directly-affected test files locally**, push, and **trust CI** for the full green. Never run the whole
suite 3x (local + sub-agent + CI) for one change.

Lefthook (one-time: `go install github.com/evilmartians/lefthook@latest && lefthook install`): pre-commit runs `gofmt`
and `go vet` on staged files, pre-push runs `go test` on the changed side. Config `lefthook.yml`; bypass once with
`LEFTHOOK=0 git commit ...`. `.lefthook-rc` puts go on PATH for IDE-launched hooks.

## Ops (host-side)

- **Back up `~/.rfe-keystore/`** - losing it = un-updatable app.
- `graphify query "..."` (graph at `graphify-out/`) answers code-structure questions only; grep/Read for anything else.
  Never `/graphify --update` on this repo - use `tools/rebuild-graph.sh`.
- Redeploy the agent only when `agent/`, `agent-rs/` or `protocol/openapi.yaml` changes; deploy the agent, both
  sidecars and `rfe-sidecars.txt` together. Restart: `systemctl --user restart rfe-agent.service` (needs
  `export XDG_RUNTIME_DIR=/run/user/$(id -u)`).
- After copying a new binary: re-run `sudo setcap cap_net_bind_service=+ep`. The `/proc/<pid>/exe` md5 check is
  Permission-denied on setcap'd binaries; verify via disk checksum and restart timing instead.

## Project state and pointers

Current state, open work, blockers and runbooks live in the knowledge vault card `rfe` (`vault read rfe`), not in this
repo; unfinished work is in that card's `## Next`. Read on demand:

- `docs/architecture.md` - living code map (file to responsibility). Read it instead of grepping.
- `docs/claude-reference.md` - CI path filters, release and desktop-release details.
- `docs/WAVE_RUNBOOK.md` - wave dispatch loop + sub-agent brief template.
- `docs/development.md` (dev setup), `HANDOFF.md` (deployment runbook), `docs/feature-roadmap.md`,
  `docs/next-waves-addendum.md` (planned waves), `docs/upgrade-to-react-native.md`.
