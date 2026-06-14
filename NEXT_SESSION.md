# NEXT_SESSION — start here

_Handoff written 2026-06-14 (overnight autonomous session). Read this, then `CLAUDE.md`._

## State: v1.11.0+19 released OTA

All on master, all CI-green, bundled into **v1.11.0 (build 19)** by `./release.sh 1.11.0+19`
(published `~/.rfe-agent/updates/rfe-1.11.0-19.apk`, 77.3 MB). The phone will offer it on
next launch / "Check for updates".

This session shipped, in order:

1. **Agent redeploy (was the blocking item from the previous handoff).** The running
   `~/.local/bin/rfe-agent` was stale (Jun 12, predated G1/G3/G4). Rebuilt + restarted; it
   now serves `PUT /v1/content`, the copy/move `overwrite` flag, duplicate-in-place, and
   409-on-upload-collision. Then redeployed AGAIN after H1 (below) so the live binary
   records session metadata. **It still reports `version:"1.1.0"` in /health** — the version
   string in the agent code was never bumped; harmless, but bump it if you touch agent
   versioning. Health verified OK (LAN 192.168.1.106:8765, Tailscale 100.126.220.27:8765).

2. **Wave H1 — active sessions** (`359ca4e`, CI green). Each authenticated request now
   records the caller's **network address** (RemoteAddr host, port stripped) and **app
   version** (new `X-RFE-Client-Version: <name>+<build>` header) alongside last-seen. The
   devices list (`GET /v1/devices`) returns `lastAddress`/`lastVersion`; the per-host
   Settings → Paired devices rows show `Active · 192.168.1.x · v1.11.0+19 · 2m ago`
   (new `formatRelative` helper). Device list + revoke already existed (Wave 3); this added
   the metadata + relative-time UI. New DB columns migrate in (default `''` for old rows, so
   a device shows blank address/version until its first request on the new agent). Built by
   **two parallel Sonnet workers** (agent + client) against a frozen contract; openapi
   updated in the same commit. See memory `project-rfe-waveH1-active-sessions`.

3. **fix: resumable APK update download + clear connection errors** (`d4cac27`, CI green).
   This fixes the previously-reported "update failed: AgentApiException(0,UNKNOWN)" — the
   77 MB APK download was non-resumable (`deleteOnError:true`, no Range), so any blip
   nuked the partial and failed opaquely. `downloadApk` now mirrors `downloadFile` (Range
   resume, append, keep partial on error, 206-vs-200 guard, absolute progress); the update
   dialog resumes from the on-disk partial and Retry/after-cancel continue instead of
   restarting. `_apiError` now maps connection/timeout DioExceptions to a readable
   `CONNECTION` error. ⚠️ **Test gap (intentional):** the HTTP Range path has no unit test —
   the repo mocks `AgentClient` at the state layer, not over HTTP, and `downloadFile` (the
   proven method this mirrors) also has none. CI covers compile/analyze.

4. **Wave G2 — persistent cut/copy/paste clipboard** (`cc87f46`, CI green). Built by one
   Sonnet worker against a frozen design. ⚠️ **This is a visible UX change the owner has not
   seen yet** — the selection bar's **Move → Cut**, and Cut/Copy now fill an app-scoped
   clipboard (`clipboard_state.dart`, a non-autoDispose `clipboardProvider`) instead of
   opening a destination picker immediately. You then navigate to any folder on the same
   host and tap a new **Paste** FAB (above Upload). Cut clears the clipboard on success,
   copy keeps it. Reuses the existing collision → Keep both/Overwrite/Skip dialog (G3).
   **Consequence:** the destination-picker sheet/state (`destination_picker_*.dart` + their
   2 tests) are now **unused** — kept, not deleted. Good follow-up: repurpose them as a
   "Paste to…" target picker (long-press Paste → choose any folder without navigating), or
   delete if not wanted. See memory `project-rfe-waveG2-clipboard`.

## If the owner dislikes the G2 UX change
The clipboard model fully replaced the one-shot move/copy destination dialog. If the owner
wants the old picker back (or both), the picker code is intact (`showDestinationPicker`);
revert/augment `selection_bar.dart` + `explorer_screen.dart`. This was a deliberate "real
file-manager mental model" call per the roadmap, made autonomously.

## Then pick next (priority)
1. **Loose end: fold file-visibility into the Wave 0 two-tier model** (app default +
   per-device override). It's the only setting still global-only; the addendum's Wave 0
   explicitly left it for a follow-up. Medium, client-only.
2. **UI Waves D → E → F** (transfers center → preview polish → theme/a11y/tablet),
   `docs/ui-redesign-plan.md`. The big remaining UI arc; D is the next one. Release 1.12.0
   after.
3. **CD + auto-update bundle** (`docs/FUTURE_FEATURES.md` #1+#2): GitHub Releases build job
   + repoint updater at it + auto-check/download. Biggest token saver — removes the local
   `release.sh` Gradle build (~80s, 77 MB) from the loop. With the resumable+CONNECTION
   fix already in, this is the natural next infra step.
4. **Wave H2/H3** (per-token path jail; post-transfer integrity check) — rest of the
   security wave, agent-led. Or **Wave N1** (encrypted config export) — small, removes the
   re-pair-everything-after-reinstall pain.

## Token note (owner is cost-sensitive)
Opus orchestration is the expensive part, not the Sonnet workers. This session: H1 and G2
went to workers (large/parallelizable or substantial single-domain); the resumable-download
fix was done inline (small + coupled — a cold worker would re-read all the context Opus
already had). Keep that split. There is **no usage-meter tool available**, so "stop at
90-95%" can't be polled — instead every change here was committed+pushed in its own unit
(CI is the free safety net) and this file was kept current, so any abrupt stop loses nothing.
