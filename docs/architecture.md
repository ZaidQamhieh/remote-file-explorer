# Architecture

## Overview

Two components plus a shared contract:

- **`app/`** — Flutter mobile app (Android-focused, v1.42+). All UI + client orchestration.
- **`agent/`** — Go host service on each Windows/macOS/Linux computer. Owns filesystem access, the
  transfer engine, search, thumbnails, settings, and the device/token store.
- **`protocol/openapi.yaml`** — the REST contract both sides follow (source of truth).

The app talks to the agent over **HTTPS (HTTP/2) + TLS**. On a local network it can connect by
IP or hostname without a VPN. **Tailscale is optional** and provides a private remote route when
installed on both devices; without it, remote access requires another routable path. The agent
advertises `_rfe._tcp` over mDNS/DNS-SD, but the Flutter app does not currently browse for those
records, so in-app host discovery still relies on QR pairing or manually entered addresses. The
app can save a direct HTTPS hostname or IP as a final connection fallback. The PC owner must
configure DNS, router NAT, and firewall access; the app does not modify network settings. The
project currently has **no cloud relay or cloud database**.

## Key decisions

| Area | Decision |
|------|----------|
| Mobile framework | Flutter (Riverpod, dio, flutter_secure_storage) |
| Backend | Custom Go host agent — single static binary, runs as a service |
| Connection routes | LAN, optional Tailscale, then a user-configured direct HTTPS address; no built-in relay |
| Agent discovery | Agent-side mDNS/DNS-SD advertisement; Flutter app-side browsing is not implemented |
| Transport security | TLS with a self-signed cert; enrollment pins a SHA-256 fingerprint obtained out of band |
| Pin storage | `HostStore` Keychain/Keystore secure storage is authoritative; the SharedPreferences copy is not a trust source |
| Storage | SQLite on the agent; app metadata locally and tokens/pins in Keychain/Keystore secure storage |
| Host app launch | Current-user registrations: Windows AppsFolder, Linux XDG desktop, and macOS standard `.app` folders; per-device grants default off; launch by opaque ID only |

## Security model (summary)

