import 'dart:ui' show Color, Locale;

import 'package:flutter/material.dart' show ThemeMode;

import '../storage/view_prefs.dart';
import '../storage/visibility_prefs.dart';

/// Two-tier settings model (Wave 0).
///
/// One source of truth — [AppDefaults] — plus sparse per-device [DeviceOverrides]
/// that are only present when a host has *deliberately* diverged. The effective
/// value for a host is resolved as `deviceOverride ?? appDefault ?? fallback`
/// (see [SettingsState.resolveView]). Absence of an override means "inherit the
/// app default"; there is no silent per-host divergence.
///
/// v1 covers the three overridable *view* settings (list/grid, density, sort).
/// The structure is intentionally extensible: future waves (theme, transfer
/// policy, file visibility) add fields here and resolve them the same way.

/// The app-wide defaults — the "general settings" surface the owner asked for.
/// Every overridable setting has exactly one default value here.
class AppDefaults {
  const AppDefaults({
    this.gridView = false,
    this.density = EntryDensity.comfortable,
    this.sort = const SortOrder(),
    this.visibility = const VisibilityPrefs(),
    this.themeMode = ThemeMode.system,
    this.dynamicColor = true,
    this.locale,
    this.notificationsEnabled = true,
    this.lowDiskThresholdBytes = 1024 * 1024 * 1024,
    this.appLockEnabled = false,
    this.amoledDark = false,
    this.seedColor,
    this.watchedFolders = const {},
    this.weeklyDigestEnabled = false,
  });

  /// Default list/grid choice. `true` = grid. Hosts without an override follow
  /// this.
  final bool gridView;
  final EntryDensity density;
  final SortOrder sort;

  /// Default file-visibility preferences (hide-dotfiles + hidden
  /// extensions/names). Unlike the view settings this is a small composite
  /// value, but it resolves the same way: a host either inherits this default
  /// wholesale or carries its own full [VisibilityPrefs] override.
  final VisibilityPrefs visibility;

  /// App-wide theme mode (Wave F). Unlike the view/visibility settings this is
  /// **app-global only** — there is no per-device override (theme follows the
  /// whole app, per `docs/next-waves-addendum.md`). Defaults to
  /// [ThemeMode.system].
  final ThemeMode themeMode;

  /// Whether to derive the color scheme from the platform's wallpaper colors
  /// (Material You / dynamic color), when the platform provides them. Also
  /// app-global only. Defaults to `true`; falls back to the [Brand.seed]
  /// palette when off or when the platform has no dynamic scheme.
  final bool dynamicColor;

  /// Explicit locale override, or `null` to follow the system locale.
  final Locale? locale;

  /// Whether transfer notifications (foreground service + completion) are
  /// enabled. App-global only — no per-device override.
  final bool notificationsEnabled;

  /// Free-space threshold (bytes) below which drives show a low-disk warning
  /// on the host card. Default 1 GB.
  final int lowDiskThresholdBytes;

  final bool appLockEnabled;

  final bool amoledDark;

  /// Custom seed color for the color scheme. `null` = default [Brand.seed].
  final Color? seedColor;

  /// Remote folder paths (on the host) that the user has opted in to
  /// watch for new files. When the SSE stream fires a create event whose
  /// parent directory is in this set, a local notification is shown.
  final Set<String> watchedFolders;

  /// Opt-in (L4): show a once-a-week notification summarizing storage trends
  /// across paired hosts. App-global only. Defaults to off.
  final bool weeklyDigestEnabled;

  AppDefaults copyWith({
    bool? gridView,
    EntryDensity? density,
    SortOrder? sort,
    VisibilityPrefs? visibility,
    ThemeMode? themeMode,
    bool? dynamicColor,
    bool? notificationsEnabled,
    int? lowDiskThresholdBytes,
    bool? appLockEnabled,
    bool? amoledDark,
    Set<String>? watchedFolders,
    bool? weeklyDigestEnabled,
  }) => AppDefaults(
    gridView: gridView ?? this.gridView,
    density: density ?? this.density,
    sort: sort ?? this.sort,
    visibility: visibility ?? this.visibility,
    themeMode: themeMode ?? this.themeMode,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    locale: locale,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    lowDiskThresholdBytes: lowDiskThresholdBytes ?? this.lowDiskThresholdBytes,
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    amoledDark: amoledDark ?? this.amoledDark,
    seedColor: seedColor,
    watchedFolders: watchedFolders ?? this.watchedFolders,
    weeklyDigestEnabled: weeklyDigestEnabled ?? this.weeklyDigestEnabled,
  );

  AppDefaults copyWithLocale(Locale? value) => AppDefaults(
    gridView: gridView,
    density: density,
    sort: sort,
    visibility: visibility,
    themeMode: themeMode,
    dynamicColor: dynamicColor,
    locale: value,
    notificationsEnabled: notificationsEnabled,
    lowDiskThresholdBytes: lowDiskThresholdBytes,
    appLockEnabled: appLockEnabled,
    amoledDark: amoledDark,
    seedColor: seedColor,
    watchedFolders: watchedFolders,
    weeklyDigestEnabled: weeklyDigestEnabled,
  );

  AppDefaults copyWithSeedColor(Color? value) => AppDefaults(
    gridView: gridView,
    density: density,
    sort: sort,
    visibility: visibility,
    themeMode: themeMode,
    dynamicColor: dynamicColor,
    locale: locale,
    notificationsEnabled: notificationsEnabled,
    lowDiskThresholdBytes: lowDiskThresholdBytes,
    appLockEnabled: appLockEnabled,
    amoledDark: amoledDark,
    seedColor: value,
    watchedFolders: watchedFolders,
    weeklyDigestEnabled: weeklyDigestEnabled,
  );

