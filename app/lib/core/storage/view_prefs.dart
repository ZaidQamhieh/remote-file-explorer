import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// View-layer preferences for the explorer: list/grid mode (per host), entry
/// density, and sort order. Persisted in [SharedPreferences] so they survive
/// app restarts, following the same load-then-persist pattern as
/// `core/storage/favorites.dart` and `core/storage/host_store.dart`.

const _kGridViewKey = 'rfe_grid_view_v1';
const _kDensityKey = 'rfe_density_v1';
const _kSortFieldKey = 'rfe_sort_field_v1';
const _kSortAscendingKey = 'rfe_sort_ascending_v1';

// ---------------------------------------------------------------------------
// Sort order
// ---------------------------------------------------------------------------

/// Fields the explorer listing can be sorted by. Directories are always
/// listed before files regardless of [SortField] (see
/// `explorer_state._sortEntries`); this enum only controls the comparator
/// used within each group.
enum SortField { name, size, date, type }

/// A sort field plus direction. Immutable; [copyWith] flips/changes either
/// independently.
class SortOrder {
  const SortOrder({this.field = SortField.name, this.ascending = true});

  final SortField field;
  final bool ascending;

  SortOrder copyWith({SortField? field, bool? ascending}) => SortOrder(
        field: field ?? this.field,
        ascending: ascending ?? this.ascending,
      );

  @override
  bool operator ==(Object other) =>
      other is SortOrder &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

// ---------------------------------------------------------------------------
// Density
// ---------------------------------------------------------------------------

/// List-tile density. Comfortable is the default two-line row (~72dp);
/// compact is a single-line row (~52dp) with metadata inline after the name.
/// Grid cell anatomy is unaffected by density (per the design spec).
enum EntryDensity { comfortable, compact }

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Snapshot of persisted view preferences.
class ViewPrefs {
  const ViewPrefs({
    this.gridViewByHost = const {},
    this.density = EntryDensity.comfortable,
    this.sort = const SortOrder(),
  });

  /// Per-host list/grid choice. `true` = grid view. Hosts not present here
  /// default to list view.
  final Map<String, bool> gridViewByHost;
  final EntryDensity density;
  final SortOrder sort;

  /// Whether [hostId] should currently render its listing as a grid.
  bool gridViewFor(String hostId) => gridViewByHost[hostId] ?? false;

  ViewPrefs copyWith({
    Map<String, bool>? gridViewByHost,
    EntryDensity? density,
    SortOrder? sort,
  }) =>
      ViewPrefs(
        gridViewByHost: gridViewByHost ?? this.gridViewByHost,
        density: density ?? this.density,
        sort: sort ?? this.sort,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Loads and persists [ViewPrefs]. Mutating methods update
/// [SharedPreferences] immediately and then update [state] so every explorer
/// instance (keyed per host/path) stays in sync.
class ViewPrefsNotifier extends AsyncNotifier<ViewPrefs> {
  SharedPreferences? _prefs;

  @override
  Future<ViewPrefs> build() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final rawGrid = prefs.getString(_kGridViewKey);
    final gridViewByHost = <String, bool>{};
    if (rawGrid != null) {
      final decoded = jsonDecode(rawGrid) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        gridViewByHost[entry.key] = entry.value as bool;
      }
    }

    final densityName = prefs.getString(_kDensityKey);
    final density = EntryDensity.values.firstWhere(
      (d) => d.name == densityName,
      orElse: () => EntryDensity.comfortable,
    );

    final sortFieldName = prefs.getString(_kSortFieldKey);
    final sortField = SortField.values.firstWhere(
      (f) => f.name == sortFieldName,
      orElse: () => SortField.name,
    );
    final sortAscending = prefs.getBool(_kSortAscendingKey) ?? true;

    return ViewPrefs(
      gridViewByHost: gridViewByHost,
      density: density,
      sort: SortOrder(field: sortField, ascending: sortAscending),
    );
  }

  /// Sets whether [hostId] renders its listing as a grid, persisting the
  /// per-host choice.
  Future<void> setGridView(String hostId, bool gridView) async {
    final current = state.valueOrNull ?? const ViewPrefs();
    final updated = Map<String, bool>.from(current.gridViewByHost)
      ..[hostId] = gridView;
    await _prefs?.setString(_kGridViewKey, jsonEncode(updated));
    state = AsyncData(current.copyWith(gridViewByHost: updated));
  }

  /// Sets the entry density, persisting the choice (applies to all hosts).
  Future<void> setDensity(EntryDensity density) async {
    final current = state.valueOrNull ?? const ViewPrefs();
    await _prefs?.setString(_kDensityKey, density.name);
    state = AsyncData(current.copyWith(density: density));
  }

  /// Sets the sort order, persisting the choice (applies to all hosts).
  Future<void> setSort(SortOrder sort) async {
    final current = state.valueOrNull ?? const ViewPrefs();
    await _prefs?.setString(_kSortFieldKey, sort.field.name);
    await _prefs?.setBool(_kSortAscendingKey, sort.ascending);
    state = AsyncData(current.copyWith(sort: sort));
  }
}

final viewPrefsProvider =
    AsyncNotifierProvider<ViewPrefsNotifier, ViewPrefs>(ViewPrefsNotifier.new);
