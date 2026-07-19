# Architecture

## Overview

Two components plus a shared contract:

- **`app/`** — Flutter mobile app (Android-focused, v1.42+). All UI + client orchestration.
- **`agent/`** — Go host service on each Windows/Linux computer. Owns filesystem access, the
  transfer engine, search, thumbnails, settings, and the device/token store.
- **`protocol/openapi.yaml`** — the REST contract both sides follow (source of truth).

The app talks to the agent over **HTTPS (HTTP/2) + TLS**, reachable on the LAN by IP or, from
anywhere, via the computer's **Tailscale** address — same code path. mDNS auto-discovery on the
LAN is implemented (`agent/internal/mdns`) so the phone can find an agent without manual IP
entry. Because Tailscale (WireGuard) already provides NAT traversal, stable addressing, and
encryption, there is **no cloud server and no cloud database**.

## Key decisions

| Area | Decision |
|------|----------|
| Mobile framework | Flutter (Riverpod, dio, flutter_secure_storage) |
| Backend | Custom Go host agent — single static binary, runs as a service |
| Remote access | Tailscale (already in use) + LAN by IP/hostname; mDNS auto-discovery |
| Transport security | TLS with self-signed cert; phone pins the SHA-256 fingerprint at pairing (TOFU) |
| Storage | SQLite on the agent; local DB + Keychain/Keystore on the phone |

## Security model (summary)

1. TLS everywhere; fingerprint pinning on top of Tailscale's WireGuard layer.
2. Device pairing (via `rfe-agent pair`, QR or manual entry) issues a revocable bearer token
   (stored in Keychain/Keystore on the phone).
3. Per-agent authorization: root-path jail, optional read-only mode, device revocation/removal,
   `/pair` rate limiting (10/min).
4. Strict path normalization + jail enforcement against traversal/symlink escape.

There is currently no audit log — device actions (revoke/remove, settings changes) are not
recorded to a persistent log; this is a possible future addition.

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
| `core/api/agent_client.dart` (~840) | **The one pinned HTTP client.** ALL network + content access goes through it (dio, TOFU cert pin, bearer token). No raw dio anywhere else. |
| `features/explorer/explorer_state.dart` (~590) | **`ExplorerNotifier`** — the state hub. Every explorer mutation (navigate, select, sort, refresh, file ops) goes through it; widgets never call `AgentClient` directly. |
| `features/explorer/explorer_screen.dart` (~950) | The central browse UI (list/grid, breadcrumb, selection, drag, view options) — wires widgets to `ExplorerNotifier`. |
| `core/settings/settings_controller.dart` (~480) | Two-tier settings: app defaults + per-device overrides; the resolution logic both screens read. |

### `core/` — shared infrastructure

| Area | Files | Responsibility |
|------|-------|----------------|
| api | `api/providers.dart` | Riverpod providers exposing `AgentClient` + derived state. |
| models | `models/{entry,listing,device,health,drive,host,pair_response,search_result,upload_session,agent_settings,app_release}.dart` | Hand-written JSON DTOs (candidate for codegen — Track 2). |
| settings | `settings/{app_settings.dart, settings_controller.dart}` | Settings model + the two-tier controller. |
| storage | `storage/{host_store,favorites,listing_cache,recent_searches,view_prefs,visibility_prefs,download_saver}.dart` | Local persistence (hosts, favorites, offline listing cache, prefs, Downloads saver). |
| theme | `theme/{tokens,app_theme,motion}.dart` | `Brand`/`Spacing`/`Radii`/`Elevations`, M3 theme, motion helpers. Skia-only (Impeller off). |
| ui | `ui/{format,feedback,entry_leading,state_views}.dart` | Shared `formatSize`/`formatDate` (**use these, no local dupes**), snackbar/haptic toolkit, file-type leading icons, empty/error/loading views. |
| update | `update/update_service.dart` | OTA updater client (`/v1/app/latest` + `/v1/app/download`). |
| misc | `app_info.dart`, `main.dart` | App version/info; app entrypoint + router. |

### `features/` — one folder per screen/domain

