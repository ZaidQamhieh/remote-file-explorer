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

## Onboarding pager
- The welcome and ready pages use a static gradient circle, not the animated two-blob hero (no Rive asset exists for that slot either way).
- The pager is skipped for any install that already has a paired computer, so upgraders from the Flutter app never see it. The flag is stored as `onboarding_complete` in the kv table.

## Upload engine
- Uploads run in the same native journaled engine as downloads (one foreground service, one journal). The record carries `direction`, the agent `sessionId` and the whole-file SHA-256, so a killed app resumes the same agent session and sends only the chunks the agent's bitmap lacks.
- Chunks are sent one at a time at a fixed 4 MiB (the Flutter app's default). Parallel chunk sends are not ported yet.
- Picked files are moved from the picker's cache into `files/uploads/<id>/` and deleted with their journal entry outcome (done or cancelled), so a cleared cache cannot break a resume. A failed upload keeps its copy so Retry works.
- "Keep both" numbers the new copy against the names already listed in the folder plus the other picks. A concurrent writer on the host can still cause a CONFLICT, which surfaces as a failed transfer with a plain-language reason.
- The Transfers tab groups Active, Failed and Finished with a progress bar per row and Clear for finished ones. Speed and ETA, and per-host grouping, are not ported yet.

## Public Downloads
- Finished downloads are copied into the shared `Download/Remote File Explorer` folder through MediaStore (Android 10 and newer, no storage permission) and the app-private copy is dropped. The Flutter app kept downloads in its app-specific external folder, invisible to other apps. On Android 9 and older, or if publishing fails, the file stays in app storage and the row says so.
- A finished download opens from its Transfers row. Removing a row never deletes the published file.

## App settings
- The Settings tab is a hub with Preferences (Appearance, File visibility, Transfers), Data (Storage & Security) and Support (About) sub-screens. Flutter mixed these with per-computer settings on one long screen; per-computer settings stay under each host.
- Accent color uses the same eight presets and the Material 3 tonal-spot derivation as `ColorScheme.fromSeed` (`@material/material-color-utilities`); the default keeps the hand-picked brand scheme. The app's violet stays the secondary role, as in Flutter.
- "Use wallpaper colors" is not offered: React Native has no Material You source. The stored `app.dynamicColor` value is kept so a round trip does not lose it.
- App lock uses `expo-local-authentication` (biometric with device PIN/pattern fallback). It locks on cold start and after 2 s in the background, and fails open when no screen lock is enrolled (a lock nobody can satisfy would brick the app). Turning it on requires a screen lock and one successful prompt first.
- Trusted certificates lists each paired computer's pinned fingerprint with Forget (the same un-pairing as host settings, including its cached data). Flutter showed the same list without a way to forget from there.
- Cache shows the cached folder-listing count and Clear also empties the image cache. The "Downloaded files" line is gone: downloads now live in the shared Downloads folder and are not app cache.
- Not ported because nothing in the RN app consumes them yet: notification toggles, low-disk alerts, weekly digest, watched folders, compress-on-cellular, update tile and diagnostics export. The stored values are read and written unchanged. Open-source licenses page is omitted (no RN equivalent of `showLicensePage`).
- Transfers settings only shows the fixed 4 MiB chunk size and links to the Transfers tab.

## Storage insights
- Host settings gets a Storage Insights row (Flutter had it too, reached from the same screen). The ring, per-drive list and free-space row use the same aggregation as Flutter; the agent reports drives that sit at or under the device's allowed folders, so a jailed device with roots on a non-mount folder sees an empty state, as in Flutter.
- The by-type map scans the host recursively from `/` (Flutter's start point), one page of 200 at a time, and stops when the screen closes. The route also accepts a `path` parameter to scan a single folder; nothing in the UI passes one yet.
- Sizes use the shared formatter (binary units), so a 10.2 MB file set shows as 9.7 MB, as in the Flutter map.

## Explorer command palette and transfer pace
- Command palette (overflow menu) filters the same eleven actions as Flutter; Navigate to Path asks for a path and jumps there. Storage by type in the overflow menu now opens the map for the current folder (Flutter did too).
- Active transfers show the smoothed speed and time left, worked out in JS from the engine's progress events (an average that ignores samples closer than 0.5 s). Flutter showed the same two numbers; there is no native rate.
- Each download is staged in its own folder (`downloads/<transfer id>/<name>`). Flutter and the first RN port used `downloads/<name>`, so two downloads of one file at once shared a partial file and corrupted each other ("size mismatch"). The folder is removed once the file is published, cancelled or forgotten.

## Offline pin sync
- Once per launch, the first time a host's Files tab loads successfully, its pinned folders are re-listed (updating the offline listing cache) and files that are not yet stored offline are downloaded. Flutter only fetched a folder's files when it was pinned and never refreshed afterwards. Bodies already stored are left as they are; they refresh when the file is next opened online. An offline start does not count, so it retries on the next visit.
