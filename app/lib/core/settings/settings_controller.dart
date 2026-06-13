import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/view_prefs.dart';
import 'app_settings.dart';

/// Loads, resolves, and persists the two-tier [SettingsState] (Wave 0).
///
/// Storage layout in [SharedPreferences]:
///  - **App defaults** as flat scalar keys: `app.gridView` (bool),
///    `app.density` (enum name), `app.sortField` (enum name),
///    `app.sortAscending` (bool).
///  - **Device overrides** as one sparse JSON blob under
///    `settings.deviceOverrides.v1`, a map of `hostId -> { gridView?, density?,
///    sortField?, sortAscending? }`. A host is present only when it overrides
///    something; an absent host (or absent field) inherits the app default. A
///    JSON map is used instead of per-host-per-field flat keys so host ids
///    containing dots can't corrupt key parsing.
///
/// On first run after upgrade, [_migrate] folds the old `view_prefs.dart` keys
/// into this model (see that method).
class SettingsNotifier extends AsyncNotifier<SettingsState> {
  SharedPreferences? _prefs;

  static const _kGridView = 'app.gridView';
  static const _kDensity = 'app.density';
  static const _kSortField = 'app.sortField';
  static const _kSortAscending = 'app.sortAscending';
  static const _kOverrides = 'settings.deviceOverrides.v1';
  static const _kMigrated = 'settings.migrated.v1';

  // Legacy view_prefs.dart keys, read once during migration.
  static const _legacyGrid = 'rfe_grid_view_v1';
  static const _legacyDensity = 'rfe_density_v1';
  static const _legacySortField = 'rfe_sort_field_v1';
  static const _legacySortAscending = 'rfe_sort_ascending_v1';

  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    if (!(prefs.getBool(_kMigrated) ?? false)) {
      await _migrate(prefs);
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
      };
    }
    await _prefs?.setString(_kOverrides, jsonEncode(map));
  }

  SettingsState _read(SharedPreferences prefs) {
    final app = AppDefaults(
      gridView: prefs.getBool(_kGridView) ?? false,
      density: _densityFrom(prefs.getString(_kDensity)),
      sort: SortOrder(
        field: _sortFieldFrom(prefs.getString(_kSortField)),
        ascending: prefs.getBool(_kSortAscending) ?? true,
      ),
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
          density: m.containsKey('density')
              ? _densityFrom(m['density'] as String?)
              : null,
          sort: hasSort
              ? SortOrder(
                  field: _sortFieldFrom(m['sortField'] as String?),
                  ascending: m['sortAscending'] as bool? ?? true,
                )
              : null,
        );
        if (!o.isEmpty) overrides[entry.key] = o;
      }
    }
    return SettingsState(app: app, overrides: overrides);
  }

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

  static EntryDensity _densityFrom(String? name) => EntryDensity.values
      .firstWhere((d) => d.name == name, orElse: () => EntryDensity.comfortable);

  static SortField _sortFieldFrom(String? name) => SortField.values
      .firstWhere((f) => f.name == name, orElse: () => SortField.name);
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
