import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

// File-visibility tests: pure filter logic (extensionOf, isDotfile,
// isEntryHidden, filterHiddenEntries, isEntryHiddenInPicker) plus the
// app-default visibility mutation/persistence/presets — which now live on the
// two-tier settings controller (the standalone VisibilityPrefsNotifier was
// folded into it). These exercise the app-default path (`hostId: null`);
// per-host override precedence is covered in settings_controller_test.dart.
// Mock SharedPreferences, fresh ProviderContainer per test, restart simulated
// via a new container/notifier instance.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Entry file(String name) =>
      Entry(name: name, path: '/root/$name', isDir: false);
  Entry dir(String name) => Entry(name: name, path: '/root/$name', isDir: true);

  // ---------------------------------------------------------------------
  // extensionOf
  // ---------------------------------------------------------------------
  group('extensionOf', () {
    test('returns the lowercase extension without the dot', () {
      expect(extensionOf('a.txt'), 'txt');
      expect(extensionOf('A.TXT'), 'txt');
    });

    test('uses the last dot for multi-dot names', () {
      expect(extensionOf('archive.tar.gz'), 'gz');
    });

    test('returns empty string for names with no extension', () {
      expect(extensionOf('noext'), '');
    });

    test('returns empty string for dotfiles (leading dot only)', () {
      expect(extensionOf('.bashrc'), '');
    });

    test('returns empty string when the dot is the last character', () {
      expect(extensionOf('trailing.'), '');
    });
  });

  // ---------------------------------------------------------------------
  // isDotfile
  // ---------------------------------------------------------------------
  group('isDotfile', () {
    test('true for names starting with "."', () {
      expect(isDotfile('.bashrc'), isTrue);
      expect(isDotfile('.config'), isTrue);
    });

    test('false for regular names', () {
      expect(isDotfile('regular.txt'), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // isEntryHidden
  // ---------------------------------------------------------------------
  group('isEntryHidden', () {
    test('default prefs hide dotfiles and dotfolders', () {
      const prefs = VisibilityPrefs();
      expect(isEntryHidden(file('.bashrc'), prefs), isTrue);
      expect(isEntryHidden(dir('.config'), prefs), isTrue);
      expect(isEntryHidden(file('readme.txt'), prefs), isFalse);
    });

    test('hideDotfiles: false stops hiding dotfiles', () {
      const prefs = VisibilityPrefs(hideDotfiles: false);
      expect(isEntryHidden(file('.bashrc'), prefs), isFalse);
    });

    test('hiddenExtensions hides matching files case-insensitively', () {
      const prefs = VisibilityPrefs(
        hideDotfiles: false,
        hiddenExtensions: {'tmp'},
      );
      expect(isEntryHidden(file('a.tmp'), prefs), isTrue);
      expect(isEntryHidden(file('a.TMP'), prefs), isTrue);
      expect(isEntryHidden(file('a.txt'), prefs), isFalse);
    });

    test('hiddenExtensions never hides directories', () {
      const prefs = VisibilityPrefs(
        hideDotfiles: false,
        hiddenExtensions: {'tmp'},
      );
      expect(isEntryHidden(dir('folder.tmp'), prefs), isFalse);
    });

    test('hiddenNames hides exact (case-insensitive) name matches', () {
      const prefs = VisibilityPrefs(
        hideDotfiles: false,
        hiddenNames: {'Thumbs.db'},
      );
      expect(isEntryHidden(file('thumbs.db'), prefs), isTrue);
      expect(isEntryHidden(file('Thumbs.db'), prefs), isTrue);
      expect(isEntryHidden(file('Thumbs.db.bak'), prefs), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // filterHiddenEntries
  // ---------------------------------------------------------------------
  group('filterHiddenEntries', () {
    test('removes entries hidden under the given prefs', () {
      const prefs = VisibilityPrefs(hiddenExtensions: {'log'});
      final entries = [
        file('readme.txt'),
        file('.env'),
        file('app.log'),
        dir('Documents'),
      ];
      final visible = filterHiddenEntries(entries, prefs);
      expect(visible.map((e) => e.name), ['readme.txt', 'Documents']);
    });
  });

  // ---------------------------------------------------------------------
  // isEntryHiddenInPicker
  // ---------------------------------------------------------------------
  group('isEntryHiddenInPicker', () {
    test('hides dotfolders when hideDotfiles is true', () {
      const prefs = VisibilityPrefs();
      expect(isEntryHiddenInPicker(dir('.config'), prefs), isTrue);
      expect(isEntryHiddenInPicker(dir('Documents'), prefs), isFalse);
    });

    test('does not hide dotfolders when hideDotfiles is false', () {
      const prefs = VisibilityPrefs(hideDotfiles: false);
      expect(isEntryHiddenInPicker(dir('.config'), prefs), isFalse);
    });

    test('extension/name rules do not apply in the picker', () {
      const prefs = VisibilityPrefs(hiddenNames: {'Thumbs.db'});
      // A folder matching a hidden *name* is still shown — the picker only
      // ever lists directories and only applies the dotfolder rule.
      expect(isEntryHiddenInPicker(dir('Thumbs.db'), prefs), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // App-default visibility mutation/persistence (settings controller)
  // ---------------------------------------------------------------------

  // Reads the resolved app-default visibility (hostId-agnostic, since these
  // exercise the default with no overrides).
  VisibilityPrefs appVis(ProviderContainer c) =>
      c.read(settingsProvider).valueOrNull!.app.visibility;

  group('app-default visibility defaults', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to hideDotfiles true and empty sets', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final s = await container.read(settingsProvider.future);
      expect(s.app.visibility.hideDotfiles, isTrue);
      expect(s.app.visibility.hiddenExtensions, isEmpty);
      expect(s.app.visibility.hiddenNames, isEmpty);
    });
  });

  group('setHideDotfiles (app default)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists and survives restart', () async {
      final container1 = ProviderContainer();
      await container1.read(settingsProvider.future);
      await container1.read(settingsProvider.notifier).setHideDotfiles(false);

      expect(appVis(container1).hideDotfiles, isFalse);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final s2 = await container2.read(settingsProvider.future);
      expect(s2.app.visibility.hideDotfiles, isFalse);
    });
  });

  group('Hidden extensions management (app default)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setHiddenExtensions normalizes to lowercase and persists', () async {
      final container1 = ProviderContainer();
      await container1.read(settingsProvider.future);
      await container1.read(settingsProvider.notifier).setHiddenExtensions({
        'TMP',
        'Log',
      });

      expect(appVis(container1).hiddenExtensions, {'tmp', 'log'});
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final s2 = await container2.read(settingsProvider.future);
      expect(s2.app.visibility.hiddenExtensions, {'tmp', 'log'});
    });

    test('addExtension strips leading dots, trims, and lowercases', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await container.read(settingsProvider.notifier).addExtension('  ..TMP  ');

      expect(appVis(container).hiddenExtensions, {'tmp'});
    });

    test('addExtension is a no-op for blank/dot-only input', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.addExtension('   ');
      await notifier.addExtension('.');

      expect(appVis(container).hiddenExtensions, isEmpty);
    });

    test('removeExtension removes an entry from the set', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.setHiddenExtensions({'tmp', 'log'});
      await notifier.removeExtension('tmp');

      expect(appVis(container).hiddenExtensions, {'log'});
    });
  });

  group('Hidden names management (app default)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'addName adds an exact name and is case-insensitively idempotent',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        final notifier = container.read(settingsProvider.notifier);
        await notifier.addName('Thumbs.db');
        await notifier.addName('thumbs.db'); // duplicate (different case)

        expect(appVis(container).hiddenNames, {'Thumbs.db'});
      },
    );

    test('addName is a no-op for blank input', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await container.read(settingsProvider.notifier).addName('   ');

      expect(appVis(container).hiddenNames, isEmpty);
    });

    test('removeName removes case-insensitively', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.setHiddenNames({'Thumbs.db'});
      await notifier.removeName('THUMBS.DB');

      expect(appVis(container).hiddenNames, isEmpty);
    });
  });

  group('applyPreset (app default)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('adds the preset extensions and names additively', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      // Pre-existing custom extension that no preset should remove.
      await notifier.addExtension('xyz');
      await notifier.applyPreset(systemJunkPreset);

      expect(
        appVis(container).hiddenExtensions,
        containsAll({'xyz', ...systemJunkPreset.extensions}),
      );
      expect(appVis(container).hiddenNames, systemJunkPreset.names);
    });

    test('applying two presets unions their extensions', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.applyPreset(systemJunkPreset);
      await notifier.applyPreset(logsPreset);

      expect(
        appVis(container).hiddenExtensions,
        containsAll({...systemJunkPreset.extensions, ...logsPreset.extensions}),
      );
    });

    test('removePreset undoes applyPreset (extensions and names)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.applyPreset(systemJunkPreset);
      await notifier.removePreset(systemJunkPreset);

      for (final ext in systemJunkPreset.extensions) {
        expect(appVis(container).hiddenExtensions, isNot(contains(ext)));
      }
      // Names (e.g. Thumbs.db) are removed too — these are otherwise
      // unreachable from the UI, which was the original "can't unchoose" bug.
      expect(appVis(container).hiddenNames, isEmpty);
    });

    test('removePreset removes names case-insensitively', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.setHiddenNames({'thumbs.db'}); // lowercase variant
      await notifier.removePreset(systemJunkPreset); // names {'Thumbs.db', ...}

      expect(appVis(container).hiddenNames, isEmpty);
    });

    test(
      'removePreset keeps a user extension that is not in the preset',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        final notifier = container.read(settingsProvider.notifier);
        await notifier.addExtension('xyz');
        await notifier.applyPreset(logsPreset);
        await notifier.removePreset(logsPreset);

        expect(appVis(container).hiddenExtensions, {'xyz'});
      },
    );
  });
}