| Feature | Key files | Responsibility |
|---------|-----------|----------------|
| hosts | `host_list_screen.dart`, `widgets/{host_card,storage_gauge}.dart` | The computer/host list + per-host card and storage gauge. |
| explorer | (hub files above) + `meta_sheet.dart`, `thumbnail_image.dart`, `drives_view.dart`, `clipboard_state.dart`, `destination_picker_state.dart`, `widgets/*` | File browser. `clipboard_state` = cut/copy/paste (Wave G2). `widgets/`: breadcrumb, entry tile/grid cell, selection bar, conflict dialog, create menu, favorites, view options, drag, batch report. `destination_picker_*` kept but unused since clipboard replaced it. |
| preview | `preview.dart` (dispatcher) + `{image,pdf,text,video}_preview.dart`, `text_editor.dart`, `preview_actions.dart`, `preview_common.dart`, `preview_image_cache.dart` | Media preview + in-app text editor (PUT `/v1/content`, Wave G1). |
| search | `search_screen.dart`, `search_logic.dart` | Remote search UI + query/debounce logic. |
| settings | `settings_screen.dart`, `app_settings_screen.dart`, `update_tile.dart`, `widgets/{settings_section,device_view_overrides_section}.dart` | Per-device settings, app-default settings, OTA update tile, active-sessions. |
| transfers | `transfer_manager.dart`, `transfer_state.dart`, `chunk_planner.dart`, `transfer_speed.dart`, `widgets/mini_transfer_bar.dart` | Transfer queue/center: manager orchestration, state, chunk planning, speed/ETA, mini bar. |
| pairing | `pairing_screen.dart` | QR scan / manual pairing flow. |

## Agent — `agent/`

| Package / file | Responsibility |
|----------------|----------------|
| `cmd/agent/main.go` | Daemon dispatcher + `runServe`; `defaultDataDir()` (`-data` > `$RFE_DATA_DIR` > `~/.rfe-agent`). |
| `cmd/agent/admin.go` | Admin CLI subcommands: `pair`, `devices`, `revoke`, `remove`, `status`. |
| `internal/server/server.go` | chi router wiring — where every route is mounted. |
| `internal/server/auth.go` | Bearer-token auth middleware + per-device authorization. |
| `internal/server/fshandlers.go` | List/read/create/delete/move/rename file endpoints. |
| `internal/server/transferhandlers.go` | Upload-session + chunk PUT + download-range endpoints. |
| `internal/server/search.go` | Search endpoint (recursive walk). |
| `internal/server/thumb.go` | Thumbnail endpoint. |
| `internal/server/settings_handlers.go` | Live-mutable agent settings endpoints. |
| `internal/server/update_handlers.go` | `/v1/app/latest` + `/v1/app/download` (serves APKs from `updates/`). |
| `internal/server/pair.go` | Pairing endpoint (consumes a DB code, issues a token). |
| `internal/server/ratelimit.go` | `/pair` rate limiter (10/min). |
| `internal/fsops/fsops.go` | **Path jail + normalization** (traversal/symlink defense), listing, file ops. |
| `internal/fsops/{drives_*,birthtime_*}.go` | OS-specific drive enumeration + file birthtime. |
| `internal/transfer/transfer.go` | **Resumable chunked transfer engine** — SHA-256, received-chunk bitmap, atomic rename. Touch its UI, not its logic. |
| `internal/thumbs/thumbs.go` | Thumbnail generation. |
| `internal/pairing/pairing.go` | DB-backed pairing codes (`Mint`/`Consume`). |
| `internal/security/tls.go` | Self-signed cert generation + SHA-256 fingerprint. |
| `internal/settings/settings.go` | Agent settings model + load/save. |
| `internal/store/store.go` | SQLite store: devices, tokens, pairing codes, transfer bitmaps. Busy-timeout DSN for daemon+CLI concurrency. |
| `internal/updates/updates.go` | Update-channel management (the `updates/` dir). |
| `internal/netinfo/netinfo.go` | LAN + Tailscale address detection. |
| `internal/mdns/mdns.go` | mDNS/DNS-SD advertisement (`_rfe._tcp`) so the phone can discover an agent on the LAN without typing an IP. |
| `internal/webui/` (`webui.go` + `src/`, `dist/`) | Browser-based web companion (control/status/settings/file-browsing), embedded static bundle served at `/`. Tailwind CSS built from `src/input.css` via `npm run build:css`; markup (`dist/index.html`) is vanilla, no build step. |

## Test → source map (used by `scripts/test-affected.sh`)

Go tests sit beside their package (`*_test.go`), so a changed Go file maps to `go test` on its
own directory. Flutter has no cheap per-file mapping, so any change under `app/` runs the full
`flutter test` suite locally; trust CI for the rest. A change to `protocol/openapi.yaml` is
treated as affecting **both** sides.
