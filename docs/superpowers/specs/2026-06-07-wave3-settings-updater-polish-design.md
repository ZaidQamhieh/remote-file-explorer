# Wave 3 — Remote Settings, In-App Updater & UX Polish

**Date:** 2026-06-07
**Status:** Approved design, ready for implementation plan
**Project:** Remote File Explorer (Flutter app + Go host agent)

## Context

Wave 1 delivered pairing, browse, CRUD, and resumable transfers. Wave 2 added the QR
pairing fix, dual-address (LAN + Tailscale) host support, search, file previews, and
thumbnails. Wave 3 makes the product feel finished: the phone can now reconfigure the
host remotely, update itself over the air, and the explorer gains the polish expected
of a daily-driver file manager.

Three pillars, each independently buildable, executed as **parallel agents in git
worktrees** (the workflow proven in Wave 2). Hard constraints carried forward:

- **Riverpod pinned at 2.6.1** (never 3.x).
- **All content fetches go through the existing pinned `AgentClient`** (TLS fingerprint
  pinning + bearer token) — never raw `http`, `Image.network`, or
  `VideoPlayerController.networkUrl`.
- **Contract-first:** new endpoints are added to `protocol/openapi.yaml` first.

---

## Pillar A — Remote Settings & Device Control

### Goal

A per-host Settings screen on the phone that surfaces and edits the agent's own
configuration: read-only mode, the root-path jail, paired-device management
(revocation), and the agent's display name. Per the user's decision, the phone has
**full remote control** — it may both tighten and loosen security (toggle read-only
either direction, freely add/remove jail roots). A paired phone therefore holds full
keys to the PC; the Settings UI states this plainly so it is not a surprise.

### Architectural decision: live-mutable config

Today `read-only` and `roots` are CLI flags read once at startup and frozen into
`fsops`. To make the phone's toggles take effect immediately:

- The `config` table (key/value, already exists) becomes the **source of truth** for
  `readOnly` and `roots`.
- A new mutex-guarded `settings.Store` holds the current values in memory, backed by
  the DB. `fsops` consults it **per operation** (`IsReadOnly()`, `Roots()`) instead of
  reading values captured at construction time.
- CLI flags (`--read-only`, `--roots`) become **first-run seed values only**: on
  startup, if the corresponding config key is unset, seed it from the flag; otherwise
  the DB value wins. This preserves existing flag-based deployment while making the DB
  authoritative thereafter.
- Result: toggling read-only or editing roots from the phone is effective on the next
  request — **no service restart**.

### Agent changes

**`internal/settings/` (new package)**
- `Store` struct wrapping `*store.DB`, with `RLock`-guarded `IsReadOnly() bool` and
  `Roots() []string`, plus `SetReadOnly(bool)` and `SetRoots([]string)` that persist to
  the `config` table and update the in-memory cache atomically.
- `Load(db, seedReadOnly, seedRoots)` constructor that seeds unset keys on first run.

**`internal/fsops/`**
- `Ops` takes a `*settings.Store` (or a small interface `settingsView{ IsReadOnly() bool; Roots() []string }`) instead of the captured `readOnly bool` / `roots []string`.
  Every write path checks `IsReadOnly()`; every path-resolution checks `Roots()`.
  An empty roots slice continues to mean "allow all" (unchanged semantics).

**`internal/store/`**
- `ListDevices() ([]Device, error)` — all rows, including revoked, ordered by created.
- `RevokeDevice(id string) error` — sets `revoked = 1`.
- `SetAgentName(name string)` via the existing `config` table (key `agentName`), read at
  startup to override the `--name` flag default when present.
- Revocation enforcement **already exists**: `authMiddleware` (auth.go:37) rejects
  `device.Revoked` tokens with `401`. `RevokeDevice` therefore only needs to flip the
  flag; no middleware change required.

