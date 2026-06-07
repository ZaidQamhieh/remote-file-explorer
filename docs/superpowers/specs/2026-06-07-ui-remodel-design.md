# UI Remodel — "Distinctive Modern" — Design Spec

Date: 2026-06-07. Status: approved (user delegated full discretion).

## Goal

Lift the app from functional-but-cramped to a cohesive, distinctive-modern look,
applied across every screen, with light + dark themes that follow the system
setting and subtle motion. Behaviour is preserved; this is visual/layout +
two small functional add-ons (below).

## Decisions (locked)

- **Direction:** distinctive modern — confident, branded, tactile; clean not flashy.
- **Theme mode:** light + dark, `ThemeMode.system`.
- **Scope:** all screens.
- **Motion:** subtle (smooth routes, gentle list fade-ins, existing haptics).
- **Identity:** Indigo primary `#4F5BD5` + Cyan accent `#00B4D8`; green=online,
  red=error. Consistent shape language: card radius 16, sheet radius 28, tonal
  surface elevation, clear section headers, roomy spacing.

## Constraints

- Riverpod stays **2.6.1**. All network access through the pinned `AgentClient`.
- Android-only paths stay guarded by `Platform.isAndroid`.
- Contract-first: the one protocol addition is `DELETE /v1/devices/{id}`.

## A. Foundation (built first, shared by everything)

New `lib/core/theme/`:
- **`tokens.dart`** — `Spacing` (xs4 sm8 md16 lg24 xl32), `Radii`
  (card16 sheet28 chip10), `Elevations`, brand seed constants.
- **`app_theme.dart`** — `AppTheme.light` / `AppTheme.dark` via
  `ColorScheme.fromSeed` (indigo seed, cyan secondary), Material 3, with
  centralized component themes: Card, ListTile, AppBar, FilledButton,
  OutlinedButton, SnackBar, InputDecoration, Dialog, BottomSheet, Chip. This is
  where most of the de-cramping happens, app-wide, in one place.
- **`motion.dart`** — `fadeThroughPageRoute` for screen transitions; an
  `AppearListItem` wrapper (gentle fade/slide on first build).

`main.dart`: `theme: AppTheme.light, darkTheme: AppTheme.dark,
themeMode: ThemeMode.system`.

`core/ui/feedback.dart`: success colour pulls from the scheme (works in dark).

## B. Per-screen layout (parallelizable after foundation)

- **Host list:** taller cards, status dot in a tonal circle, online/offline
  pill, name `titleMedium`, muted address line, relative last-seen; roomier
  empty state; version in app-bar subtitle.
- **Explorer:** breadcrumb as scrollable chips (current filled, parents tonal,
  still drop targets); roomier list rows with type icon in a tonal square,
  size·date single muted subtitle; grid cards from theme; multi-select bar with
  count header + clearer icons. Subtle list fade-in.
- **Settings:** real sections with headers — Agent · Access · Allowed folders ·
  Paired devices · Updates · About — each a grouped card. Device rows show a
  status line; **revoked devices get a remove (trash) action** wired to the new
  `DELETE /v1/devices/{id}` (see add-on 2).
- **Pairing / Search / Transfers / Preview:** lighter passes — themed chrome,
  consistent empty/error/loading states (reuse `state_views`), grouped transfer
  progress, styled pairing error card.

## Add-ons

1. **Update-cache cleanup (app):** the updater downloads to external cache as
   `update-<versionCode>.apk`; these accumulate. After saving the new APK,
   delete any other `update-*.apk` in that directory so only the current one
   remains. (User-reported: "every update gets cached… remove the older one.")
2. **Remove revoked devices (agent + app):** agent only had `RevokeDevice`
   (sets revoked=1) and no hard-delete, so revoked rows linger with no way to
   clear them. Add `store.DeleteDevice(id)` + `DELETE /v1/devices/{id}` +
   `AgentClient.deleteDevice`, surfaced as the trash action in Settings.

## Verification

`flutter analyze lib/` clean; `flutter test` green (add a theme smoke test +
device-delete store test); Go suite green; `flutter build apk` succeeds;
Riverpod pinned 2.6.1. Manual: light/dark both legible on host list, explorer,
settings; revoked device removable; only one `update-*.apk` after an update.
Ship via `./release.sh`.

## Out of scope

Per-screen redesigns beyond layout/spacing (no new features), animation beyond
"subtle", in-app manual theme toggle (we follow system).
