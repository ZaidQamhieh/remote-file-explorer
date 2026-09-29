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
- Duplicate finder asks before moving the marked copies to Trash (Flutter trashed on one tap). The kept copy is the first in walk order; Flutter's was whatever order the checksum response had.

## Post-parity list
(none yet)
