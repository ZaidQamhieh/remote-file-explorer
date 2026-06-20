# O1 + I3 Combined Wave — Handoff

Branch: `feat/o1-i3-rtl-diagnostics` off `master` at v1.17.0+30

## I3: Connection Diagnostics + Auto LAN↔Tailscale (DONE)

### What was done
- `agent_client.dart`: Added `probeLanFirst` param — health pings always start at address index 0 (LAN) with 3s connect timeout, fallback interceptor restores 10s. Fixes "never returns to LAN" bug caused by `_lastGoodAddrIndex` remembering Tailscale forever.
- `providers.dart`: Passes `probeLanFirst` through `buildClientForHost`.
- `host_card.dart`: `_ping()` uses `probeLanFirst: true`, timeout 8s. Added `_openDiagnostics` to ⋯ menu.
- `connection_diagnostics_sheet.dart`: NEW FILE — bottom sheet probing both LAN and Tailscale in parallel, showing reachability/latency/errors.

## O1: Arabic + RTL Support (PARTIAL)

### Infrastructure (DONE)
- `pubspec.yaml`: Added `flutter_localizations`, `intl`, `generate: true`
- `l10n.yaml`: `synthetic-package: false`, output to `lib/l10n/generated/`
- `lib/l10n/app_en.arb`: 300 English string keys with ICU placeholders
- `lib/l10n/app_ar.arb`: Full Arabic translations for all 300 keys
- `lib/l10n/generated/`: Generated localizations (app_localizations.dart, _en.dart, _ar.dart)
- `lib/core/l10n_ext.dart`: NEW — `extension L10n on BuildContext { AppLocalizations get l10n => ... }`
- `main.dart`: Wired `supportedLocales`, `localizationsDelegates`, `locale` from settings
- `app_settings.dart`: Added `Locale? locale` field to `AppDefaults`
- `settings_controller.dart`: Added `setLocale()`, reads/writes `app.locale` key

### RTL Layout Fixes (DONE)
- `explorer_screen.dart`: EdgeInsets → EdgeInsetsDirectional
- `destination_picker_sheet.dart`: AlignmentDirectional.centerStart
- `transfer_manager.dart`: AlignmentDirectional.centerStart/End
- `device_view_overrides_section.dart`: AlignmentDirectional.centerStart
- `app_settings_screen.dart`: AlignmentDirectional.centerStart

### String Localization — replacing hardcoded English with `context.l10n.*` (PARTIAL)

#### DONE (strings replaced with l10n calls):
- `host_card.dart` (manual)
- `connection_diagnostics_sheet.dart` (manual)
- `app_settings_screen.dart` (fork)
- `backup_restore_section.dart` (fork)
- `destination_picker_sheet.dart` (fork)
- `explorer_screen.dart` (fork)
- `batch_rename_sheet.dart` (fork)
- `batch_report.dart` (fork)
- `conflict_resolution_dialog.dart` (fork)
- `create_menu.dart` (fork)
- `favorites_sheet.dart` (fork)
- `meta_sheet.dart` (fork)
- `selection_bar.dart` (fork)
- `trash_screen.dart` (fork)
- `view_options_sheet.dart` (fork)

#### TODO (still have hardcoded English strings):
- `host_list_screen.dart`
- `storage_insights_screen.dart`
- `pairing_screen.dart`
- `photo_backup_screen.dart`
- `preview_actions.dart`
- `preview_common.dart`
- `text_editor.dart`
- `search_screen.dart`
- `settings_screen.dart`
- `update_banner.dart`
- `update_tile.dart`
- `device_view_overrides_section.dart`
- `transfer_manager.dart`
- `state_views.dart`

### After localization is complete:
1. Run `flutter analyze` — fix any issues
2. Run `flutter test` — all 406+ tests must pass
3. May need to add new ARB keys if forks missed any strings
4. Commit everything on the branch
5. Update Obsidian wiki: mark O1 and I3 as done in backlog
