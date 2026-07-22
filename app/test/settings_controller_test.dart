import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/app_settings.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
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

    test('compressDownloadsOnCellular defaults to true', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final s = await c.read(settingsProvider.future);
      expect(s.app.compressDownloadsOnCellular, isTrue);
    });
  });

  group('compressDownloadsOnCellular (S3)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('setCompressDownloadsOnCellular persists across restart', () async {
      final c1 = ProviderContainer();
      final n1 = await load(c1);
      await n1.setCompressDownloadsOnCellular(false);
      expect(
        c1.read(settingsProvider).valueOrNull!.app.compressDownloadsOnCellular,
        isFalse,
      );
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final s = await c2.read(settingsProvider.future);
      expect(s.app.compressDownloadsOnCellular, isFalse);
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
      expect(
        s.resolveView('hostA').density,
        EntryDensity.compact,
        reason: 'un-overridden field still inherits the app default',
      );
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
      expect(
        c.read(settingsProvider).valueOrNull!.hasOverride('hostA'),
        isTrue,
      );

      await n.setDeviceGridView('hostA', null); // clear
      final s = c.read(settingsProvider).valueOrNull!;
      expect(s.hasOverride('hostA'), isFalse, reason: 'pruned when empty');
      expect(
        s.resolveView('hostA').gridView,
        isTrue,
        reason: 'back to default',
      );
    });

    test('resetDevice clears every override for the host', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await load(c);

      await n.setDeviceGridView('hostA', true);
      await n.setDeviceDensity('hostA', EntryDensity.compact);
      await n.setDeviceSort('hostA', const SortOrder(field: SortField.size));
      expect(
        c.read(settingsProvider).valueOrNull!.hasOverride('hostA'),
        isTrue,
      );

      await n.resetDevice('hostA');
      expect(
        c.read(settingsProvider).valueOrNull!.hasOverride('hostA'),
        isFalse,
      );
    });
  });

  group('persistence across restart', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('app defaults and overrides survive a fresh container', () async {
      final c1 = ProviderContainer();
      final n1 = await load(c1);
      await n1.setAppSort(
        const SortOrder(field: SortField.date, ascending: false),
      );
      await n1.setDeviceGridView('hostA', true);
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final s = await c2.read(settingsProvider.future);
      expect(
        s.app.sort,
        const SortOrder(field: SortField.date, ascending: false),
      );
      expect(s.resolveView('hostA').gridView, isTrue);
      expect(s.resolveView('other').gridView, isFalse);
    });
  });

  group('migration from legacy view_prefs keys', () {
    test(
      'per-host grid: divergences become overrides, matches collapse',
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
        expect(
          s.app.sort,
          const SortOrder(field: SortField.size, ascending: false),
        );

        // hostA diverged -> explicit override; hostB matched -> no override.
        expect(s.hasOverride('hostA'), isTrue);
        expect(s.resolveView('hostA').gridView, isTrue);
        expect(s.hasOverride('hostB'), isFalse);

        // Behavior is preserved either way: both resolve to what they were.
        expect(s.resolveView('hostB').gridView, isFalse);
      },
    );

    test('migration runs once and removes legacy keys', () async {
      SharedPreferences.setMockInitialValues({
        'rfe_grid_view_v1': jsonEncode({'hostA': true}),
      });
      final prefs = await SharedPreferences.getInstance();

      final c1 = ProviderContainer();
      await c1.read(settingsProvider.future);
      c1.dispose();

      expect(
        prefs.containsKey('rfe_grid_view_v1'),
        isFalse,
        reason: 'legacy key cleaned up',
      );
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
      expect(
        s3.hasOverride('hostA'),
        isFalse,
        reason: 'migration is one-shot; reset is not undone',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Appearance (Wave F): app-global theme mode + dynamic color. No per-device
  // override — these live on AppDefaults only.
  // ---------------------------------------------------------------------
  group('appearance defaults and persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'fresh install defaults to system theme + dynamic color off',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final s = await c.read(settingsProvider.future);

        expect(s.app.themeMode, ThemeMode.system);
        expect(s.app.dynamicColor, isFalse);
      },
    );

    test('setThemeMode / setDynamicColor update state and persist', () async {
      final c1 = ProviderContainer();
      final n1 = await load(c1);
      await n1.setThemeMode(ThemeMode.dark);
      await n1.setDynamicColor(false);

      final s1 = c1.read(settingsProvider).valueOrNull!;
      expect(s1.app.themeMode, ThemeMode.dark);
      expect(s1.app.dynamicColor, isFalse);
      c1.dispose();

      // Survives a fresh container (persisted as enum name + bool).
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final s2 = await c2.read(settingsProvider.future);
      expect(s2.app.themeMode, ThemeMode.dark);
      expect(s2.app.dynamicColor, isFalse);
    });

    test('unknown/absent persisted theme mode falls back to system', () async {
      SharedPreferences.setMockInitialValues({'app.themeMode': 'bogus'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final s = await c.read(settingsProvider.future);
      expect(s.app.themeMode, ThemeMode.system);
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

    test('copyWithVisibility sets and clears the wholesale override', () {
      const empty = DeviceOverrides();
      final withVis = empty.copyWithVisibility(
        const VisibilityPrefs(hideDotfiles: false),
      );
      expect(withVis.isEmpty, isFalse);
      expect(withVis.visibility, const VisibilityPrefs(hideDotfiles: false));

      final cleared = withVis.copyWithVisibility(null);
      expect(cleared.isEmpty, isTrue, reason: 'null clears the override');
    });
  });

  // ---------------------------------------------------------------------
  // File-visibility: app default + optional per-device override (wholesale)
  // ---------------------------------------------------------------------
  group('visibility resolution precedence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'default resolves to hideDotfiles-true / empty sets, no override',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final s = await c.read(settingsProvider.future);

        final v = s.resolveVisibility('any-host');
        expect(v.hideDotfiles, isTrue);
        expect(v.hiddenExtensions, isEmpty);
        expect(v.hiddenNames, isEmpty);
        expect(
          s.overridesFor('any-host').visibility,
          isNull,
          reason: 'absence == inherit',
        );
      },
    );

    test('override wins; absence inherits the app default', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await load(c);

      // App default hides ".tmp".
      await n.setHiddenExtensions({'tmp'});
      // hostA overrides to hide ".log" instead (wholesale).
      await n.setHiddenExtensions({'log'}, hostId: 'hostA');

      final s = c.read(settingsProvider).valueOrNull!;
      expect(
        s.resolveVisibility('hostA').hiddenExtensions,
        {'log'},
        reason: 'override wins wholesale',
      );
      expect(
        s.resolveVisibility('hostB').hiddenExtensions,
        {'tmp'},
        reason: 'inherits the app default',
      );
      expect(s.overridesFor('hostA').visibility, isNotNull);
      expect(s.overridesFor('hostB').visibility, isNull);
    });

    test(
      'editing the app default does not affect an overridden host',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = await load(c);

        await n.setHiddenExtensions({'log'}, hostId: 'hostA');
        await n.setHiddenExtensions({'tmp'}); // app default changes

        final s = c.read(settingsProvider).valueOrNull!;
        expect(s.resolveVisibility('hostA').hiddenExtensions, {'log'});
        expect(s.app.visibility.hiddenExtensions, {'tmp'});
      },
    );
  });

  group('setDeviceVisibilityOverride seed/clear', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('turning override on seeds from the current resolved value', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await load(c);

      // App default: hide dotfiles off + hide ".tmp".
      await n.setHideDotfiles(false);
      await n.setHiddenExtensions({'tmp'});

      await n.setDeviceVisibilityOverride('hostA', true);
      final s = c.read(settingsProvider).valueOrNull!;
      final vis = s.overridesFor('hostA').visibility;
      expect(vis, isNotNull);
      expect(vis!.hideDotfiles, isFalse, reason: 'seeded from app default');
      expect(vis.hiddenExtensions, {'tmp'});
    });

    test(
      'turning override off clears it (host falls back to app default)',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = await load(c);

        await n.setHiddenExtensions({'log'}, hostId: 'hostA');
        expect(
          c
              .read(settingsProvider)
              .valueOrNull!
              .overridesFor('hostA')
              .visibility,
          isNotNull,
        );

        await n.setDeviceVisibilityOverride('hostA', false);
        final s = c.read(settingsProvider).valueOrNull!;
        expect(s.overridesFor('hostA').visibility, isNull);
        expect(
          s.hasOverride('hostA'),
          isFalse,
          reason: 'host pruned when empty',
        );
        expect(
          s.resolveVisibility('hostA').hiddenExtensions,
          isEmpty,
          reason: 'back to the app default',
        );
      },
    );

    test(
      'resetDevice clears a visibility override along with the host entry',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = await load(c);

        await n.setHiddenExtensions({'log'}, hostId: 'hostA');
        await n.resetDevice('hostA');
        expect(
          c
              .read(settingsProvider)
              .valueOrNull!
              .overridesFor('hostA')
              .visibility,
          isNull,
        );
      },
    );

    test('app-default + per-host overrides survive a fresh container', () async {
      final c1 = ProviderContainer();
      final n1 = await load(c1);
      await n1.setHiddenExtensions({'tmp'}); // app default
      await n1.setHideDotfiles(false, hostId: 'hostA');
      await n1.setHiddenNames({'Thumbs.db'}, hostId: 'hostA');
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final s = await c2.read(settingsProvider.future);
      expect(s.app.visibility.hiddenExtensions, {'tmp'});
      final vis = s.resolveVisibility('hostA');
      expect(vis.hideDotfiles, isFalse);
      expect(vis.hiddenNames, {'Thumbs.db'});
      // The override is wholesale: it carries the seeded app-default extension.
      expect(vis.hiddenExtensions, {'tmp'});
    });
  });

  group('visibility migration from legacy global keys', () {
    test(
      'legacy globals fold into the app default, then are removed',
      () async {
        SharedPreferences.setMockInitialValues({
          'rfe_hide_dotfiles_v1': false,
          'rfe_hidden_extensions_v1': jsonEncode(['tmp', 'log']),
          'rfe_hidden_names_v1': jsonEncode(['Thumbs.db']),
        });
        final prefs = await SharedPreferences.getInstance();

        final c = ProviderContainer();
        addTearDown(c.dispose);
        final s = await c.read(settingsProvider.future);

        expect(s.app.visibility.hideDotfiles, isFalse);
        expect(s.app.visibility.hiddenExtensions, {'tmp', 'log'});
        expect(s.app.visibility.hiddenNames, {'Thumbs.db'});

        // Legacy keys cleaned up; the one-shot flag is set.
        expect(prefs.containsKey('rfe_hide_dotfiles_v1'), isFalse);
        expect(prefs.containsKey('rfe_hidden_extensions_v1'), isFalse);
        expect(prefs.containsKey('rfe_hidden_names_v1'), isFalse);
        expect(prefs.getBool('settings.visibilityMigrated.v1'), isTrue);
      },
    );

    test('absent legacy keys yield the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final s = await c.read(settingsProvider.future);

      expect(s.app.visibility.hideDotfiles, isTrue);
      expect(s.app.visibility.hiddenExtensions, isEmpty);
      expect(s.app.visibility.hiddenNames, isEmpty);
    });

    test('migration runs once and is not undone by a later edit', () async {
      SharedPreferences.setMockInitialValues({
        'rfe_hidden_extensions_v1': jsonEncode(['tmp']),
      });

      final c1 = ProviderContainer();
      final n1 = await load(c1);
      // User later clears the app-default extensions.
      await n1.setHiddenExtensions(<String>{});
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final s = await c2.read(settingsProvider.future);
      expect(
        s.app.visibility.hiddenExtensions,
        isEmpty,
        reason: 'migration is one-shot; it does not resurrect the legacy set',
      );
    });
  });
}
