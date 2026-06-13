import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

// File-visibility tests: pure filter logic (extensionOf, isDotfile,
// isEntryHidden, filterHiddenEntries, isEntryHiddenInPicker) plus
// VisibilityPrefsNotifier persistence/presets, mirroring view_prefs_test.dart
// (mock SharedPreferences, fresh ProviderContainer per test, restart
// simulated via a new container/notifier instance).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Entry file(String name) => Entry(name: name, path: '/root/$name', isDir: false);
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
      const prefs = VisibilityPrefs(hideDotfiles: false, hiddenExtensions: {'tmp'});
      expect(isEntryHidden(file('a.tmp'), prefs), isTrue);
      expect(isEntryHidden(file('a.TMP'), prefs), isTrue);
      expect(isEntryHidden(file('a.txt'), prefs), isFalse);
    });

    test('hiddenExtensions never hides directories', () {
      const prefs = VisibilityPrefs(hideDotfiles: false, hiddenExtensions: {'tmp'});
      expect(isEntryHidden(dir('folder.tmp'), prefs), isFalse);
    });

    test('hiddenNames hides exact (case-insensitive) name matches', () {
      const prefs =
          VisibilityPrefs(hideDotfiles: false, hiddenNames: {'Thumbs.db'});
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
  // VisibilityPrefsNotifier persistence
  // ---------------------------------------------------------------------
  group('VisibilityPrefsNotifier defaults', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to hideDotfiles true and empty sets', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final prefs = await container.read(visibilityPrefsProvider.future);
      expect(prefs.hideDotfiles, isTrue);
      expect(prefs.hiddenExtensions, isEmpty);
      expect(prefs.hiddenNames, isEmpty);
    });
  });

  group('setHideDotfiles', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists and survives restart', () async {
      final container1 = ProviderContainer();
      await container1.read(visibilityPrefsProvider.future);
      await container1
          .read(visibilityPrefsProvider.notifier)
          .setHideDotfiles(false);

      final prefs1 = await container1.read(visibilityPrefsProvider.future);
      expect(prefs1.hideDotfiles, isFalse);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final prefs2 = await container2.read(visibilityPrefsProvider.future);
      expect(prefs2.hideDotfiles, isFalse);
    });
  });

  group('Hidden extensions management', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setHiddenExtensions normalizes to lowercase and persists', () async {
      final container1 = ProviderContainer();
      await container1.read(visibilityPrefsProvider.future);
      await container1
          .read(visibilityPrefsProvider.notifier)
          .setHiddenExtensions({'TMP', 'Log'});

      final prefs1 = await container1.read(visibilityPrefsProvider.future);
      expect(prefs1.hiddenExtensions, {'tmp', 'log'});
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final prefs2 = await container2.read(visibilityPrefsProvider.future);
      expect(prefs2.hiddenExtensions, {'tmp', 'log'});
    });

    test('addExtension strips leading dots, trims, and lowercases', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.addExtension('  ..TMP  ');

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, {'tmp'});
    });

    test('addExtension is a no-op for blank/dot-only input', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.addExtension('   ');
      await notifier.addExtension('.');

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, isEmpty);
    });

    test('removeExtension removes an entry from the set', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.setHiddenExtensions({'tmp', 'log'});
      await notifier.removeExtension('tmp');

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, {'log'});
    });
  });

  group('applyPreset', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('adds the preset extensions and names additively', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      // Pre-existing custom extension that no preset should remove.
      await notifier.addExtension('xyz');
      await notifier.applyPreset(systemJunkPreset);

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, containsAll({'xyz', ...systemJunkPreset.extensions}));
      expect(prefs.hiddenNames, systemJunkPreset.names);
    });

    test('applying two presets unions their extensions', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.applyPreset(systemJunkPreset);
      await notifier.applyPreset(logsPreset);

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(
        prefs.hiddenExtensions,
        containsAll({...systemJunkPreset.extensions, ...logsPreset.extensions}),
      );
    });

    test('removePreset undoes applyPreset (extensions and names)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.applyPreset(systemJunkPreset);
      await notifier.removePreset(systemJunkPreset);

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      for (final ext in systemJunkPreset.extensions) {
        expect(prefs.hiddenExtensions, isNot(contains(ext)));
      }
      // Names (e.g. Thumbs.db) are removed too — these are otherwise
      // unreachable from the UI, which was the original "can't unchoose" bug.
      expect(prefs.hiddenNames, isEmpty);
    });

    test('removePreset removes names case-insensitively', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.setHiddenNames({'thumbs.db'}); // lowercase variant
      await notifier.removePreset(systemJunkPreset); // names {'Thumbs.db', ...}

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenNames, isEmpty);
    });

    test('removePreset keeps a user extension that is not in the preset',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(visibilityPrefsProvider.future);

      final notifier = container.read(visibilityPrefsProvider.notifier);
      await notifier.addExtension('xyz');
      await notifier.applyPreset(logsPreset);
      await notifier.removePreset(logsPreset);

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, {'xyz'});
    });
  });
}
