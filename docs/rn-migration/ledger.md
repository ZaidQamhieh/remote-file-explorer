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
- Not ported because nothing in the RN app consumes them yet: notification toggles, low-disk alerts, weekly digest, watched folders and compress-on-cellular. The stored values are read and written unchanged. The update tile, diagnostics export and open-source licenses are under About & Support (see Updater and Licenses below).
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

## Hand-off and share intake
- Hand-off QR: a file's More sheet has "Scan to receive". The QR carries the host's certificate fingerprint and the file path (no token, no address). The other phone's Receive screen scans it, finds the paired computer whose pin matches, and downloads through the normal engine. A phone that has not paired that computer is told so rather than pairing it. Flutter had no phone-to-phone hand-off.
- Share intake: sharing files from another app to Remote File Explorer opens a screen to pick a paired computer (skipped with one), then a folder with the same picker as Move/Copy, and uploads with the usual name-clash prompt. Text and links are ignored with a toast. Android only (`expo-share-intent`, iOS disabled). Flutter's share intake did not exist.

## Not ported yet
- No in-app update-ready notification (Flutter posted one from its background check); the RN background job downloads the APK quietly and About shows "Update available".
- `expo-share-intent` throws on a share whose content URI returns no rows (an unreadable or revoked grant) and takes the app down; normal senders grant access, so this is left as is. Verified on the emulator with a MediaStore image: cold start, folder pick, upload, and the keep-both prompt. The camera scan in Receive was not exercised (no camera on the emulator); the QR sheet and the permission screen render.

## Photo backup
- Settings > Photo backup keeps the Flutter behavior: one-way copy of photos (not videos) to the folder the computer's owner set in its web companion, in `<folder>/<phone nickname>/<year>/<year-month>/<asset id>.<ext>`, optional album selection, Wi-Fi-only and charging-only switches, and a "Back up now" action. The settings and the backed-up record use the Flutter keys and encoding, so the one-time import carries them over.
- Differences: Flutter never had a scheduled photo backup (its WorkManager job only checked for app updates). RN adds "Back up automatically" (see Scheduled background work). A photo is recorded as backed up when its upload finishes, found by the transfer id `pb-<asset id>`; the record is updated while the app is open, so a photo whose upload finishes while the app is dead is recorded at the next launch (unless its finished row was cleared first, in which case it uploads again and the agent answers CONFLICT, which is treated as already backed up: the path is device, capture date and MediaStore id, so the file there is the same photo). The media library reports assets as content URIs, so the file name, transfer id and record use the trailing MediaStore row id, which is also what Flutter recorded.
- Emulator-verified against a scratch agent: permission prompt, PC picker, album picker (root-level files with no bucket name show as "Other photos"), files landing at `<folder>/<device id>/<year>/<year-month>/<id>.jpg`, live backed-up count, reset record, already up to date, Wi-Fi-only and charging-only messages, and the "not set on the PC" message. The PC must list its backup folder inside its roots (a relative `-roots` value made the destination unavailable to the paired device).
- Each photo is copied into app storage before queueing (the engine deletes the copy when done), so a large first backup briefly needs the same amount of free space as the queued photos.

## Parallel chunk uploads
- An upload sends up to three chunks at once (Flutter sent one at a time per file). The agent already allows concurrent chunk requests per session; completion waits for all of them. Progress and resume are unchanged: the agent's bitmap decides what is left, so a failed run may leave later chunks already stored. JVM-tested against the fake agent (concurrency asserted). Emulator wall clock, loopback, 100 MB: about 12 s unthrottled (roughly 8 MB/s or more; the emulator's own network throttle does not apply to the host loopback). There is no switch to force one chunk at a time, so no sequential baseline was measured, and no real Wi-Fi timing exists (needs a phone).

## Support and About
- About & Support has What's new (a short 2.0 list, not Flutter's per-release history from v1.18), Privacy policy (the same facts as Flutter, plus that diagnostics carry no passwords, tokens or file names) and Export diagnostics, which copies a plain-text summary to the clipboard as Flutter did. The RN summary adds app lock and drops the Dart version.
- The in-app updater and the licenses page are ported (see below). Host setup guidance is the existing pairing, login and register hints, which were ported with their Flutter wording.

