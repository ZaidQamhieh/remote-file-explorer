# Remote File Explorer — Project Handoff

> Single-document briefing for a fresh chat. Read this top-to-bottom and you'll have
> the full picture: what the app is, how it's built, where the code lives, the hard
> constraints, the current build state, and how to operate it.

---

## 1. What it is

A **phone-as-file-explorer for your PC**, over LAN or Tailscale.

- **Host agent** (Go) runs on the PC, serves a file API over TLS to paired phones.
- **Mobile app** (Flutter, Android-focused) browses/transfers files, previews media,
  and self-updates over-the-air from the agent.

No cloud. Pairing is TOFU (trust-on-first-use) cert pinning + a bearer token per device.

Repo root: `~/Storage/Projects/remote-file-explorer`

---

## 2. Architecture & stack

### Host agent (`agent/`)
- **Go 1.26**, chi router, `modernc.org/sqlite` (pure-Go, no cgo), `skip2/go-qrcode` (vendored).
- TLS self-signed cert, fingerprint pinned by the phone on first pair.
- Bearer-token device auth; devices keyed on a stable `client_id` (Android ID).
- Runs as a **systemd --user service** named `rfe-agent`.
  - Binary: `~/.local/bin/rfe-agent`
  - Data dir: `~/.rfe-agent` (DB at `~/.rfe-agent/agent.db`, certs, `updates/`, `transfers/`, `thumbs/`)
  - Needs `export XDG_RUNTIME_DIR="/run/user/$(id -u)"` for `systemctl --user`.
- Build/run: `export PATH="$HOME/.local/go/bin:$PATH"`, work from `agent/`.

### Mobile app (`app/`)
- **Flutter**, **Riverpod 2.6.1** (PINNED — never 3.x), `dio`, `flutter_secure_storage`.
- All network/content fetches go through the **pinned `AgentClient`** (no raw dio elsewhere).
- Native Android bits via MethodChannel `rfe/downloads`:
  `saveToDownloads`, `installApk` (FileProvider + ACTION_VIEW), `getDeviceId` (Settings.Secure.ANDROID_ID).
- Build/run: `export PATH="$HOME/flutter/bin:$PATH"`, work from `app/`.
- applicationId: `com.zqamhieh.remote_file_explorer`

### Contract
- Contract-first **OpenAPI** at `protocol/openapi.yaml`. Change the spec, then implement.

---

## 3. Hard constraints (do not violate)

1. **Riverpod stays at 2.6.1.** Never upgrade to 3.x.
2. **All content/network access goes through the pinned `AgentClient`.** No ad-hoc HTTP.
3. **Contract-first:** update `protocol/openapi.yaml` before implementing API changes.
4. Android-only paths (installer, install-permission, device-id) stay guarded by `Platform.isAndroid`.

---

## 4. Current build state (as of 2026-06-08)

- **App release: v1.5.0 (build 10)** — UI remodel + native installer + feedback toolkit
  + device dedup + remove-revoked-device button + updater pruning of old cached APKs.
- **Agent:** admin-CLI build, DB-backed pairing codes, deployed to `~/.local/bin/rfe-agent`.
  - **Agent version is now `1.0.0`** (was `0.1.0`); `protocol/openapi.yaml` `info.version`
    bumped to match. No min-version handshake yet (future work).
  - **Data dir unified**: both the daemon (no-args/`serve`) and the admin CLI now resolve the
    data dir via the same `defaultDataDir()` (in `cmd/agent/main.go`), precedence
    `-data` flag > `$RFE_DATA_DIR` > `~/.rfe-agent`. Previously the daemon defaulted to
    `os.UserConfigDir()/remote-file-explorer` while the CLI defaulted to `~/.rfe-agent` —
    `rfe-agent devices` (no `-data`) was opening a different, empty DB than the live deployment.
    `~/.rfe-agent` was kept as the default since it's what the deployed systemd service and
    `release.sh` already use.
  - `protocol/openapi.yaml` had a contract-drift pass: removed the never-implemented `permanent`
    delete flag (deletes are permanent/recursive `os.RemoveAll`, documented as such), removed the
    promised-but-nonexistent `/v1/events` WebSocket (rephrased as future work), added
    `address`/`tailscaleAddress` to `Health`/`PairResponse`, made `Content-Range` optional on
    chunk PUT, documented the full error-code vocabulary + 401/429/413 responses, and added
    server-side validation rejecting negative `size` on `POST /transfers` (400 BAD_REQUEST).
- **Phone:** Samsung SM S918B (Android 16 / API 36), adb serial `R5CWB2KDC2K`.
  - adb path: `~/Android/Sdk/platform-tools/adb`
  - ⚠️ Phone was last cable-flashed to **build 6** and its app data was cleared, so it is
    **currently unpaired**. To bring it current: `rfe-agent pair` → scan → it will then be
    offered the OTA up to v1.5.0.
- Working tree: clean, all work committed on `master`.

### Release tooling
`./release.sh X.Y.Z+N` bumps `pubspec.yaml`, builds the APK, publishes it to
`~/.rfe-agent/updates/`, and **deletes older `rfe-*.apk`** so only the latest is cached.

---

## 5. Theme / design language

"Distinctive Modern" — `ColorScheme.fromSeed` **indigo `#4F5BD5`** + **cyan `#00B4D8`**,
light + dark, `ThemeMode.system` (no manual toggle yet).

