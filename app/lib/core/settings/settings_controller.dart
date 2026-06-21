import 'dart:convert';

import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/view_prefs.dart';
import '../storage/visibility_prefs.dart';
import 'app_settings.dart';

/// Loads, resolves, and persists the two-tier [SettingsState] (Wave 0).
///
/// Storage layout in [SharedPreferences]:
///  - **App defaults** as flat scalar keys: `app.gridView` (bool),
///    `app.density` (enum name), `app.sortField` (enum name),
///    `app.sortAscending` (bool).
///  - **App-default file visibility** as flat keys:
///    `app.visibility.hideDotfiles` (bool), `app.visibility.hiddenExtensions`
///    (JSON list string), `app.visibility.hiddenNames` (JSON list string).
///  - **Device overrides** as one sparse JSON blob under
///    `settings.deviceOverrides.v1`, a map of `hostId -> { gridView?, density?,
///    sortField?, sortAscending?, visibility? }`. A host is present only when it
///    overrides something; an absent host (or absent field) inherits the app
///    default. `visibility`, when present, is the host's FULL visibility blob
///    (`{ hideDotfiles, hiddenExtensions: [...], hiddenNames: [...] }`) —
///    visibility is wholesale (no field-level visibility overrides). A JSON map
///    is used instead of per-host-per-field flat keys so host ids containing
///    dots can't corrupt key parsing.
///
/// On first run after upgrade, [_migrate] folds the old `view_prefs.dart` keys
/// into this model, and [_migrateVisibility] folds the old
/// `visibility_prefs.dart` global keys into the app-default visibility (each
/// gated by its own one-shot flag).
class SettingsNotifier extends AsyncNotifier<SettingsState> {
  SharedPreferences? _prefs;

  static const _kGridView = 'app.gridView';
  static const _kDensity = 'app.density';
  static const _kSortField = 'app.sortField';
  static const _kSortAscending = 'app.sortAscending';
  static const _kVisHideDotfiles = 'app.visibility.hideDotfiles';
  static const _kVisHiddenExtensions = 'app.visibility.hiddenExtensions';
  static const _kVisHiddenNames = 'app.visibility.hiddenNames';
  static const _kThemeMode = 'app.themeMode';
  static const _kDynamicColor = 'app.dynamicColor';
  static const _kLocale = 'app.locale';
  static const _kNotifications = 'app.notificationsEnabled';
  static const _kLowDiskThreshold = 'app.lowDiskThresholdBytes';
  static const _kOverrides = 'settings.deviceOverrides.v1';
  static const _kMigrated = 'settings.migrated.v1';
  static const _kVisMigrated = 'settings.visibilityMigrated.v1';

  // Legacy view_prefs.dart keys, read once during migration.
  static const _legacyGrid = 'rfe_grid_view_v1';
  static const _legacyDensity = 'rfe_density_v1';
  static const _legacySortField = 'rfe_sort_field_v1';
  static const _legacySortAscending = 'rfe_sort_ascending_v1';

