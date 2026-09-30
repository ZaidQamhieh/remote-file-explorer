# RN migration parity ledger (frozen 2026-09-29, base b49d7044, Flutter 1.42.5+80)

Status: port | replace | gap | obsolete(owner-approved). Post-parity items are appended below, never added to the ledger.

## Release identity
- applicationId `com.zqamhieh.remote_file_explorer`; versionCode 80; release signing via `app/android/key.properties` (absent here; `~/.rfe-keystore` missing) -> blocker rfe-6do.

## Screens (app/lib/features; Dart lines)
explorer 9735 · settings 5564 · preview 3888 · hosts 3633 · search 2339 · transfers 2258 · pairing 1837 · photo_backup 1078 · share 653 · home 569 · sync 556 · handoff 520 · onboarding 277 · bookmarks 227. All: port.

## API (protocol/openapi.yaml, 51 paths)
health,status,metrics,transfers/list,users(+/{u}),logs,audit,agent/restart,auth/{challenge,logout},pair,register,login,wol,share/{mint,token,list},system/drives,fs/{,folder,file,rename,copy,move,...}. All: port via generated typed client. Agent-admin endpoints (users/logs/restart) stay owner-gated.

## Native bridges (MainActivity.kt 475 L, TransferService.kt 86 L)
| channel | methods | RN plan |
|---|---|---|
| intent | getInitialHostId | Expo module + intent filter plugin |
| discovery | scan, stop | Kotlin NsdManager/mDNS module |
| transfers | start, stop, complete | Kotlin foreground service module (spike 1C) |
| files | saveToDownloads, getDeviceId, installApk, openFile | Kotlin module (MediaStore, FileProvider, package installer) |

## Persisted state
- SharedPreferences (`FlutterSharedPreferences`, keys prefixed `flutter.`): `rfe_hosts_v1` (JSON list), `rfe_last_seen_*`, favorites, bookmarks, pins, sync rules, saved/recent searches, view/visibility prefs, settings (`app.`, `host.`).
- Secure storage (FlutterSecureStorage 10.3.1): `rfe_token_<hostId>`, `rfe_fp_<hostId>`, `rfe_device_identity_private_v1` (32-byte Ed25519 seed, base64), `..._public_v1`, offline body cache key.
- Backup (`rfe-backup` v1) EXCLUDES the device private key by design (PR-17): backup cannot migrate identity. Migration must be in-place Kotlin read or verified re-pair.

## Pin semantics (agent_client.dart)
Empty trust store; exact leaf-cert SHA-256 (lowercase hex) compared in cert callback before any header/body; missing pin with token -> `MissingCertPin`; mismatch -> `CertPinMismatch`. One pin per host across routes. RN transport must replicate: custom Kotlin TrustManager, no system roots.

## Tests to port/replace: 100 Dart test files (app/test).

## Deliberate deviations (owner review)
- Explorer row long-press starts selection; Bookmark moved to the selection app bar (1 item). Flutter bound row long-press to bookmark, which left multi-select unreachable by touch.
- Preview kind ignores MIME parameters: the agent sends `text/markdown; charset=utf-8`, so Flutter always showed Markdown/CSV as plain text.
- PDF pages scroll vertically (Flutter paged horizontally inside the horizontal file pager).
- Pinned HTTPS reuses TLS connections per pin (Flutter's HttpClient pooled too); never across pins.
- Details sheet (folder/file actions, permissions, checksum): opened from the folder info button, from the selection bar when one item is selected, from the preview menu, and by tapping a file that has no previewer. Flutter reached it only from the folder info button and only showed a toast for unpreviewable files, so file actions such as Extract here and Share link were unreachable.
- Offline bodies are AES-256-GCM (Tink streaming AEAD, 64 KiB segments) with the key in secure storage; Flutter used ChaCha20-Poly1305 with its own envelope. Existing Flutter offline_cache files are not migrated (they are reconstructible). File names are hashes, so the directory no longer reveals host ids or paths.
- The Files tab opens a host's cached listings while it is offline by remembering the roots it last allowed (Flutter showed a connection error for "Browse cache").
- Forgetting a computer also drops its cached listings and offline bodies (the Flutter behaviour, which the first RN port skipped).
- Host settings: Storage insights and Sync rules rows are left out until those screens are ported (rfe-bvw.5, rfe-bvw.4) instead of shipping dead links.
- Connection diagnostics tells DNS failure from an unreachable host by reading the transport error behind the connection failure (AgentApiError.cause); Flutter read Dio exception types.
- Cross-host search (Flutter had the screen but no way to reach it; only its widget tests used it): reachable from the host search screen's "Search every paired device instead" button, and its rows open the result's folder in Files (Flutter's rows did nothing).
- Duplicate finder asks before moving the marked copies to Trash (Flutter trashed on one tap). The kept copy is the first in walk order; Flutter's was whatever order the checksum response had.

## Post-parity list
(none yet)
