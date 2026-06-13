import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/app_settings.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Two-tier settings model (Wave 0): app defaults + sparse per-device overrides,
// resolved as `deviceOverride ?? appDefault`. Mirrors the SharedPreferences
// patterns in the other storage tests — mock prefs, fresh ProviderContainer per
// test, restart simulated by reading via a new container.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsNotifier> load(ProviderContainer c) async {
    await c.read(settingsProvider.future);
    return c.read(settingsProvider.notifier);
  }

  group('defaults', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('fresh install resolves to list / comfortable / name-asc', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final s = await c.read(settingsProvider.future);

      final v = s.resolveView('any-host');
      expect(v.gridView, isFalse);
      expect(v.density, EntryDensity.comfortable);
      expect(v.sort, const SortOrder());
      expect(s.hasOverride('any-host'), isFalse);
    });
  });

  group('resolution precedence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('override wins over app default; absence inherits', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await load(c);

      await n.setAppGridView(true);
      await n.setAppDensity(EntryDensity.compact);

      // hostA overrides grid back to list; hostB inherits everything.
      await n.setDeviceGridView('hostA', false);

      final s = c.read(settingsProvider).valueOrNull!;
      expect(s.resolveView('hostA').gridView, isFalse, reason: 'override wins');
      expect(s.resolveView('hostA').density, EntryDensity.compact,
          reason: 'un-overridden field still inherits the app default');
      expect(s.resolveView('hostB').gridView, isTrue, reason: 'inherits');
      expect(s.hasOverride('hostA'), isTrue);
      expect(s.hasOverride('hostB'), isFalse);
    });

    test('clearing an override falls back to the app default and prunes the '
        'host when empty', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await load(c);

      await n.setAppGridView(true);
      await n.setDeviceGridView('hostA', false);
      expect(c.read(settingsProvider).valueOrNull!.hasOverride('hostA'), isTrue);

      await n.setDeviceGridView('hostA', null); // clear
      final s = c.read(settingsProvider).valueOrNull!;
      expect(s.hasOverride('hostA'), isFalse, reason: 'pruned when empty');
      expect(s.resolveView('hostA').gridView, isTrue, reason: 'back to default');
    });

    test('resetDevice clears every override for the host', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await load(c);

      await n.setDeviceGridView('hostA', true);
      await n.setDeviceDensity('hostA', EntryDensity.compact);
      await n.setDeviceSort('hostA', const SortOrder(field: SortField.size));
      expect(c.read(settingsProvider).valueOrNull!.hasOverride('hostA'), isTrue);

      await n.resetDevice('hostA');
      expect(
          c.read(settingsProvider).valueOrNull!.hasOverride('hostA'), isFalse);
    });
  });

  group('persistence across restart', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('app defaults and overrides survive a fresh container', () async {
      final c1 = ProviderContainer();
      final n1 = await load(c1);
      await n1.setAppSort(const SortOrder(field: SortField.date, ascending: false));
      await n1.setDeviceGridView('hostA', true);
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final s = await c2.read(settingsProvider.future);
      expect(s.app.sort, const SortOrder(field: SortField.date, ascending: false));
      expect(s.resolveView('hostA').gridView, isTrue);
      expect(s.resolveView('other').gridView, isFalse);
    });
  });

  group('migration from legacy view_prefs keys', () {
    test('per-host grid: divergences become overrides, matches collapse',
        () async {
      // Legacy state: hostA was grid (diverges from the list default), hostB
      // was explicitly list (matches the default), plus global density+sort.
      SharedPreferences.setMockInitialValues({
        'rfe_grid_view_v1': jsonEncode({'hostA': true, 'hostB': false}),
        'rfe_density_v1': EntryDensity.compact.name,
        'rfe_sort_field_v1': SortField.size.name,
        'rfe_sort_ascending_v1': false,
      });

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final s = await c.read(settingsProvider.future);

      // Old globals become app defaults.
      expect(s.app.gridView, isFalse);
      expect(s.app.density, EntryDensity.compact);
      expect(s.app.sort, const SortOrder(field: SortField.size, ascending: false));

      // hostA diverged -> explicit override; hostB matched -> no override.
      expect(s.hasOverride('hostA'), isTrue);
      expect(s.resolveView('hostA').gridView, isTrue);
      expect(s.hasOverride('hostB'), isFalse);

      // Behavior is preserved either way: both resolve to what they were.
      expect(s.resolveView('hostB').gridView, isFalse);
    });

    test('migration runs once and removes legacy keys', () async {
      SharedPreferences.setMockInitialValues({
        'rfe_grid_view_v1': jsonEncode({'hostA': true}),
      });
      final prefs = await SharedPreferences.getInstance();

      final c1 = ProviderContainer();
      await c1.read(settingsProvider.future);
      c1.dispose();

      expect(prefs.containsKey('rfe_grid_view_v1'), isFalse,
          reason: 'legacy key cleaned up');
      expect(prefs.getBool('settings.migrated.v1'), isTrue);

      // A user later sets the app default to list; re-running build must NOT
      // re-migrate the (now-removed) legacy grid map and resurrect the override.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final n2 = c2.read(settingsProvider.notifier);
      await c2.read(settingsProvider.future);
      await n2.resetDevice('hostA');
      c2.dispose();

      final c3 = ProviderContainer();
      addTearDown(c3.dispose);
      final s3 = await c3.read(settingsProvider.future);
      expect(s3.hasOverride('hostA'), isFalse,
          reason: 'migration is one-shot; reset is not undone');
    });
  });

  group('value types', () {
    test('DeviceOverrides.isEmpty and copyWith clear semantics', () {
      const empty = DeviceOverrides();
      expect(empty.isEmpty, isTrue);

      final withGrid = empty.copyWithGridView(true);
      expect(withGrid.isEmpty, isFalse);
      expect(withGrid.gridView, isTrue);

      final cleared = withGrid.copyWithGridView(null);
      expect(cleared.isEmpty, isTrue, reason: 'null clears the field');
    });
  });
}
