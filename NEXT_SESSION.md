# NEXT_SESSION — start here

_Handoff written 2026-06-14 (second overnight autonomous session). Read this, then `CLAUDE.md`._

## State: v1.12.0+20 released OTA

All on master, all CI-green, bundled into **v1.12.0 (build 20)** by `./release.sh 1.12.0+20`
(published `~/.rfe-agent/updates/rfe-1.12.0-20.apk`, 78.4 MB). The phone will offer it on
next launch / "Check for updates".

**This session was purely client-side — no agent/openapi changes, so NO agent redeploy is
needed.** The running agent already serves everything these waves use.

Shipped this session, in order (each its own commit, CI-green before the next):

1. **file-visibility folded into the two-tier settings model** (`12f0df4`). It was the last
   global-only setting; now an app-default `VisibilityPrefs` + optional **wholesale**
   per-device override, resolved `deviceOverride ?? appDefault`. Mutation API moved off the
   old standalone notifier into `SettingsNotifier` (each method takes an optional `hostId`).
   One-time `_migrateVisibility` folds the legacy globals into the app default. Consumers
   (explorer/search/picker) re-pointed to `resolveVisibility(hostId)`. See memory.
2. **Wave D — transfers center** (`23786b8`). Speed/ETA (pure `computeSpeedEta` + a
   read-only `TransferSamplerNotifier` that only ticks while active — engine
   `transfer_state.dart` is byte-for-byte UNCHANGED), grouped collapsible sections,
   swipe pause/resume + remove-with-undo, a `MiniTransferBar` above the explorer bottom bar,
   clear-completed, inline error + retry.
3. **Wave E — preview & polish** (`9aea304`). Swipe between previewable siblings
   (`PreviewPager` over the visible listing; single-entry path preserved when no `siblings`
   passed), image tile→preview Hero, unified `PreviewTopBar` (Share/Save/Delete/Show-in-folder),
   text line-numbers toggle. **New dep: `share_plus ^10.1.4`** (only way to drive the OS
   share sheet — agent is pinned-TLS-only, no shareable URL).
4. **Wave F — theme/a11y/tablet** (`853cbce`). App-global `themeMode` + `dynamicColor` in
   `AppDefaults` (app-global, no per-device override); `main.dart` is now a ConsumerWidget
   wrapping `DynamicColorBuilder` with seed-palette fallback; Appearance section in App
   Settings; a11y/scaling hardening. **New dep: `dynamic_color ^1.7.0`.** Tablet two-pane
   was explicitly CUT (the brief's first-to-cut stretch).
5. **fix — moved the app-default file-visibility editor to the App Settings screen**
   (`d8b0a70`). Wave-0 fold-in had mounted it on the per-host screen; it now sits with the
   other app defaults (per-host screen keeps only the override section).

Test baseline grew (each wave added tests); `flutter analyze` clean, full CI suite green.

## Known follow-ups (not blockers)
- **NDK warning at build time:** `dynamic_color`/`share_plus` (and ~10 pre-existing plugins)
  request Android NDK 27.0.12077973; the project pins 26.3.11579264. **The release built
  fine** (NDK is backward-compatible) — this is a pre-existing warning, not new. Silence it
  if desired by setting `ndkVersion = "27.0.12077973"` in `app/android/app/build.gradle.kts`
  (only if NDK 27 is installed, else it could break the local build).
- `share_plus` 10.x: `Share.shareXFiles` is deprecated in favor of
  `SharePlus.instance.share(ShareParams(...))`; works now, migrate when convenient.
- Two near-duplicate extension tables still exist: `preview.dart`'s private sets vs the
  public `core/ui/entry_leading.dart` — fold preview onto the public source (deferred from
  the prior session).
- `transfer_state.dart` header comment says "Riverpod 3.x" — stale, it's 2.x (untouched as
  it's the sensitive engine file).

## Then pick next (priority)
1. **CD + auto-update bundle** (`docs/FUTURE_FEATURES.md` #1+#2): a GitHub Releases build job
   + repoint the updater at it + auto-check/download. **Biggest token saver** — removes the
   local `release.sh` Gradle build (~120s, 78 MB) from the loop. The resumable + CONNECTION
   fix is already in, so this is the clean next infra step.
2. **Wave H2/H3** (per-token path jail; post-transfer integrity check) — rest of the security
   wave, agent-led (bump agent minor + openapi in the same commit). Or **Wave N1** (encrypted
   config export) — small, removes the re-pair-everything-after-reinstall pain.
3. **Wave G5** (batch/pattern rename) or **M1** (advanced search filters) — small client-side
   power features.

## Workflow notes (kept from last session — still true)
Opus orchestrates + dispatches Sonnet workers per wave with disjoint file ownership, reviews
each diff, commits per wave (`feat:` then a separate `fix:` for review fixes), pushes, and
trusts CI for the full suite. Small/coupled fixes done inline (a cold worker re-reads context
Opus already has). No usage-meter tool exists, so every change is committed+pushed in its own
unit and this file kept current — an abrupt stop loses nothing.