  @override
  bool operator ==(Object other) =>
      other is AppDefaults &&
      other.gridView == gridView &&
      other.density == density &&
      other.sort == sort &&
      other.visibility == visibility &&
      other.themeMode == themeMode &&
      other.dynamicColor == dynamicColor &&
      other.locale == locale &&
      other.notificationsEnabled == notificationsEnabled &&
      other.lowDiskThresholdBytes == lowDiskThresholdBytes &&
      other.appLockEnabled == appLockEnabled &&
      other.amoledDark == amoledDark &&
      other.seedColor == seedColor &&
      other.watchedFolders.length == watchedFolders.length &&
      other.watchedFolders.containsAll(watchedFolders) &&
      other.weeklyDigestEnabled == weeklyDigestEnabled;

  @override
  int get hashCode => Object.hash(
    gridView,
    density,
    sort,
    visibility,
    themeMode,
    dynamicColor,
    locale,
    notificationsEnabled,
    lowDiskThresholdBytes,
    appLockEnabled,
    amoledDark,
    seedColor,
    Object.hashAllUnordered(watchedFolders),
    weeklyDigestEnabled,
  );
}

/// A single host's overrides. Each field is nullable: `null` = inherit the app
/// default for that setting, non-null = this host has explicitly overridden it.
///
/// The `copyWithX` helpers deliberately *replace* a field with the given
/// (nullable) value so callers can clear an override by passing `null` — a
/// normal `copyWith` can't express "set this back to null".
class DeviceOverrides {
  const DeviceOverrides({
    this.gridView,
    this.density,
    this.sort,
    this.visibility,
  });

  final bool? gridView;
  final EntryDensity? density;
  final SortOrder? sort;

  /// This host's full file-visibility override, or `null` to inherit the app
  /// default. Visibility is *wholesale*: when present this is the complete
  /// [VisibilityPrefs] for the host (no field-level visibility overrides).
  final VisibilityPrefs? visibility;

  /// True when this host overrides nothing — equivalent to having no entry at
  /// all. Such entries are pruned on write so "absent == inherit" stays exact.
  bool get isEmpty =>
      gridView == null && density == null && sort == null && visibility == null;

  DeviceOverrides copyWithGridView(bool? value) => DeviceOverrides(
    gridView: value,
    density: density,
    sort: sort,
    visibility: visibility,
  );
  DeviceOverrides copyWithDensity(EntryDensity? value) => DeviceOverrides(
    gridView: gridView,
    density: value,
    sort: sort,
    visibility: visibility,
  );
  DeviceOverrides copyWithSort(SortOrder? value) => DeviceOverrides(
    gridView: gridView,
    density: density,
    sort: value,
    visibility: visibility,
  );
  DeviceOverrides copyWithVisibility(VisibilityPrefs? value) => DeviceOverrides(
    gridView: gridView,
    density: density,
    sort: sort,
    visibility: value,
  );

  @override
  bool operator ==(Object other) =>
      other is DeviceOverrides &&
      other.gridView == gridView &&
      other.density == density &&
      other.sort == sort &&
      other.visibility == visibility;

  @override
  int get hashCode => Object.hash(gridView, density, sort, visibility);
}

/// The effective, resolved view settings for one host — what the explorer
/// actually renders with. Produced by [SettingsState.resolveView].
class ResolvedView {
  const ResolvedView({
    required this.gridView,
    required this.density,
    required this.sort,
  });

  final bool gridView;
  final EntryDensity density;
  final SortOrder sort;

  @override
  bool operator ==(Object other) =>
      other is ResolvedView &&
      other.gridView == gridView &&
      other.density == density &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(gridView, density, sort);
}

/// Immutable snapshot of all settings: the single [app] defaults plus a sparse
/// map of per-host [overrides] (only hosts that override something appear).
class SettingsState {
  const SettingsState({
    this.app = const AppDefaults(),
    this.overrides = const {},
  });

  final AppDefaults app;
  final Map<String, DeviceOverrides> overrides;

  /// The override bundle for [hostId], or an empty one if the host inherits
  /// everything.
  DeviceOverrides overridesFor(String hostId) =>
      overrides[hostId] ?? const DeviceOverrides();

  /// Whether [hostId] overrides at least one setting.
  bool hasOverride(String hostId) => !overridesFor(hostId).isEmpty;

  /// Whether [folderPath] is in the watched-folders set (L3).
  bool isWatched(String folderPath) => app.watchedFolders.contains(folderPath);

  /// Resolves the effective view settings for [hostId]:
  /// `deviceOverride ?? appDefault`.
  ResolvedView resolveView(String hostId) {
    final o = overridesFor(hostId);
    return ResolvedView(
      gridView: o.gridView ?? app.gridView,
      density: o.density ?? app.density,
      sort: o.sort ?? app.sort,
    );
  }

  /// Resolves the effective file-visibility prefs for [hostId]:
  /// `deviceOverride ?? appDefault`. Visibility is wholesale, so this returns
  /// either the host's full override or the app default unchanged.
  VisibilityPrefs resolveVisibility(String hostId) =>
      overridesFor(hostId).visibility ?? app.visibility;

  SettingsState copyWith({
    AppDefaults? app,
    Map<String, DeviceOverrides>? overrides,
  }) => SettingsState(
    app: app ?? this.app,
    overrides: overrides ?? this.overrides,
  );
}
