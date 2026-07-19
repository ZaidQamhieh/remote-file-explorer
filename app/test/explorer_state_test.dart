import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/api/providers.dart';
import 'package:remote_file_explorer/core/models/batch_result.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:remote_file_explorer/features/explorer/explorer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

/// Polls [predicate] until it's true or [timeout] elapses, pumping the event
/// loop between checks so pending async work (cache I/O, network mocks) gets
/// a chance to complete.
Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Entry _file(String name, {int? size, DateTime? modified, String? mime}) =>
    Entry(
      name: name,
      path: '/root/$name',
      isDir: false,
      size: size,
      mimeType: mime,
      modified: modified,
    );

Entry _dir(String name) => Entry(name: name, path: '/root/$name', isDir: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A unique scratch directory for ListingCache's on-disk reads/writes during
  // this test run, so tests are hermetic and don't pick up (or leave behind)
  // stale cache files in /tmp.
  late Directory tmpDir;

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('rfe_explorer_state_test_');
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  // Mock path_provider's platform channel so ListingCache (used internally by
  // ExplorerNotifier) doesn't throw MissingPluginException when it falls back
  // to the app documents directory.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
  });

  // ---------------------------------------------------------------------
  // buildPathStack
  // ---------------------------------------------------------------------
  group('buildPathStack', () {
    test('POSIX root', () {
      expect(buildPathStack('/'), ['/']);
    });

    test('POSIX nested path', () {
      expect(buildPathStack('/home/x/Storage'), [
        '/',
        '/home',
        '/home/x',
        '/home/x/Storage',
      ]);
    });

    test('Windows drive root', () {
      expect(buildPathStack(r'C:\'), [r'C:\']);
    });

    test('Windows nested path with backslashes', () {
      expect(buildPathStack(r'C:\Users\me\Documents'), [
        r'C:\',
        r'C:\Users',
        r'C:\Users\me',
        r'C:\Users\me\Documents',
      ]);
    });

    test('Windows path with forward slashes is normalized', () {
      expect(buildPathStack('C:/Users/me'), [
        r'C:\',
        r'C:\Users',
        r'C:\Users\me',
      ]);
    });
  });

  // ---------------------------------------------------------------------
  // renameDestination
  // ---------------------------------------------------------------------
  group('renameDestination', () {
    test('POSIX nested path keeps forward slashes', () {
      expect(
        renameDestination('/home/x/old.txt', 'new.txt'),
        '/home/x/new.txt',
      );
    });

    test('POSIX root-level rename', () {
      expect(renameDestination('/old.txt', 'new.txt'), '/new.txt');
    });

    test('Windows nested path keeps backslashes', () {
      expect(
        renameDestination(r'C:\dir\old.txt', 'new.txt'),
        r'C:\dir\new.txt',
      );
    });

    test('Windows drive-root rename keeps backslash separator', () {
      expect(renameDestination(r'C:\old.txt', 'new.txt'), r'C:\new.txt');
    });

    test('does not mix separators (no C:\\dir/new.txt)', () {
      final result = renameDestination(r'C:\dir\old.txt', 'new.txt');
      expect(result.contains('/'), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // basenameOf
  // ---------------------------------------------------------------------
  group('basenameOf', () {
    test('POSIX nested path', () {
      expect(basenameOf('/home/x/report.pdf'), 'report.pdf');
    });

    test('Windows nested path', () {
      expect(basenameOf(r'C:\Users\me\report.pdf'), 'report.pdf');
    });

    test('top-level path', () {
      expect(basenameOf('/report.pdf'), 'report.pdf');
    });
  });

  // ---------------------------------------------------------------------
  // joinRemotePath (PR-66) — several call sites used to hardcode "/",
  // producing a broken mixed-separator path for a Windows-paired host.
  // ---------------------------------------------------------------------
  group('joinRemotePath', () {
    test('POSIX nested dir', () {
      expect(joinRemotePath('/home/x', 'report.pdf'), '/home/x/report.pdf');
    });

    test('POSIX root does not double the leading slash', () {
      expect(joinRemotePath('/', 'report.pdf'), '/report.pdf');
    });

    test('Windows nested dir uses backslash, not "/"', () {
      expect(
        joinRemotePath(r'C:\Users\me', 'report.pdf'),
        r'C:\Users\me\report.pdf',
      );
    });

    test('Windows drive root does not double the backslash', () {
      expect(joinRemotePath(r'C:\', 'report.pdf'), r'C:\report.pdf');
    });
  });

  // ---------------------------------------------------------------------
  // dedupedName — used by the upload "Keep both" resolution
  // ---------------------------------------------------------------------
  group('dedupedName', () {
    test('returns the name unchanged when it does not collide', () {
      expect(dedupedName('photo.jpg', {'other.jpg'}), 'photo.jpg');
    });

    test('appends " (1)" before the extension on first collision', () {
      expect(dedupedName('photo.jpg', {'photo.jpg'}), 'photo (1).jpg');
    });

    test('increments until a free name is found', () {
      expect(
        dedupedName('photo.jpg', {
          'photo.jpg',
          'photo (1).jpg',
          'photo (2).jpg',
        }),
        'photo (3).jpg',
      );
    });

    test('extensionless names get the suffix appended at the end', () {
      expect(dedupedName('README', {'README'}), 'README (1)');
    });

    test('dotfiles (no real extension) get the suffix appended at the end', () {
      expect(dedupedName('.bashrc', {'.bashrc'}), '.bashrc (1)');
    });
  });

  // ---------------------------------------------------------------------
  // ExplorerState.sortedEntries memoization / correctness
  // ---------------------------------------------------------------------
  group('ExplorerState.sortedEntries', () {
    test('directories are listed before files regardless of name', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('a.txt'), _dir('z_dir'), _file('b.txt'), _dir('a_dir')],
      );

      expect(state.sortedEntries.map((e) => e.name), [
        'a_dir',
        'z_dir',
        'a.txt',
        'b.txt',
      ]);
    });

    test('sorts by name ascending by default, case-insensitively', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('Banana'), _file('apple'), _file('Cherry')],
      );

      expect(state.sortedEntries.map((e) => e.name), [
        'apple',
        'Banana',
        'Cherry',
      ]);
    });

    test('sorts by size descending when configured', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [
          _file('small', size: 10),
          _file('large', size: 1000),
          _file('medium', size: 100),
        ],
        sort: const SortOrder(field: SortField.size, ascending: false),
      );

      expect(state.sortedEntries.map((e) => e.name), [
        'large',
        'medium',
        'small',
      ]);
    });

    test('sorts by date ascending, missing dates treated as epoch', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [
          _file('no_date'),
          _file('newer', modified: DateTime(2026, 1, 2)),
          _file('older', modified: DateTime(2026, 1, 1)),
        ],
        sort: const SortOrder(field: SortField.date, ascending: true),
      );

      expect(state.sortedEntries.map((e) => e.name), [
        'no_date',
        'older',
        'newer',
      ]);
    });

    test('is recomputed when copyWith changes entries', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('b.txt'), _file('a.txt')],
      );
      expect(state.sortedEntries.map((e) => e.name), ['a.txt', 'b.txt']);

      final next = state.copyWith(entries: [_file('z.txt'), _file('y.txt')]);
      expect(next.sortedEntries.map((e) => e.name), ['y.txt', 'z.txt']);
    });

    test('is recomputed when copyWith changes sort order', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('a.txt'), _file('b.txt')],
      );
      expect(state.sortedEntries.map((e) => e.name), ['a.txt', 'b.txt']);

      final next = state.copyWith(
        sort: const SortOrder(field: SortField.name, ascending: false),
      );
      expect(next.sortedEntries.map((e) => e.name), ['b.txt', 'a.txt']);
    });
  });

  // ---------------------------------------------------------------------
  // ExplorerState pagination fields
  // ---------------------------------------------------------------------
  group('ExplorerState pagination', () {
    test('hasMore is false when nextCursor is null', () {
      final state = ExplorerState(pathStack: const ['/root']);
      expect(state.hasMore, isFalse);
    });

    test('hasMore is true when nextCursor is set', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        nextCursor: 'cursor-1',
      );
      expect(state.hasMore, isTrue);
    });

    test(
      'copyWith can clear nextCursor back to null via sentinel-aware arg',
      () {
        final state = ExplorerState(
          pathStack: const ['/root'],
          nextCursor: 'cursor-1',
        );
        final cleared = state.copyWith(nextCursor: null);
        expect(cleared.nextCursor, isNull);
        expect(cleared.hasMore, isFalse);
      },
    );

    test('copyWith without nextCursor preserves the previous cursor', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        nextCursor: 'cursor-1',
      );
      final next = state.copyWith(loading: true);
      expect(next.nextCursor, 'cursor-1');
    });
  });

  // ---------------------------------------------------------------------
  // ExplorerState file visibility (hiddenPaths / displayEntries)
  // ---------------------------------------------------------------------
  group('ExplorerState file visibility', () {
    test(
      'hiddenPaths/hiddenCount reflect entries hidden by visibilityPrefs',
      () {
        final state = ExplorerState(
          pathStack: const ['/root'],
          entries: [_file('readme.txt'), _file('.env'), _dir('.config')],
        );

        // Default VisibilityPrefs hides dotfiles/dotfolders.
        expect(state.hiddenCount, 2);
        expect(state.hiddenPaths, {'/root/.env', '/root/.config'});
      },
    );

    test('displayEntries excludes hidden entries when showHidden is false', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('readme.txt'), _file('.env')],
      );

      expect(state.displayEntries.map((e) => e.name), ['readme.txt']);
    });

    test('displayEntries includes hidden entries when showHidden is true', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('readme.txt'), _file('.env')],
        showHidden: true,
      );

      expect(state.displayEntries.map((e) => e.name).toSet(), {
        'readme.txt',
        '.env',
      });
    });

    test('hiddenPaths is recomputed when copyWith changes visibilityPrefs', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('readme.txt'), _file('app.log')],
      );
      expect(state.hiddenCount, 0);

      final next = state.copyWith(
        visibilityPrefs: const VisibilityPrefs(
          hideDotfiles: false,
          hiddenExtensions: {'log'},
        ),
      );
      expect(next.hiddenCount, 1);
      expect(next.hiddenPaths, {'/root/app.log'});
    });

    test('copyWith toggling showHidden does not change hiddenPaths', () {
      final state = ExplorerState(
        pathStack: const ['/root'],
        entries: [_file('.env')],
      );
      final revealed = state.copyWith(showHidden: true);
      expect(revealed.hiddenPaths, state.hiddenPaths);
      expect(revealed.displayEntries, isNot(state.displayEntries));
    });
  });

  // ---------------------------------------------------------------------
  // ExplorerNotifier.toggleShowHidden + resolved-visibility wiring
  // ---------------------------------------------------------------------
  group('ExplorerNotifier.toggleShowHidden', () {
    late ProviderContainer container;
    late _FakeAgentClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      client = _FakeAgentClient(host: _testHost);
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    test('flips state.showHidden and reveals filtered entries', () async {
      client.pages['/'] = [
        Listing(
          path: '/',
          entries: [_file('readme.txt'), _file('.env')],
          nextCursor: null,
        ),
      ];

      final arg = (hostId: 'h4', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      var state = container.read(explorerProvider(arg));
      expect(state.showHidden, isFalse);
      expect(state.hiddenCount, 1);
      expect(state.displayEntries.map((e) => e.name), ['readme.txt']);

      notifier.toggleShowHidden();

      state = container.read(explorerProvider(arg));
      expect(state.showHidden, isTrue);
      expect(state.displayEntries.map((e) => e.name).toSet(), {
        'readme.txt',
        '.env',
      });
    });

    test('mirrors the resolved app-default visibility into '
        'ExplorerState.visibilityPrefs', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('app.log')], nextCursor: null),
      ];

      final arg = (hostId: 'h5', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      expect(container.read(explorerProvider(arg)).hiddenCount, 0);

      // Editing the app-default visibility (hostId null) flows through the
      // settings model and is mirrored into this explorer's state.
      await container.read(settingsProvider.future);
      await container.read(settingsProvider.notifier).setHiddenExtensions({
        'log',
      });

      await _waitUntil(
        () => container.read(explorerProvider(arg)).hiddenCount == 1,
      );

      final state = container.read(explorerProvider(arg));
      expect(state.hiddenPaths, {'/root/app.log'});
    });

    test(
      'a per-device visibility override takes precedence for that host',
      () async {
        client.pages['/'] = [
          Listing(path: '/', entries: [_file('app.log')], nextCursor: null),
        ];

        final arg = (hostId: 'h6', rootPath: '/');
        container.listen(explorerProvider(arg), (_, _) {});
        await _waitUntil(
          () => container.read(explorerProvider(arg)).entries.isNotEmpty,
        );

        // Override just this host to hide ".log"; the app default is untouched.
        await container.read(settingsProvider.future);
        await container.read(settingsProvider.notifier).setHiddenExtensions({
          'log',
        }, hostId: 'h6');

        await _waitUntil(
          () => container.read(explorerProvider(arg)).hiddenCount == 1,
        );
        expect(container.read(explorerProvider(arg)).hiddenPaths, {
          '/root/app.log',
        });
      },
    );
  });

  // ---------------------------------------------------------------------
  // ExplorerNotifier pagination via loadMore()
  // ---------------------------------------------------------------------
  group('ExplorerNotifier.loadMore', () {
    late ProviderContainer container;
    late _FakeAgentClient client;

    setUp(() {
      client = _FakeAgentClient(host: _testHost);
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    test('first load fetches page 1 and stores nextCursor', () async {
      client.pages['/'] = [
        Listing(
          path: '/',
          entries: [_file('a.txt'), _file('b.txt')],
          nextCursor: 'page2',
        ),
      ];

      final arg = (hostId: 'h1', rootPath: '/');
      // Keep the autoDispose provider alive for the duration of the test —
      // without an active listener, container.read() alone schedules
      // disposal at the end of each microtask, which would tear down and
      // rebuild the notifier (re-triggering _load and resetting state)
      // between polling iterations below.
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);

      // Wait for the microtask-scheduled initial _load to complete.
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      final state = container.read(explorerProvider(arg));
      expect(state.entries.map((e) => e.name), ['a.txt', 'b.txt']);
      expect(state.nextCursor, 'page2');
      expect(state.hasMore, isTrue);

      // loadMore appends page 2 and clears the cursor (no further pages).
      client.cursorPages['page2'] = Listing(
        path: '/',
        entries: [_file('c.txt')],
        nextCursor: null,
      );
      await notifier.loadMore();

      final after = container.read(explorerProvider(arg));
      expect(after.entries.map((e) => e.name), ['a.txt', 'b.txt', 'c.txt']);
      expect(after.nextCursor, isNull);
      expect(after.hasMore, isFalse);
      expect(after.loadingMore, isFalse);
    });

    test('loadMore is a no-op when there is no next cursor', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt')], nextCursor: null),
      ];

      final arg = (hostId: 'h2', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      final before = container.read(explorerProvider(arg));
      expect(before.hasMore, isFalse);

      await notifier.loadMore();

      final after = container.read(explorerProvider(arg));
      // Unchanged — still just the one entry from the initial load.
      expect(after.entries.map((e) => e.name), ['a.txt']);
    });

    test('navigating to a new path resets pagination state', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt')], nextCursor: 'page2'),
      ];
      client.pages['/sub'] = [
        Listing(path: '/sub', entries: [_file('only.txt')], nextCursor: null),
      ];

      final arg = (hostId: 'h3', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      var state = container.read(explorerProvider(arg));
      expect(state.nextCursor, 'page2');

      notifier.navigate('/sub');
      await _waitUntil(
        () => container
            .read(explorerProvider(arg))
            .entries
            .any((e) => e.name == 'only.txt'),
      );

      state = container.read(explorerProvider(arg));
      expect(state.entries.map((e) => e.name), ['only.txt']);
      expect(state.nextCursor, isNull);
      expect(state.hasMore, isFalse);
    });
  });

  group('ExplorerNotifier ABA staleness guard (PR-34)', () {
    late ProviderContainer container;
    late _FakeAgentClient client;

    setUp(() {
      client = _FakeAgentClient(host: _testHost);
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    test('a stale load for A resolving after navigate(A->B->A) does not '
        'clobber the fresh A result', () async {
      final gateA1 = Completer<void>();
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('stale-a.txt')]),
        Listing(path: '/', entries: [_file('fresh-a.txt')]),
      ];
      client.gates['/'] = [gateA1, null];
      client.pages['/sub'] = [
        Listing(path: '/sub', entries: [_file('b.txt')]),
      ];

      final arg = (hostId: 'aba1', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);

      // Let the microtask-scheduled initial _load() actually start (so it
      // captures path='/' and the pre-navigate generation) before we
      // navigate — it then blocks inside client.list() on gateA1.
      await _waitUntil(() => container.read(explorerProvider(arg)).loading);
      notifier.navigate('/sub');
      await _waitUntil(
        () => container
            .read(explorerProvider(arg))
            .entries
            .any((e) => e.name == 'b.txt'),
      );

      notifier.navigateTo(0); // back to '/' — a fresh, ungated load.
      await _waitUntil(
        () => container
            .read(explorerProvider(arg))
            .entries
            .any((e) => e.name == 'fresh-a.txt'),
      );

      // Release the stale first call for '/'; it must not overwrite the
      // fresh result that already landed.
      gateA1.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(explorerProvider(arg));
      expect(state.entries.map((e) => e.name), ['fresh-a.txt']);
    });
  });

  group('ExplorerNotifier.batchRename duplicate targets (PR-35)', () {
    late ProviderContainer container;
    late _FakeAgentClient client;

    setUp(() {
      client = _FakeAgentClient(host: _testHost);
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    test('two sources renamed to the same target are both rejected before '
        'either is touched', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt'), _file('b.txt')]),
      ];
      final arg = (hostId: 'dup1', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt'), _file('b.txt')]),
      ];
      final result = await notifier.batchRename([
        (path: '/root/a.txt', newName: 'same.txt'),
        (path: '/root/b.txt', newName: 'same.txt'),
      ]);

      expect(result.results, hasLength(2));
      expect(result.results.every((r) => !r.ok), isTrue);
      expect(
        result.results.every((r) => r.errorCode == 'DUPLICATE_TARGET'),
        isTrue,
      );
      // Neither source was ever renamed — rejected before touching files.
      expect(client.renameCalls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // ExplorerNotifier.collidingBasenames — pre-flight copy/move collision check
  // ---------------------------------------------------------------------
  group('ExplorerNotifier.collidingBasenames', () {
    late ProviderContainer container;
    late _FakeAgentClient client;

    setUp(() {
      client = _FakeAgentClient(host: _testHost);
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    test(
      'returns basenames of sources that already exist in destDir',
      () async {
        client.pages['/'] = [
          Listing(path: '/', entries: [_file('a.txt'), _file('b.txt')]),
        ];
        client.pages['/dest'] = [
          Listing(
            path: '/dest',
            entries: [_file('a.txt'), _file('other.txt')],
            nextCursor: null,
          ),
        ];

        final arg = (hostId: 'h6', rootPath: '/');
        container.listen(explorerProvider(arg), (_, _) {});
        final notifier = container.read(explorerProvider(arg).notifier);
        await _waitUntil(
          () => container.read(explorerProvider(arg)).entries.isNotEmpty,
        );

        final colliding = await notifier.collidingBasenames('/dest', [
          '/root/a.txt',
          '/root/b.txt',
        ]);

        expect(colliding, {'a.txt'});
      },
    );

    test('returns an empty set when nothing collides', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt')]),
      ];
      client.pages['/dest'] = [
        Listing(path: '/dest', entries: [_file('other.txt')], nextCursor: null),
      ];

      final arg = (hostId: 'h7', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      final colliding = await notifier.collidingBasenames('/dest', [
        '/root/a.txt',
      ]);

      expect(colliding, isEmpty);
    });

    test('pages through the full destination listing', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt')]),
      ];
      client.pages['/dest'] = [
        Listing(
          path: '/dest',
          entries: [_file('other.txt')],
          nextCursor: 'page2',
        ),
      ];
      client.cursorPages['page2'] = Listing(
        path: '/dest',
        entries: [_file('a.txt')],
        nextCursor: null,
      );

      final arg = (hostId: 'h8', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      final colliding = await notifier.collidingBasenames('/dest', [
        '/root/a.txt',
      ]);

      expect(colliding, {'a.txt'});
    });
  });

  // ---------------------------------------------------------------------
  // ExplorerNotifier.copySelected / moveSelected — conflict resolution params
  // ---------------------------------------------------------------------
  group('ExplorerNotifier.copySelected/moveSelected', () {
    late ProviderContainer container;
    late _FakeAgentClient client;

    setUp(() {
      client = _FakeAgentClient(host: _testHost);
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    /// Sets up an explorer at '/' with [selected] marked selected, with
    /// `pages['/']` registered twice — once for the initial load, once for
    /// the reload that copySelected/moveSelected triggers afterwards.
    Future<ExplorerNotifier> setUpExplorer(
      ProviderContainer container,
      ExplorerArg arg, {
      required Set<String> selected,
    }) async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('a.txt'), _file('b.txt')]),
        Listing(path: '/', entries: [_file('a.txt'), _file('b.txt')]),
      ];
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      for (final path in selected) {
        notifier.toggleSelect(path);
      }
      return notifier;
    }

    test(
      'copySelected with no extra args defaults to duplicate/overwrite false',
      () async {
        final arg = (hostId: 'h9', rootPath: '/');
        final notifier = await setUpExplorer(
          container,
          arg,
          selected: {'/root/a.txt'},
        );

        await notifier.copySelected('/dest');

        expect(client.copyMoveCalls, hasLength(1));
        final call = client.copyMoveCalls.single;
        expect(call.verb, 'copy');
        expect(call.sources, ['/root/a.txt']);
        expect(call.destDir, '/dest');
        expect(call.duplicate, isFalse);
        expect(call.overwrite, isFalse);
      },
    );

    test(
      'copySelected with duplicate:true passes duplicate through (Keep both)',
      () async {
        final arg = (hostId: 'h10', rootPath: '/');
        final notifier = await setUpExplorer(
          container,
          arg,
          selected: {'/root/a.txt'},
        );

        await notifier.copySelected('/dest', duplicate: true);

        expect(client.copyMoveCalls.single.duplicate, isTrue);
        expect(client.copyMoveCalls.single.overwrite, isFalse);
      },
    );

    test('moveSelected with overwrite:true passes overwrite through', () async {
      final arg = (hostId: 'h11', rootPath: '/');
      final notifier = await setUpExplorer(
        container,
        arg,
        selected: {'/root/a.txt'},
      );

      await notifier.moveSelected('/dest', overwrite: true);

      expect(client.copyMoveCalls, hasLength(1));
      final call = client.copyMoveCalls.single;
      expect(call.verb, 'move');
      expect(call.duplicate, isFalse);
      expect(call.overwrite, isTrue);
    });

    test(
      'an explicit sources list overrides state.selected (Skip filtering)',
      () async {
        final arg = (hostId: 'h12', rootPath: '/');
        final notifier = await setUpExplorer(
          container,
          arg,
          selected: {'/root/a.txt', '/root/b.txt'},
        );

        // Simulates the Skip resolution: caller filters out the colliding
        // source ('/root/a.txt') and passes only the non-colliding one.
        await notifier.moveSelected('/dest', sources: ['/root/b.txt']);

        expect(client.copyMoveCalls.single.sources, ['/root/b.txt']);
      },
    );
  });
}

/// Fake [AgentClient] that serves canned [Listing] pages from in-memory maps
/// instead of making network calls.
///
/// - [pages]: queue of responses for the *first* `list(path)` call (no
///   cursor) per path — consumed in order.
/// - [cursorPages]: response for `list(path, cursor: c)` keyed by cursor.
class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host}) : super(host);

  final Map<String, List<Listing>> pages = {};
  final Map<String, Listing> cursorPages = {};

  /// Per-path queue of optional gates, aligned with [pages]' queue for that
  /// path — the Nth call to `list(path)` awaits the Nth gate (if non-null)
  /// before returning. Lets tests control out-of-order resolution to
  /// reproduce ABA staleness races (PR-34).
  final Map<String, List<Completer<void>?>> gates = {};

  /// Every rename call, in order — used by batchRename tests (PR-35).
  final List<({String path, String dest})> renameCalls = [];

  @override
  Future<Entry> rename(String src, String dst) async {
    renameCalls.add((path: src, dest: dst));
    return Entry(name: dst.split('/').last, path: dst, isDir: false);
  }

  /// Records every [copy]/[move] call made through this client, in order,
  /// so tests can assert on the `sources`/`destDir`/`duplicate`/`overwrite`
  /// arguments that `ExplorerNotifier.copySelected`/`moveSelected` passed
  /// through.
  final List<_CopyMoveCall> copyMoveCalls = [];

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    if (cursor != null) {
      final listing = cursorPages[cursor];
      if (listing == null) {
        throw StateError('No fake page registered for cursor "$cursor"');
      }
      return listing;
    }
    final queue = pages[path];
    if (queue == null || queue.isEmpty) {
      throw StateError('No fake page registered for path "$path"');
    }
    final listing = queue.removeAt(0);
    final gateQueue = gates[path];
    if (gateQueue != null && gateQueue.isNotEmpty) {
      final gate = gateQueue.removeAt(0);
      if (gate != null) await gate.future;
    }
    return listing;
  }

  @override
  Future<BatchResult> copy(
    List<String> sources,
    String destDir, {
    bool duplicate = false,
    bool overwrite = false,
  }) async {
    copyMoveCalls.add(
      _CopyMoveCall(
        verb: 'copy',
        sources: sources,
        destDir: destDir,
        duplicate: duplicate,
        overwrite: overwrite,
      ),
    );
    return BatchResult(
      results: sources.map((s) => BatchItemResult(path: s, ok: true)).toList(),
    );
  }

  @override
  Future<BatchResult> move(
    List<String> sources,
    String destDir, {
    bool duplicate = false,
    bool overwrite = false,
  }) async {
    copyMoveCalls.add(
      _CopyMoveCall(
        verb: 'move',
        sources: sources,
        destDir: destDir,
        duplicate: duplicate,
        overwrite: overwrite,
      ),
    );
    return BatchResult(
      results: sources.map((s) => BatchItemResult(path: s, ok: true)).toList(),
    );
  }
}

class _CopyMoveCall {
  _CopyMoveCall({
    required this.verb,
    required this.sources,
    required this.destDir,
    required this.duplicate,
    required this.overwrite,
  });

  final String verb;
  final List<String> sources;
  final String destDir;
  final bool duplicate;
  final bool overwrite;
}