  // Legacy visibility_prefs.dart global keys, read once during migration.
  static const _legacyHideDotfiles = 'rfe_hide_dotfiles_v1';
  static const _legacyHiddenExtensions = 'rfe_hidden_extensions_v1';
  static const _legacyHiddenNames = 'rfe_hidden_names_v1';

  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    if (!(prefs.getBool(_kMigrated) ?? false)) {
      await _migrate(prefs);
    }
    if (!(prefs.getBool(_kVisMigrated) ?? false)) {
      await _migrateVisibility(prefs);
    }
    return _read(prefs);
  }

  // --- App defaults -------------------------------------------------------

  Future<void> setAppGridView(bool value) async {
    await _prefs?.setBool(_kGridView, value);
    _emit((s) => s.copyWith(app: s.app.copyWith(gridView: value)));
  }

  Future<void> setAppDensity(EntryDensity value) async {
    await _prefs?.setString(_kDensity, value.name);
    _emit((s) => s.copyWith(app: s.app.copyWith(density: value)));
  }

  Future<void> setAppSort(SortOrder value) async {
    await _prefs?.setString(_kSortField, value.field.name);
    await _prefs?.setBool(_kSortAscending, value.ascending);
    _emit((s) => s.copyWith(app: s.app.copyWith(sort: value)));
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _prefs?.setBool(_kNotifications, value);
    _emit(
      (s) => s.copyWith(app: s.app.copyWith(notificationsEnabled: value)),
    );
  }

  Future<void> setLowDiskThreshold(int bytes) async {
    await _prefs?.setInt(_kLowDiskThreshold, bytes);
    _emit(
      (s) => s.copyWith(app: s.app.copyWith(lowDiskThresholdBytes: bytes)),
    );
  }

  // --- Appearance (Wave F) ------------------------------------------------
  //
  // Theme mode and dynamic color are app-global only — no per-device override
  // (theme follows the whole app). Persisted as the enum name and a bool;
  // absent keys fall back to the defaults (system / dynamic-on).

  /// Sets the app-wide theme mode (system / light / dark).
  Future<void> setThemeMode(ThemeMode value) async {
    await _prefs?.setString(_kThemeMode, value.name);
    _emit((s) => s.copyWith(app: s.app.copyWith(themeMode: value)));
  }

  /// Sets whether to derive the color scheme from the platform's wallpaper
  /// colors (Material You). When off (or unsupported), the [Brand.seed] palette
  /// is used.
  Future<void> setDynamicColor(bool value) async {
    await _prefs?.setBool(_kDynamicColor, value);
    _emit((s) => s.copyWith(app: s.app.copyWith(dynamicColor: value)));
  }

  /// Sets the app locale override, or clears it (null = follow system).
  Future<void> setLocale(Locale? value) async {
    if (value == null) {
      await _prefs?.remove(_kLocale);
    } else {
      await _prefs?.setString(_kLocale, value.languageCode);
    }
    _emit((s) => s.copyWith(app: s.app.copyWithLocale(value)));
  }

  // --- File visibility (app default + per-device override) ----------------
  //
  // Each mutation takes an optional `hostId`: `null` edits the app default,
  // a non-null id edits (creating if needed) that host's wholesale
  // [VisibilityPrefs] override. When a host's override is first created it is
  // seeded from the host's currently-resolved visibility, so flipping a single
  // setting doesn't reset the others. These mirror the old
  // `VisibilityPrefsNotifier` API one-for-one.

  /// Sets whether dotfiles/dotfolders are hidden for [hostId] (or the app
  /// default when `hostId` is null).
  Future<void> setHideDotfiles(bool hide, {String? hostId}) =>
      _updateVisibility(hostId, (v) => v.copyWith(hideDotfiles: hide));

  /// Replaces the set of hidden extensions (normalized to lowercase).
  Future<void> setHiddenExtensions(Set<String> extensions, {String? hostId}) {
    final normalized = extensions.map((e) => e.toLowerCase()).toSet();
    return _updateVisibility(
      hostId,
      (v) => v.copyWith(hiddenExtensions: normalized),
    );
  }

  /// Replaces the set of hidden exact names.
  Future<void> setHiddenNames(Set<String> names, {String? hostId}) =>
      _updateVisibility(hostId, (v) => v.copyWith(hiddenNames: names));

  /// Adds a single exact name (e.g. `Thumbs.db`). No-op for blank input or a
  /// name already present (case-insensitively).
  Future<void> addName(String name, {String? hostId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value();
    return _updateVisibility(hostId, (v) {
      if (v.hiddenNames.any((n) => n.toLowerCase() == trimmed.toLowerCase())) {
        return v;
      }
      return v.copyWith(hiddenNames: {...v.hiddenNames, trimmed});
    });
  }

  /// Removes a single exact name (case-insensitive match).
  Future<void> removeName(String name, {String? hostId}) {
    final lower = name.toLowerCase();
    return _updateVisibility(
      hostId,
      (v) => v.copyWith(
        hiddenNames:
            v.hiddenNames.where((n) => n.toLowerCase() != lower).toSet(),
      ),
    );
  }

  /// Adds a single extension (lowercase, leading dots/whitespace stripped).
  /// No-op if the result is empty.
  Future<void> addExtension(String extension, {String? hostId}) {
    final normalized = extension.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );
    if (normalized.isEmpty) return Future.value();
    return _updateVisibility(
      hostId,
      (v) => v.copyWith(hiddenExtensions: {...v.hiddenExtensions, normalized}),
    );
  }

  /// Removes a single extension.
  Future<void> removeExtension(String extension, {String? hostId}) {
    final lower = extension.toLowerCase();
    return _updateVisibility(
      hostId,
      (v) => v.copyWith(
        hiddenExtensions: Set<String>.from(v.hiddenExtensions)..remove(lower),
      ),
    );
  }

  /// Applies [preset], adding its extensions/names additively.
  Future<void> applyPreset(VisibilityPreset preset, {String? hostId}) =>
      _updateVisibility(
        hostId,
        (v) => v.copyWith(
          hiddenExtensions: {...v.hiddenExtensions, ...preset.extensions},
          hiddenNames: {...v.hiddenNames, ...preset.names},
        ),
      );

  /// Removes [preset]'s extensions/names — the inverse of [applyPreset]. Names
  /// are matched case-insensitively (mirroring [isEntryHidden]).
  Future<void> removePreset(VisibilityPreset preset, {String? hostId}) {
    final lowerToRemove = preset.names.map((n) => n.toLowerCase()).toSet();
    return _updateVisibility(
      hostId,
      (v) => v.copyWith(
        hiddenExtensions: v.hiddenExtensions.difference(preset.extensions),
        hiddenNames:
            v.hiddenNames
                .where((n) => !lowerToRemove.contains(n.toLowerCase()))
                .toSet(),
      ),
    );
  }

  /// Turns this host's file-visibility override on or off. Turning it **on**
  /// seeds the host's override from its currently-resolved visibility (the app
  /// default, since it had no override) so nothing jumps; turning it **off**
  /// clears the override and the host falls back to the app default. Mirrors
  /// the view-settings "Use app default / Override" toggle pattern.
  Future<void> setDeviceVisibilityOverride(String hostId, bool override) async {
    final cur = state.valueOrNull ?? const SettingsState();
    if (override) {
      await _setOverrideVisibility(hostId, cur.resolveVisibility(hostId));
    } else {
      await _setOverrideVisibility(hostId, null);
    }
  }

  /// Reads the mutation target's current [VisibilityPrefs] (the app default, or
  /// the host's override-or-resolved-default when first creating an override),
  /// applies [mutate], and writes it back via the app-default or override path.
  Future<void> _updateVisibility(
    String? hostId,
    VisibilityPrefs Function(VisibilityPrefs) mutate,
  ) async {
    final cur = state.valueOrNull ?? const SettingsState();
    if (hostId == null) {
      await _setAppVisibility(mutate(cur.app.visibility));
    } else {
      // Base = the host's existing override, or (when first overriding) its
      // currently-resolved visibility so the new override starts from what the
      // user already sees.
      final base =
          cur.overridesFor(hostId).visibility ?? cur.resolveVisibility(hostId);
      await _setOverrideVisibility(hostId, mutate(base));
    }
  }

  /// Persists and emits the app-default visibility.
  Future<void> _setAppVisibility(VisibilityPrefs vis) async {
    await _prefs?.setBool(_kVisHideDotfiles, vis.hideDotfiles);
    await _prefs?.setString(
      _kVisHiddenExtensions,
      jsonEncode(vis.hiddenExtensions.toList()),
    );
    await _prefs?.setString(
      _kVisHiddenNames,
      jsonEncode(vis.hiddenNames.toList()),
    );
    _emit((s) => s.copyWith(app: s.app.copyWith(visibility: vis)));
  }

  /// Sets (or clears, when [vis] is null) the wholesale visibility override for
  /// [hostId], pruning the host entry if it ends up overriding nothing.
  Future<void> _setOverrideVisibility(
    String hostId,
    VisibilityPrefs? vis,
  ) async {
    final cur = state.valueOrNull ?? const SettingsState();
    final updated = cur.overridesFor(hostId).copyWithVisibility(vis);
    final next = Map<String, DeviceOverrides>.from(cur.overrides);
    if (updated.isEmpty) {
      next.remove(hostId);
    } else {
      next[hostId] = updated;
    }
    await _persistOverrides(next);
    _emit((s) => s.copyWith(overrides: next));
  }

  // --- Device overrides ---------------------------------------------------
  // Passing `null` clears that setting's override (the host falls back to the
  // app default). When a host ends up overriding nothing it is dropped from the
  // map so "absent == inherit" stays exact.

  Future<void> setDeviceGridView(String hostId, bool? value) =>
      _updateOverride(hostId, (o) => o.copyWithGridView(value));

  Future<void> setDeviceDensity(String hostId, EntryDensity? value) =>
      _updateOverride(hostId, (o) => o.copyWithDensity(value));

  Future<void> setDeviceSort(String hostId, SortOrder? value) =>
      _updateOverride(hostId, (o) => o.copyWithSort(value));

  /// Clears every override for [hostId] ("Reset to app defaults").
  Future<void> resetDevice(String hostId) async {
    final cur = state.valueOrNull ?? const SettingsState();
    if (!cur.overrides.containsKey(hostId)) return;
    final next = Map<String, DeviceOverrides>.from(cur.overrides)
      ..remove(hostId);
    await _persistOverrides(next);
    _emit((s) => s.copyWith(overrides: next));
  }

  Future<void> _updateOverride(
    String hostId,
    DeviceOverrides Function(DeviceOverrides) mutate,
  ) async {
    final cur = state.valueOrNull ?? const SettingsState();
    final updated = mutate(cur.overridesFor(hostId));
    final next = Map<String, DeviceOverrides>.from(cur.overrides);
    if (updated.isEmpty) {
      next.remove(hostId);
    } else {
      next[hostId] = updated;
    }
    await _persistOverrides(next);
    _emit((s) => s.copyWith(overrides: next));
  }

  void _emit(SettingsState Function(SettingsState) f) {
    final cur = state.valueOrNull ?? const SettingsState();
    state = AsyncData(f(cur));
  }

  // --- Persistence --------------------------------------------------------

  Future<void> _persistOverrides(Map<String, DeviceOverrides> overrides) async {
    if (overrides.isEmpty) {
      await _prefs?.remove(_kOverrides);
      return;
    }
    final map = <String, Map<String, dynamic>>{};
    for (final entry in overrides.entries) {
      final o = entry.value;
      if (o.isEmpty) continue;
      map[entry.key] = {
        if (o.gridView != null) 'gridView': o.gridView,
        if (o.density != null) 'density': o.density!.name,
        if (o.sort != null) 'sortField': o.sort!.field.name,
        if (o.sort != null) 'sortAscending': o.sort!.ascending,
        if (o.visibility != null)
          'visibility': _visibilityToJson(o.visibility!),
      };
    }
    await _prefs?.setString(_kOverrides, jsonEncode(map));
  }

  SettingsState _read(SharedPreferences prefs) {
    final localeCode = prefs.getString(_kLocale);
    final app = AppDefaults(
      gridView: prefs.getBool(_kGridView) ?? false,
      density: _densityFrom(prefs.getString(_kDensity)),
      sort: SortOrder(
        field: _sortFieldFrom(prefs.getString(_kSortField)),
        ascending: prefs.getBool(_kSortAscending) ?? true,
      ),
      visibility: _readAppVisibility(prefs),
      themeMode: _themeModeFrom(prefs.getString(_kThemeMode)),
      dynamicColor: prefs.getBool(_kDynamicColor) ?? true,
      locale: localeCode != null ? Locale(localeCode) : null,
      notificationsEnabled: prefs.getBool(_kNotifications) ?? true,
      lowDiskThresholdBytes:
          prefs.getInt(_kLowDiskThreshold) ?? 1024 * 1024 * 1024,
    );

    final overrides = <String, DeviceOverrides>{};
    final raw = prefs.getString(_kOverrides);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final m = entry.value as Map<String, dynamic>;
        final hasSort = m.containsKey('sortField');
        final o = DeviceOverrides(
          gridView: m['gridView'] as bool?,
          density:
              m.containsKey('density')
                  ? _densityFrom(m['density'] as String?)
                  : null,
          sort:
              hasSort
                  ? SortOrder(
                    field: _sortFieldFrom(m['sortField'] as String?),
                    ascending: m['sortAscending'] as bool? ?? true,
                  )
                  : null,
          visibility:
              m.containsKey('visibility')
                  ? _visibilityFromJson(m['visibility'] as Map<String, dynamic>)
                  : null,
        );
        if (!o.isEmpty) overrides[entry.key] = o;
      }
    }
    return SettingsState(app: app, overrides: overrides);
  }

  /// Reads the app-default visibility from its flat keys. Missing keys fall
  /// back to [VisibilityPrefs]'s defaults (`hideDotfiles: true`, empty sets).
  VisibilityPrefs _readAppVisibility(SharedPreferences prefs) =>
      VisibilityPrefs(
        hideDotfiles: prefs.getBool(_kVisHideDotfiles) ?? true,
        hiddenExtensions: _decodeStringSet(
          prefs.getString(_kVisHiddenExtensions),
        ),
        hiddenNames: _decodeStringSet(prefs.getString(_kVisHiddenNames)),
      );

  // --- Migration ----------------------------------------------------------

  /// One-time fold of the legacy `view_prefs.dart` keys into the two-tier
  /// model. Density and sort were already global → they become app defaults.
  /// list/grid was a per-host map whose implicit default was list (`false`):
  /// hosts matching that default collapse into the app default (no override),
  /// genuine divergences (`true`) become explicit per-device overrides — so a
  /// user's current behavior is never lost silently. Legacy keys are removed
  /// afterward; the migration flag prevents re-running.
  Future<void> _migrate(SharedPreferences prefs) async {
    // App defaults from the old globals.
    await prefs.setBool(_kGridView, false);
    final oldDensity = prefs.getString(_legacyDensity);
    if (oldDensity != null) await prefs.setString(_kDensity, oldDensity);
    final oldSortField = prefs.getString(_legacySortField);
    if (oldSortField != null) await prefs.setString(_kSortField, oldSortField);
    final oldSortAsc = prefs.getBool(_legacySortAscending);
    if (oldSortAsc != null) await prefs.setBool(_kSortAscending, oldSortAsc);

    // Per-host grid map → overrides for divergences only.
    final overrides = <String, DeviceOverrides>{};
    final rawGrid = prefs.getString(_legacyGrid);
    if (rawGrid != null) {
      final decoded = jsonDecode(rawGrid) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        if (entry.value == true) {
          overrides[entry.key] = const DeviceOverrides(gridView: true);
        }
      }
    }
    await _persistOverrides(overrides);

    // Clean up legacy keys and mark done.
    await prefs.remove(_legacyGrid);
    await prefs.remove(_legacyDensity);
    await prefs.remove(_legacySortField);
    await prefs.remove(_legacySortAscending);
    await prefs.setBool(_kMigrated, true);
  }

  /// One-time fold of the legacy `visibility_prefs.dart` global keys
  /// (`rfe_hide_dotfiles_v1`/`rfe_hidden_extensions_v1`/`rfe_hidden_names_v1`)
  /// into the app-default visibility, then removes them. Runs once, gated by
  /// its own flag so it is independent of the view migration above. If the
  /// legacy keys are absent the defaults apply (`hideDotfiles: true`, empty
  /// sets) — the user's current global visibility is never lost.
  Future<void> _migrateVisibility(SharedPreferences prefs) async {
    final hideDotfiles = prefs.getBool(_legacyHideDotfiles);
    if (hideDotfiles != null) {
      await prefs.setBool(_kVisHideDotfiles, hideDotfiles);
    }
    final extensions = prefs.getString(_legacyHiddenExtensions);
    if (extensions != null) {
      await prefs.setString(_kVisHiddenExtensions, extensions);
    }
    final names = prefs.getString(_legacyHiddenNames);
    if (names != null) {
      await prefs.setString(_kVisHiddenNames, names);
    }

    await prefs.remove(_legacyHideDotfiles);
    await prefs.remove(_legacyHiddenExtensions);
    await prefs.remove(_legacyHiddenNames);
    await prefs.setBool(_kVisMigrated, true);
  }

  // --- Visibility (de)serialization --------------------------------------

  /// The per-host override visibility blob: `{ hideDotfiles, hiddenExtensions:
  /// [...], hiddenNames: [...] }`.
  static Map<String, dynamic> _visibilityToJson(VisibilityPrefs v) => {
    'hideDotfiles': v.hideDotfiles,
    'hiddenExtensions': v.hiddenExtensions.toList(),
    'hiddenNames': v.hiddenNames.toList(),
  };

  static VisibilityPrefs _visibilityFromJson(Map<String, dynamic> m) =>
      VisibilityPrefs(
        hideDotfiles: m['hideDotfiles'] as bool? ?? true,
        hiddenExtensions:
            (m['hiddenExtensions'] as List?)?.cast<String>().toSet() ?? {},
        hiddenNames: (m['hiddenNames'] as List?)?.cast<String>().toSet() ?? {},
      );

  /// Decodes a JSON list string (as written by [_setAppVisibility]) into a set,
  /// or an empty set when [raw] is null.
  static Set<String> _decodeStringSet(String? raw) =>
      raw == null
          ? <String>{}
          : (jsonDecode(raw) as List).cast<String>().toSet();

  static EntryDensity _densityFrom(String? name) =>
      EntryDensity.values.firstWhere(
        (d) => d.name == name,
        orElse: () => EntryDensity.comfortable,
      );

  static SortField _sortFieldFrom(String? name) => SortField.values.firstWhere(
    (f) => f.name == name,
    orElse: () => SortField.name,
  );

  static ThemeMode _themeModeFrom(String? name) => ThemeMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => ThemeMode.system,
  );
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