Foundation: `app/lib/core/theme/{tokens,app_theme,motion}.dart`
- `Brand` (seed, accent, online/offline colors)
- `Spacing` (xs4 / sm8 / md16 / lg24 / xl32)
- `Radii` (chip10 / card16 / sheet28)
- `Elevations`
- `fadeThroughPageRoute`, `AppearListItem` (motion helpers)

---

## 6. Agent admin CLI (newest feature — how you operate the host now)

`rfe-agent` is a subcommand dispatcher. **No-args / leading-flag / `serve` still runs the
daemon**, so the systemd unit is unchanged. Data dir resolves: `-data` > `$RFE_DATA_DIR` > `~/.rfe-agent`.

| Command | What it does |
|---|---|
| `rfe-agent pair [-ttl 1h]` | **The way to add a phone now.** Mints a single-use code + prints a scannable QR in the terminal. No more restart-service-and-grep-journal. |
| `rfe-agent devices` | Table of paired devices (id, label, status, last seen). |
| `rfe-agent revoke <id>` | Block a device (accepts a unique id prefix). |
| `rfe-agent remove <id>` | Permanently delete a device (accepts a unique id prefix). |
| `rfe-agent status` | name, version, LAN/Tailscale addrs, fingerprint, device counts. |

Key change: **pairing codes moved from daemon memory into the DB** (`pairing_codes` table).
`pairing.Manager` is now DB-backed (`Mint`/`Consume`); the **daemon no longer mints a code at startup**.
Store added `CreatePairingCode` / `ConsumePairingCode` / `ResolveDeviceID`, plus a
`_busy_timeout=5000` DSN so the CLI and daemon can write the same DB concurrently.

Code: `agent/cmd/agent/main.go` (dispatcher + `runServe`), `agent/cmd/agent/admin.go`
(subcommands), `agent/internal/pairing/pairing.go` (DB-backed), `agent/internal/store/store.go`.

---

## 7. Feature history (all shipped, on master)

- **Wave 3** (`cc17f56`): remote settings & device control (live-mutable, no restart);
  in-app Android updater (`/v1/app/latest` + `/v1/app/download` serving APKs from
  `~/.rfe-agent/updates/`); UX polish (offline cache, empty/error states, drag-move, batch ops).
- **Native installer** (`89beae5`): replaced `open_filex` (its `canRequestPackageInstalls()`
  pre-check false-negatives on Android 16) with a native FileProvider + ACTION_VIEW intent.
  Authority `${applicationId}.fileprovider`, paths in `res/xml/provider_paths.xml`.
- **Feedback toolkit** (`51624a4`): `app/lib/core/ui/feedback.dart` —
  `showSuccess` / `showError(onRetry)` / `showInfo` / `runWithFeedback` + haptics;
  replaced ~18 ad-hoc snackbars.
- **Device dedup** (`50b92e4`): app sends Android ID as `deviceId`; agent `UpsertDevice`
  reuses the row matching `client_id` (rotates token, clears revoked). Fixes "every update
  made a new paired device." Survives clearing app data AND reinstall.
- **Device hard-delete** (`908f550`): `DELETE /v1/devices/{id}?purge=true` + Settings trash
  button for revoked devices.
- **UI remodel** (`8f6d5f5`/`a3dcce7`/`b1c58bd`/`59cf8d3`): per-screen modern redesign.
- **Admin CLI** (`b03afbd`): section 6 above.

Specs/plans live in `docs/superpowers/specs/` and `docs/superpowers/plans/`.

---

## 8. How to build / deploy / verify

```bash
# --- Agent ---
export PATH="$HOME/.local/go/bin:$PATH"
cd ~/Storage/Projects/remote-file-explorer/agent
go build ./... && go vet ./... && go test ./...
# deploy:
go build -o ~/.local/bin/rfe-agent ./cmd/agent
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user restart rfe-agent
systemctl --user status rfe-agent

# --- App ---
export PATH="$HOME/flutter/bin:$PATH"
cd ~/Storage/Projects/remote-file-explorer/app
flutter analyze lib/ && flutter test
flutter build apk --debug          # or: ../release.sh X.Y.Z+N to publish an OTA

# --- Pair the phone (current next step) ---
~/.local/bin/rfe-agent pair         # scan the QR in the app: Add computer → Scan QR
```

Tests currently green: Go (store/server/settings/updates incl. pairing-code lifecycle &
prefix-resolve), Flutter (~43 tests, analyze clean, Riverpod held at 2.6.1).

---

## 9. Standing context

- **Autonomy grant:** user has repeatedly said to work fully autonomously — make decisions,
  run parallel agents, commit freely, don't ask for confirmation.
- **User is limit/cost-conscious** — be efficient, don't spawn agents gratuitously.
- Parallel work uses **git worktree isolation** (one agent per disjoint file set, merge clean).

---

## 10. Likely next steps / open ideas (none committed-to)

- **Re-pair the phone** (it's unpaired) and dogfd the v1.5.0 OTA. ← most natural next action.
- Theme smoke test; in-app manual light/dark toggle (currently system-only).
- **Wave 4 candidates:** WebSocket `/events` (live push), mDNS discovery, Windows installer,
  Shorebird silent updates.