**`internal/server/` — new authenticated routes**
| Method | Path | Body / effect |
|--------|------|---------------|
| `GET` | `/v1/settings` | `{ readOnly, roots, agentName }` |
| `PATCH` | `/v1/settings` | `{ readOnly?, roots?, agentName? }` — partial update |
| `GET` | `/v1/devices` | `[{ id, label, created, lastSeen, revoked, current }]` |
| `DELETE` | `/v1/devices/{id}` | revoke a device (cannot revoke the caller's own token — return `409` to avoid self-lockout) |

`current: true` marks the device whose token made the request (so the UI can label
"This phone" and prevent self-revoke).

### App changes

- **`core/models/agent_settings.dart`**, **`device.dart`** — model classes.
- **`core/api/agent_client.dart`** — `getSettings()`, `updateSettings(...)`,
  `listDevices()`, `revokeDevice(id)`.
- **`features/settings/settings_screen.dart`** — opened from the host card (overflow
  menu) or explorer app bar. Sections:
  - **Access:** read-only switch (with a caption: "Off = this phone can modify files");
    a banner noting the phone holds full control of the host.
  - **Allowed folders (jail):** list of roots with add (path text field / pick from a
    drive) and remove; empty list shows "All folders allowed".
  - **Paired devices:** list with label, last-seen, and a Revoke action; the current
    device is labelled and non-revocable.
  - **Agent name:** editable text field.
- Settings writes call the client then refresh; optimistic UI with rollback on error.

### Verification (Pillar A)
- `curl PATCH /v1/settings {readOnly:true}` then attempt a write → `403`; toggle back →
  write succeeds. No restart between steps.
- Add a jail root that excludes `/tmp`, then list `/tmp` → `403`; remove it → succeeds.
- `GET /v1/devices` lists the smoke-test device; `DELETE` it, then reuse its token →
  `401`. Self-revoke attempt → `409`.

---

## Pillar B — In-App Updater (Android only)

### Goal

Update the phone app over Wi-Fi/Tailscale with no USB and no app store, using the
agent on the PC as the update server. One tap (Android's system install prompt) per
update. iOS is out of scope (sideloaded self-update is forbidden); all update UI is
guarded behind `Platform.isAndroid`.

### Build/release flow
1. Developer builds the release APK on the PC (`flutter build apk --release`).
2. Drops it into `~/.rfe-agent/updates/` (created on agent startup if absent). The
   filename convention `rfe-<versionName>-<versionCode>.apk` (e.g.
   `rfe-1.2.0-12.apk`) carries the version; the agent parses `versionCode` as the
   monotonic comparison key. A future enhancement could read the APK's manifest
   directly, but filename parsing keeps the agent dependency-free.
3. The phone discovers and installs it.

### Agent changes

**`internal/updates/` (new package)**
- `Latest(dir) (*Release, error)` — scans `dir` for `rfe-*.apk`, parses
  `{versionName, versionCode, filename, size}`, returns the highest `versionCode`
  (or nil if none).

**`internal/server/` — new authenticated routes**
| Method | Path | Effect |
|--------|------|--------|
| `GET` | `/v1/app/latest` | `{ versionName, versionCode, size }` or `204` if none |
| `GET` | `/v1/app/download` | streams the latest APK bytes (`application/vnd.android.package-archive`), Range-enabled via the existing download helper |

`main.go` plumbs an `UpdatesDir` (default `~/.rfe-agent/updates/`) into `server.Config`.

### App changes

- **`pubspec.yaml`** — add an installer package (`install_plugin` or
  `open_filex`; final choice during implementation) and declare
  `REQUEST_INSTALL_PACKAGES` + `INTERNET` in `AndroidManifest.xml`. A `FileProvider`
  entry is required for the installer to read the downloaded APK on Android 7+.
- **`core/api/agent_client.dart`** — `latestRelease()` and a `downloadApk(toFile,
  onProgress)` using the existing pinned download path.
- **`core/update/update_service.dart`** — compares `latestRelease().versionCode`
  against `PackageInfo.fromPlatform().buildNumber`; exposes
  `UpdateAvailable?` state via a provider.
- **UI:**
  - On app launch (after host list loads), silently check the active/last host; if an
    update exists, show a dismissible banner / dialog "Update available → vX.Y.Z".
  - A **"Check for updates"** tile in Settings that runs the check on demand and shows
    download progress, then launches the installer.
- All of the above is wrapped in `if (Platform.isAndroid)`; on other platforms the
  update entry points are hidden.

### Verification (Pillar B)
- `curl GET /v1/app/latest` with a seeded `rfe-1.0.1-2.apk` returns its metadata;
  empty dir returns `204`.
- Install vN on the phone, drop vN+1 in the updates dir, open the app → banner appears
  → tap → APK downloads over the pinned client → Android install prompt → confirm →
  app relaunches as vN+1. No USB.
- Downgrade/equal version → no update offered.

---

## Pillar C — UX Polish

Four independent improvements to the explorer. Multi-select, the `ExplorerNotifier`
state machine, and the `_MultiSelectBar` already exist — these are enhancements, not
new subsystems.

### C1 — Offline listing cache
- **`core/storage/listing_cache.dart`** — an on-disk JSON store under the app's
  documents dir, one file per host, mapping `path -> { entries, fetchedAt }`. Size-
  capped (LRU eviction by `fetchedAt`, e.g. keep the most recent ~200 directories).
- **`ExplorerNotifier._load()`** — on navigation: emit cached entries immediately (if
  present) with a `stale: true` flag, then fetch live and replace + update the cache.
  If the live fetch fails and a cache entry exists, keep showing the cached entries with
  an "offline / showing cached" indicator instead of an error. Writes are still blocked
  while offline (surfaced via the error/offline state, C2).
- `ExplorerState` gains `stale`/`fromCache` booleans.

### C2 — Empty / error / offline states
- **`core/ui/` shared widgets:** `EmptyFolderView`, `ErrorRetryCard(onRetry)`,
  `OfflineBanner`, and a `ListingSkeleton` (shimmer rows/cells) shown during the first
  load instead of a bare `CircularProgressIndicator`.
- Wire into the explorer (empty dir, load error with retry, cached/offline banner) and
  the host list (offline host styling).

### C3 — Drag-and-drop (Android)
- Rows/cells become `LongPressDraggable<Entry>` (or a multi-drag of the current
  selection); folder rows/cells and the breadcrumb segments become `DragTarget<Entry>`
  that, on drop, perform a **move** (`client.move`) into that folder, with a confirm
  toast and undo where feasible.
- Edge autoscroll while dragging near the top/bottom of the list.
- Long-press already toggles selection; drag is initiated from the drag handle / after
  a short hold so it doesn't fight selection. Interaction detail finalized in
  implementation; gracefully no-op on non-touch.

### C4 — Batch-ops refinement
- `_MultiSelectBar`: add **select-all / clear**, a **count badge**, and make the
  contextual action bar persistent while in multi-select.
- **Batch progress:** copy/move/delete of many items shows a progress sheet (n of m,
  current item, cancel) driven by the existing batch endpoints; per-item failures are
  collected and reported at the end rather than aborting the whole batch.

### Verification (Pillar C)
- Navigate a folder, kill the agent, re-enter it → cached entries shown with offline
  banner; attempt a write → clear "offline" message, not a crash.
- Empty folder → friendly empty view; force a list error → retry card; first load shows
  skeletons.
- Drag a file onto a folder → it moves (verify on the PC filesystem); drag onto a
  breadcrumb crumb → moves up.
- Select 20 files → select-all → delete → progress sheet counts down; inject one
  permission error → batch completes, error summarized.

---

## Cross-Cutting

- **`protocol/openapi.yaml`:** add `/settings`, `/devices`, `/devices/{id}`,
  `/app/latest`, `/app/download` with request/response schemas before implementing.
- **Security note:** full remote control is an accepted, deliberate choice for personal
  use; the Settings UI surfaces that the phone holds full host access. Revoked tokens
  are already rejected by `authMiddleware` (auth.go:37).
- **No new cloud dependencies.** The updater uses the agent itself; the cache is local.

## Execution Plan (parallel agents)

Designed so each pillar is an isolated worktree agent with minimal shared-file overlap
(the Wave 2 pattern). Shared touch-points (`agent_client.dart`, `server.go`,
`openapi.yaml`, `explorer_screen.dart`) are merged at the end as in Wave 2.

- **Agent 1 — Settings & devices** (Go: settings pkg, fsops, store, server routes; Dart:
  settings screen, models, client methods).
- **Agent 2 — Updater** (Go: updates pkg, server routes, main plumbing; Dart: update
  service, client methods, installer wiring, manifest/permissions).
- **Agent 3 — Polish** (Dart only: listing cache, shared state widgets, drag-and-drop,
  batch refinement) — optionally split C1+C2 from C3+C4 into two agents if large.

Each agent: builds clean (`go build ./...` / `flutter analyze` + `flutter build apk
--debug`), runs the smoke tests in its Verification section, commits on its branch.
Integration merge + full end-to-end verification + agent redeploy follows, as in Wave 2.

## Out of Scope (Wave 3)

- iOS updater (platform-forbidden).
- WebSocket `/events` live filesystem push (manual + cache refresh suffices for now).
- mDNS auto-discovery and a Windows service installer (candidate Wave 4).
- Silent (zero-tap) updates / Shorebird code-push (rejected: cloud dependency).
