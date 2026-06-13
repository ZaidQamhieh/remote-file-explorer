import '../storage/view_prefs.dart';

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
  });

  /// Default list/grid choice. `true` = grid. Hosts without an override follow
  /// this.
  final bool gridView;
  final EntryDensity density;
  final SortOrder sort;

  AppDefaults copyWith({
    bool? gridView,
    EntryDensity? density,
    SortOrder? sort,
  }) =>
      AppDefaults(
        gridView: gridView ?? this.gridView,
        density: density ?? this.density,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is AppDefaults &&
      other.gridView == gridView &&
      other.density == density &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(gridView, density, sort);
}

/// A single host's overrides. Each field is nullable: `null` = inherit the app
/// default for that setting, non-null = this host has explicitly overridden it.
///
/// The `copyWithX` helpers deliberately *replace* a field with the given
/// (nullable) value so callers can clear an override by passing `null` — a
/// normal `copyWith` can't express "set this back to null".
class DeviceOverrides {
  const DeviceOverrides({this.gridView, this.density, this.sort});

  final bool? gridView;
  final EntryDensity? density;
  final SortOrder? sort;

  /// True when this host overrides nothing — equivalent to having no entry at
  /// all. Such entries are pruned on write so "absent == inherit" stays exact.
  bool get isEmpty => gridView == null && density == null && sort == null;

  DeviceOverrides copyWithGridView(bool? value) =>
      DeviceOverrides(gridView: value, density: density, sort: sort);
  DeviceOverrides copyWithDensity(EntryDensity? value) =>
      DeviceOverrides(gridView: gridView, density: value, sort: sort);
  DeviceOverrides copyWithSort(SortOrder? value) =>
      DeviceOverrides(gridView: gridView, density: density, sort: value);

  @override
  bool operator ==(Object other) =>
      other is DeviceOverrides &&
      other.gridView == gridView &&
      other.density == density &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(gridView, density, sort);
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

  SettingsState copyWith({
    AppDefaults? app,
    Map<String, DeviceOverrides>? overrides,
  }) =>
      SettingsState(
        app: app ?? this.app,
        overrides: overrides ?? this.overrides,
      );
}