1. TLS is used for all app-agent API traffic. New pairing requires a fingerprint from a trusted
   independent source (for example, the intended host's local display or console); the app checks
   the pin before sending pairing codes, passwords, or authenticated request data. Tailscale may
   add a private network route, but certificate pinning is independent of it. Direct HTTPS still
   uses the same pin; a TLS-terminating proxy with a different certificate is not supported.
2. Paired-device fingerprints and bearer tokens are stored in Keychain/Keystore secure storage.
   The secure-store fingerprint is authoritative; a missing or invalid value fails closed and is
   never recovered from the legacy SharedPreferences host record.
3. Device pairing (via `rfe-agent pair`, QR or manual entry) issues a revocable bearer token.
   Per-agent authorization includes a root-path jail, optional read-only mode, device
   revocation/removal, and `/pair` rate limiting (10/min). Browse, download, upload, modify,
   delete, and share are independent per-device file-action grants. Existing devices retain
   their prior access during migration; new code-paired devices start browse-only; devices
   authenticated by the account password retain full file access. Owner provenance bypasses
   per-device file grants, while configured roots, global and per-device read-only, per-device
   jail, and the global share switch remain in force. App-catalog viewing and app launching
   remain separate per-device grants, default off; admin provenance does not bypass them.
4. Strict path normalization + jail enforcement guards against traversal and symlink escape.
5. App launch accepts only an opaque ID from the agent's current-user app catalog. The agent
   re-resolves it before launch, does not accept client paths/commands/arguments, checks for an
   interactive desktop session, applies rate/concurrency limits, and audits the result. Catalog
   support is Windows and Linux registered desktop entries plus macOS `.app` bundles in standard
   application folders; arbitrary executables, macOS aliases, and apps outside those folders are
   not included.

The agent has a persistent SQLite audit trail for account, device, share-link, app-launch, and
restart events (including pair/register/login, device changes, share creation/revocation, app
launch outcomes, and agent restart). The audit endpoint is admin-only. File operations are
deliberately not recorded in that trail.

For the full route-by-route authentication and authorization inventory, including explicit gaps,
see [`security-route-matrix.md`](security-route-matrix.md). The current device model provides
administrator provenance, a per-device path jail, a read-only switch, separate app-view/app-
launch grants, and independent per-device browse, download, upload, modify, delete, and share
grants. Upload currently covers both new writes and the transfer engine's overwrite option;
overwrite cannot be separately required to hold the modify grant at the route boundary without
changing transfer-session enforcement.

## Transfers (the core engineering)

- **Upload:** resumable chunked sessions. Per-chunk + whole-file SHA-256; received-chunk bitmap in
  SQLite for resume; atomic temp→final rename on completion. Chunks can upload in parallel.
- **Download:** HTTP Range requests; resume from last offset; optional parallel ranges.

See `../protocol/openapi.yaml` for the full API surface.

---

# Code map (living)

> **Purpose: read this instead of fan-out grepping.** It maps every file to its one
> responsibility so a session — or a dispatched sub-agent — jumps straight to the right file.
> **Keep it current:** when you add/move/split a file, update its row in the same commit.
> Line counts are rough size hints, not exact.

## App — `app/lib/`

### Hub files (touched most often — know these first)

| File | Responsibility |
|------|----------------|
| `core/api/agent_client.dart` (~840) | **The one pinned HTTP client.** App-agent requests use Dio, verify the secure-store/out-of-band certificate pin before request data is sent, and add the bearer token only for pinned hosts. |
| `features/explorer/explorer_state.dart` (~590) | **`ExplorerNotifier`** — the state hub. Every explorer mutation (navigate, select, sort, refresh, file ops) goes through it; widgets never call `AgentClient` directly. |
| `features/explorer/explorer_screen.dart` (~950) | The central browse UI (list/grid, breadcrumb, selection, drag, view options) — wires widgets to `ExplorerNotifier`. |
| `core/settings/settings_controller.dart` (~480) | Two-tier settings: app defaults + per-device overrides; the resolution logic both screens read. |

### `core/` — shared infrastructure

| Area | Files | Responsibility |
|------|-------|----------------|
| api | `api/providers.dart` | Riverpod providers exposing `AgentClient` + derived state. |
| backup | `backup/{backup_service,config_backup}.dart` | Full-app backup/restore + settings-only config export/import. |
| models | `models/{entry,listing,device,health,drive,host,host_app,pair_response,search_result,upload_session,agent_settings,app_release,agent_status,archive_entry,bandwidth_settings,batch_result,share_link,trash_entry}.dart` | Hand-written JSON DTOs (candidate for codegen — Track 2). |
| notifications | `notifications/notification_service.dart` | Local notification channel setup + dispatch (transfer progress/completion). |
| platform | `platform/{file_opener,transfer_notifications,wol}.dart` | Platform-channel glue: open-with, native transfer notifications, Wake-on-LAN send. |
| security | `security/device_identity.dart` | Generates/persists the phone's device identity keypair (paired token binding). |
| settings | `settings/{app_settings.dart, settings_controller.dart}` | Settings model + the two-tier controller. |
| storage | `storage/{host_store,favorites,bookmark_store,pin_store,listing_cache,offline_body_cache,cache_manager,recent_searches,saved_searches,sync_rules,transfer_journal,transfer_queue_store,view_prefs,visibility_prefs,download_saver}.dart` | Local persistence (hosts, favorites/bookmarks/pins, offline listing + body cache, search history, sync rules, transfer queue/journal, prefs, Downloads saver). |
| theme | `theme/{tokens,app_theme,motion}.dart` | `Brand`/`Spacing`/`Radii`/`Elevations`, M3 theme, motion helpers. Skia-only (Impeller off). |
| ui | `ui/{format,feedback,entry_leading,state_views}.dart` | Shared `formatSize`/`formatDate` (**use these, no local dupes**), snackbar/haptic toolkit, file-type leading icons, empty/error/loading views. |
| update | `update/update_service.dart` | OTA updater client (`/v1/app/latest` + `/v1/app/download`). |
| misc | `app_info.dart`, `main.dart` | App version/info; app entrypoint + router. |
| l10n | `l10n/app_en.arb` (+ `l10n/generated/`) | Flutter gen-l10n source strings + generated localization delegate. |

### `features/` — one folder per screen/domain

| Feature | Key files | Responsibility |
|---------|-----------|----------------|
| home | `home_shell.dart`, `home_state.dart`, `widgets/app_bottom_nav.dart` | Top-level app shell + bottom nav tab state, hosting the other feature screens. |
| hosts | `host_list_screen.dart`, `host_apps_screen.dart`, `widgets/{host_card,storage_gauge}.dart` | The computer list, per-host card/storage gauge, and host app catalog/Run screen. |
| explorer | (hub files above) + `meta_sheet.dart`, `thumbnail_image.dart`, `drives_view.dart`, `clipboard_state.dart`, `destination_picker_state.dart`, `widgets/*` | File browser. `clipboard_state` = cut/copy/paste (Wave G2). `widgets/`: breadcrumb, entry tile/grid cell, selection bar, conflict dialog, create/batch-rename menus, chmod dialog, favorites, view options, drag, batch report. `destination_picker_*` kept but unused since clipboard replaced it. |
| bookmarks | `bookmarks_screen.dart` | Saved-path bookmarks list (backed by `core/storage/bookmark_store.dart`). |
| preview | `preview.dart` (dispatcher) + `{image,pdf,text,video}_preview.dart`, `text_editor.dart`, `preview_actions.dart`, `preview_common.dart`, `preview_image_cache.dart` | Media preview + in-app text editor (PUT `/v1/content`, Wave G1). |
| search | `search_screen.dart`, `search_logic.dart` | Remote search UI + query/debounce logic. |
| settings | `settings_screen.dart`, `app_settings_screen.dart`, `appearance_settings_screen.dart`, `file_visibility_screen.dart`, `notifications_settings_screen.dart`, `storage_security_settings_screen.dart`, `transfers_backup_settings_screen.dart`, `about_screen.dart`, `about_support_settings_screen.dart`, `update_banner.dart`, `update_tile.dart`, `widgets/{backup_restore_section,device_file_access_controls,settings_hero,settings_picker,settings_section,settings_tile}.dart` | Per-device settings and independent file-action grants, app-default settings, appearance/visibility/notifications/storage/backup sub-screens, OTA update tile/banner, about screen. |
| transfers | `transfer_manager.dart`, `transfer_state.dart`, `chunk_planner.dart`, `transfer_speed.dart`, `widgets/mini_transfer_bar.dart` | Transfer queue/center: manager orchestration, state, chunk planning, speed/ETA, mini bar. |
| pairing | `pairing_screen.dart` | QR scan / manual pairing flow. |
| handoff | `qr_generate_screen.dart`, `qr_scan_screen.dart` | Device-to-device handoff via QR (distinct from agent pairing). |
| onboarding | `onboarding_screen.dart` | First-run intro flow. |
| photo_backup | `photo_backup_controller.dart`, `photo_backup_logic.dart`, `photo_backup_prefs.dart`, `photo_backup_screen.dart` | Camera-roll auto-backup to a host: controller/logic split, prefs, settings UI. |
| share | `share_intake.dart`, `share_sheet.dart` | Receives OS share-sheet intents into the app; app's own outbound share sheet. |
| sync | `sync_runner.dart`, `sync_screen.dart` | Background two-way folder sync runner + its status/config UI. |

## Agent — `agent/`

| Package / file | Responsibility |
|----------------|----------------|
| `cmd/agent/main.go` | Daemon dispatcher + `runServe`; `defaultDataDir()` (`-data` > `$RFE_DATA_DIR` > `~/.rfe-agent`). |
| `cmd/agent/admin.go` | Admin CLI subcommands: `pair`, `devices`, `revoke`, `remove`, `status`. |
| `cmd/agent/install{,_darwin,_linux,_windows}.go` | `install`/`uninstall` CLI: registers the agent as an auto-start service (systemd --user / launchd / a Windows equivalent) — no root/admin required. |
| `internal/server/server.go` | chi router wiring — where every route is mounted. |
| `internal/server/auth.go` | Bearer-token auth middleware + per-device authorization. |
| `internal/server/login.go` | Username/password login — a second way (besides `/v1/pair`) to obtain a device token. |
| `internal/server/register.go` | Account registration; self-gated since it's reachable before any account exists. |
| `internal/server/challenge.go` | Nonce mint/verify for device-signature proof-of-possession (pairs with `security/device_identity.go`). |
| `internal/server/fshandlers.go` | List/read/create/delete/move/rename file endpoints. |
| `internal/server/archive_handler.go` | Compress/extract endpoints (fronts `fsops/archive.go`). |
| `internal/server/chmod_handler.go` | chmod endpoint. |
| `internal/server/dupfinder_handler.go` | Batch-checksum endpoint backing the app's duplicate finder. |
| `internal/server/recent.go` | Recent-files endpoint — a live recursive walk, like `search.go`, not a persistent index. |
| `internal/server/transferhandlers.go` | Upload-session + chunk PUT + download-range endpoints. |
| `internal/server/search.go` | Search endpoint (recursive walk). |
| `internal/server/search_index.go` | Background index rebuild backing `search.go`. |
| `internal/server/thumb.go` | Thumbnail endpoint. |
| `internal/server/settings_handlers.go` | Live-mutable agent settings endpoints. |
| `internal/server/apps_handlers.go` + `apps_{linux,windows,darwin,other}.go` | Per-device app catalog/launch routes and OS-specific current-user app inventory/launch adapters. |
| `internal/server/update_handlers.go` | `/v1/app/latest` + `/v1/app/download` (serves APKs from `updates/`). |
| `internal/server/pair.go` | Pairing endpoint (consumes a DB code, issues a token). |
| `internal/server/ratelimit.go` | Pairing, app-catalog, and app-launch rate limiters. |
| `internal/server/share_handlers.go` | One-time share-link mint/serve/revoke/list — see `docs/r1-share-link-threat-model.md`. |
| `internal/server/sse_handler.go` | Server-sent-events endpoint — server-side half of the PR-59 finding (client parser lives in the frozen `app/lib` tree). |
| `internal/server/status_handlers.go` + `status_disk_{unix,windows}.go` | `/v1/health`/status endpoint, incl. OS-specific disk-space lookup. |
| `internal/server/metrics_{linux,other}.go` | CPU/RAM for `/metrics` — read from `/proc` on Linux, zero on other OSes. |
| `internal/server/agent_control.go` + `agent_control_{linux,other}.go` | `/agent/restart` handler; OS-specific process restart. |
| `internal/server/throughput.go` | Process-lifetime cumulative rx/tx byte counters exposed via metrics. |
| `internal/server/wol_handler.go` | Wake-on-LAN send endpoint. |
| `internal/server/webdata_handlers.go` | List endpoints (+ user removal) backing the web companion's Transfers/Users/Logs pages. |
| `internal/fsops/fsops.go` | Core listing + file ops, built on `jail.go`'s path resolution. |
| `internal/fsops/jail.go` | **Path jail + normalization** (traversal/symlink defense) — the security boundary for every fs operation; `Resolve` is the single chokepoint. |
| `internal/fsops/archive.go` | Compress (zip) / Extract (zip, tar.gz), both routed through `Resolve`. |
| `internal/fsops/trash.go` | Move-to-trash / restore, XDG Trash-layout (`files/` + `info/*.trashinfo`). |
| `internal/fsops/{drives_*,birthtime_*}.go` | OS-specific drive enumeration + file birthtime. |
| `internal/transfer/transfer.go` | **Resumable chunked transfer engine** — SHA-256, received-chunk bitmap, atomic rename. Touch its UI, not its logic. |
| `internal/transfer/throttle.go` | Rate-limited `io.ReadSeeker` wrapper for bandwidth-capped transfers. |
| `internal/thumbs/thumbs.go` | Thumbnail generation. |
| `internal/pairing/pairing.go` | DB-backed pairing codes (`Mint`/`Consume`). |
| `internal/security/tls.go` | Self-signed cert generation + SHA-256 fingerprint. |
| `internal/security/device_identity.go` | Per-device Ed25519 identity keypair, generated on first use (pairs with `server/challenge.go`). |
| `internal/security/password.go` | bcrypt password hashing for account login (bearer tokens elsewhere use SHA-256 — different threat model). |
| `internal/settings/settings.go` | Agent settings model + load/save. |
| `internal/store/store.go` | SQLite store: devices, tokens, pairing codes, transfer bitmaps. Busy-timeout DSN for daemon+CLI concurrency. |
| `internal/updates/updates.go` | Update-channel management (the `updates/` dir). |
| `internal/netinfo/netinfo.go` | LAN + Tailscale address detection. |
| `internal/mdns/mdns.go` | Agent-side mDNS/DNS-SD advertisement (`_rfe._tcp`). The Flutter app does not currently browse these records; users still scan a pairing QR or enter the address. |
| `internal/webui/` (`webui.go`, `web/`, `dist/`) | Browser-based web companion (control/status/settings/file-browsing), embedded static bundle served at `/`. The Vite + React + TypeScript source lives in `web/`; run `npm run build` there to generate `dist/`, which Go embeds into the agent binary. Edit `web/src/` and rebuild; treat `dist/` as generated output. |

## Test → source map (used by `scripts/test-affected.sh`)

Go tests sit beside their package (`*_test.go`), so a changed Go file maps to `go test` on its
own directory. Flutter has no cheap per-file mapping, so any change under `app/` runs the full
`flutter test` suite locally; trust CI for the rest. A change to `protocol/openapi.yaml` is
treated as affecting **both** sides.