## Sync rules
- Settings > Sync Rules mirrors one remote folder into a folder picked with the system folder picker (Storage Access Framework tree; the app keeps access across restarts). Rules keep the Flutter keys and encoding, so the import carries them over; a rule whose local path is a plain path from Flutter still runs.
- On demand only, downloads only, top level only (no subfolders, no deletions), as in Flutter. A file is fetched when it is missing, a different size, or older than the remote copy; each download goes to a staging file first and is copied in on completion, replacing any existing document. There is no background sync.
- Emulator-verified: add rule, Documents picker with the "Allow access" prompt, first run downloads (names and sizes right), second run reports 0 downloaded, an edited remote file replaces the local copy with no `name (1)` duplicate, delete rule. The remote path must be absolute on the computer's filesystem (a relative `/docs` was refused by the agent as outside its roots). A failed run names the first file's reason in the message.
- The picker refuses the storage root, Downloads and similar folders (Android's own rule).

## Encrypted backup
- Settings > Backup & restore exports hosts, tokens, favorites, bookmarks, pins and settings to an `.rfebackup` file and shares it, and imports one. The envelope is Flutter's (`rfe-backup` v1, PBKDF2-HMAC-SHA256 200k iterations, AES-256-GCM), so files move both ways. A JVM test decrypts a Flutter-made vector. Passphrase minimum is 12 characters. Import replaces everything owned by the app after a confirm, and asks for an app restart.
- Only the known secure keys (`rfe_token_*`, `rfe_fp_*`, device identity) are exported; unknown secure entries are never read into a backup.
- Emulator-verified: export writes the file and opens the share sheet; import with a wrong passphrase reports "Incorrect passphrase, or this backup file has been corrupted"; import with the right one restores; the RN-side envelope round trips. Importing the Flutter vector through the UI was not done (adb cannot type the non-ASCII passphrase); the JVM test covers it.

## Scheduled background work
- One periodic WorkManager job (`expo-background-task`, about every 6 hours, network required) runs the automatic photo backup (only when both "Enable photo backup" and "Back up automatically" are on) and the update check. Photo permission is read without prompting; no permission means no run. The job waits up to 8 minutes for the queued uploads before the process may be stopped.
- The task is defined in `mobile/index.js` (the app's entry), because the headless run evaluates the entry but never mounts the router; defining it in the root layout failed with "No task registered" on the emulator.
- Emulator-verified with the process dead: a new photo reached the computer (`148.jpg`) from a forced job run; the job survives a reboot (WorkManager re-registers it without opening the app); force-stop cancels it until the app opens again (Android behavior). Each run logs a one-line report (`[rfe-background]`).
- Not verified: OEM battery savers that kill the job or delay it past the interval (needs the owner's phone), and whether a foreground-service start is refused when the job begins on a locked, idle phone (the upload finished on the emulator; a stricter Android 14 or 15 device may queue it until the app opens).

## Updater
- Release channel: the same GitHub repo and `releases/latest/download/latest.json` the Flutter app reads, with the APK host allow-list; size and SHA-256 are checked before the installer opens. About & Support > Updates checks on demand; the Devices tab shows a banner. The APK is fetched in the background on Wi-Fi only. The installer needs the "Install unknown apps" permission, which the app sends the person to.
- Found while testing: the repo's Latest release is currently the agent (`agent-v1.42.7`), which has no `latest.json`, so the manifest URL returns 404 and neither app can find an update until an app release is Latest. The RN About screen now shows an "Update failed: HTTP 404" message instead of "Up to date" in that case (the manual check used to swallow the error).
- Not verified: download, verification and the installer prompt (no newer app release exists to serve, and the host allow-list blocks a local one).

## Licenses
- About & Support > Open-source licenses lists the built-in native code plus every JavaScript dependency with its license text (expandable), generated by `scripts/gen-licenses.mjs` into `src/features/support/licenses.json`. Emulator-verified: renders, scrolls, expands.

## Edge cases checked on the emulator (rfe-2mi.9)
- Revoked token: the host opens to "invalid or revoked token" with Retry; un-revoking and Retry recovers. Flutter behaves the same (no re-pair prompt).
- Network drop mid-upload (Wi-Fi and data off for 20 s, through a throttling TCP proxy so the transfer is slow enough to catch): the transfer fails as "Could not reach the computer"; it does not resume by itself. Back up now (or Retry) resumes on the same session and finishes byte-exact. Killing the app mid-upload leaves the transfer Paused; Back up now resumes it, also byte-exact.
- Bugs this found and fixed: concurrent chunk requests failed with "Cipher not initialized" (secure-store reads are now serialised); a failed photo upload was removed and re-queued, opening a new session each time, and the agent allows only four open sessions per device (a stalled phone could be locked out for a week: the agent has no way to close a session and sweeps stale ones after seven days), so failed and paused photo uploads now resume their own session; after a dropped connection the agent answers 409 TRANSFER_ACTIVE until it times out the old request, so the uploader waits and repeats (up to 8 times, 5 s apart).
- Storage full: a backup with no room to copy the photo said "Already up to date"; it now says how many photos could not be prepared and tries them again next run. No partial staging file is left behind.
- Reboot: the periodic job is back after boot. Transfers found running become Paused, as before.
- Device matrix (emulator only): 720x1280 at 280 dpi, font scale 1.6, dark mode, and a 1600x2560 tablet at 320 dpi all render without overflow or crashes. At 1.6x the bottom-tab labels nearly touch and long status lines truncate; the tablet gets the phone layout stretched, with no two-pane layout.

## Pairing without codes or fingerprints (owner request)
- Add computer > Find on LAN / Enter address: pick a computer and it asks the owner to approve at the PC. The PC shows a desktop notification with Approve/Reject (`notify-send` actions on Linux) or the owner runs `rfe-agent pair requests|accept|reject`; nothing is typed on the phone, and the certificate fingerprint is never shown, typed or scanned in the app (it is learned on first contact and pinned).
- Both sides show an 8-digit match code, HMAC-SHA256 keyed by the pinned certificate, so a machine relaying the connection shows a different code than the PC does. The TS and Go implementations share a test vector, and the live contract test checks the phone's code equals the one `rfe-agent pair requests` prints.
- Agent: `POST /v1/pair/request`, `GET /v1/pair/request/{id}?nonce=` (token handed out once), admin list/approve/reject; requests expire after 2 minutes, 3 wait at most, 6 asks per minute per address (in `protocol/openapi.yaml`). Approved devices start browse-only, like code-paired ones.
- Verified on the owner's phone with the real agent: request, matching codes (8863 5563 on both), approve from the PC, device listed, computer opens and lists its shared folder. Not verified: clicking the desktop notification button (approved through the CLI, which takes the same path); the web companion does not list requests yet.
- Login and Register no longer ask for a fingerprint (learned on first contact instead). Register still sends a one-time code, so on a hostile network that code could be handed to a relay; QR scan (code and fingerprint inside the QR) is unchanged and not re-tested here.

## Owner's phone walkthrough (USB, real agent)
- Verified on the phone: browse; download (28.6 MB, saved to Downloads, SHA-256 equal to the source); text view and edit; image view; upload through the system picker (landed on the PC); Move to Trash; photo backup of one album (one photo landed in `Phone Backup/<phone>/2026/2026-09/`). Permission denials show the agent's reason: "device lacks modify permission", "Delete failed: device lacks delete permission".
- Bug found and fixed: a refused download (403 CAPABILITY_DENIED) said "Could not reach the computer". The engine now fails with the agent's code and the app explains the missing permission.
- New devices are browse-only by design, and the app does not know its own permissions (the Download and Delete buttons show anyway). `rfe-agent allow <id> browse,download,upload,modify,delete,share|all|none` sets them from the PC.
- Setting the photo backup folder needs the web companion (or a config row plus agent restart, as done here).
- Also verified on the phone: search; Sync Rules (first sync and an incremental one with a new and a changed file); host settings screen; encrypted config export (file produced, passphrase rules enforced).
- Found and fixed: the host settings header, the Trusted certificates list and the connection diagnostics still showed a fingerprint prefix. They now show the address or a plain "pinned" state; the fingerprint appears nowhere in the app.
- Verified on the phone (second pass): share link create and revoke (link fetch is covered by the agent's tests; I could not read the full token from the screen); config export then import (file is an encrypted envelope with no plaintext host data; a restore keeps the host and token across a full restart); Login (audit shows it, the device becomes an owner device); Register on a scratch agent with no account (it refuses on an agent that already has one, with a clear message); connection diagnostics sheet (no fingerprint shown; Tailscale "No response" because the phone has no Tailscale).
- Performance pass on the phone (S23 Ultra, release build, 600 JPEGs of 1600x1200 in one folder, 20 flings): 1255 frames, 1.83% janky, 50th/90th/99th percentile 12/14/20 ms, app PSS 488 MB (graphics 131 MB, native 146 MB). Thumbnails rendered. No Flutter build on the phone, so there is no side-by-side number. Listings are cached: a new folder on the PC shows after pull-to-refresh.
- The desktop notification is sent with Approve and Reject actions (seen on the session D-Bus); clicking it is still unverified.
- Actions the device may not use are now hidden (download, delete, rename, copy/move, create, upload, share link), driven by `fileCapabilities` on GET /settings; the agent still enforces. Verified: an upload-only device sees only "Upload file" in the Create menu and no Download or Delete in the file sheet.
- `rfe-agent backup-dir [path|none]` sets the photo backup folder (restart the agent to apply).
- Accepted risk, for the security review: Register and Login trust the certificate on first contact, so a machine in the middle during that first request could read the one-time code or password. QR and approve-on-PC pairing do not have this gap.

## Scope decision
- The web companion (`agent/internal/webui`) is out of scope for this migration: the owner is taking it in a new direction. No work is planned on it here, and the code is left untouched. Consequences: pair requests are answered with the desktop notification or `rfe-agent pair accept|reject`; the photo backup folder and device permissions are set with the CLI (`rfe-agent allow`) or the agent's config until the new direction lands.

## Still needs a physical phone (recorded, not verified)
- Camera QR scan on a real camera and LAN discovery (mDNS): the emulator's NAT drops multicast. QR decoding itself is verified on the emulator's virtual-scene camera (see below).
- Secure-storage migration on a production Flutter install (needs the owner's signed Flutter build and its data; the reader is the same plugin code, JVM- and emulator-tested on fresh data only).
- Scroll, thumbnail-memory and throughput comparison against Flutter, and per-OEM device walkthroughs: emulator numbers are not comparable to a phone, and no Flutter build was installed for a side by side.
- Real Wi-Fi to cellular handover and OEM background-kill behavior.

## QR scan and Approve click (emulator / stub)
- QR scan: emulator `rfe_test` with `hw.camera.back = virtualscene`, the pairing QR (address 10.0.2.2, scratch agent) as the scene's wall poster, camera moved with the emulator gRPC `setPhysicalModel` (POSITION/ROTATION). The scanner decoded it and the app paired ("Paired with qr-scratch", host online). Real-camera scan on the phone is the owner's to do.
- Approve click: `contract/fake_notification_server.py` stands in for the notification service on a private D-Bus and answers the agent's Approve action, so the agent's click handling and pairing completion are tested (`RFE_NOTIFY_STUB=1`). A real click on the Plasma notification is still unverified.

## Second phone: Galaxy A53 (SM-A536E, Android 15, 1080x2400, serial R5CTB12ZLQH)
- Had an old Flutter 1.12.0 (versionCode 20) signed with a different key; `adb install -r` of the RN release (versionCode 81, production signer) failed with INSTALL_FAILED_UPDATE_INCOMPATIBLE. Uninstalled it (owner-approved, secondary phone) and installed RN: onboarding, Add computer > Enter address, pairing, Devices shows "zaid-pc Online v1.3.0 LAN", Files lists "RFE Files". This is not the iib.7 upgrade test (wrong key, no production data).
- Approve: the first request (code 2197 1184) expired after about 2.5 min with nobody clicking ("Nobody approved in time"). The retry (code 0414 2043, matching the phone) was accepted with `rfe-agent pair accept`, not a click. A real click on the Plasma notification and a real-camera QR scan are still unverified.
- Device `a19a1c99` is this A53; `e13a4291` is the earlier pairing. Neither is removed.
- Approve on the real desktop notification: verified on the A53 (request a3534abf, code 8261 2207, started by the owner on the phone, approved 4 s later; audit_log id 7 "approved at the computer"; no `pair accept` was run by the agent for it). The phone re-paired into the existing device row a19a1c99 (same client id), so no extra device exists. Audit text is identical for CLI and click, so this rests on no CLI accept having been run. Still unverified: the real-camera QR scan.
