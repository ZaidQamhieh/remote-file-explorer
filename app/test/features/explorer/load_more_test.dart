// Tests for S2: cursor-based incremental listing via ExplorerNotifier.loadMore().
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/api/providers.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/features/explorer/explorer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _host = Host(id: 'h1', label: 'Test', address: '127.0.0.1:1');

Entry _file(String name) =>
    Entry(name: name, path: '/root/$name', isDir: false);

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline))
      fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Minimal fake: only overrides [list] — the only method exercised by these tests.
class _FakeClient extends AgentClient {
  _FakeClient() : super(_host);

  final Map<String, List<Listing>> pages = {};
  final Map<String, Listing> cursorPages = {};

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    if (cursor != null) {
      final page = cursorPages[cursor];
      if (page == null) throw StateError('no fake page for cursor "$cursor"');
      return page;
    }
    final queue = pages[path];
    if (queue == null || queue.isEmpty) {
      throw StateError('no fake page for path "$path"');
    }
    return queue.removeAt(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('rfe_load_more_test_');
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  group('ExplorerNotifier.loadMore — S2 incremental listing', () {
    late ProviderContainer container;
    late _FakeClient client;

    setUp(() {
      client = _FakeClient();
      container = ProviderContainer(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
      );
      addTearDown(container.dispose);
    });

    test(
      'appends entries from cursor page; hasMore false when nextCursor is null',
      () async {
        client.pages['/'] = [
          Listing(
            path: '/',
            entries: [_file('a.txt'), _file('b.txt')],
            nextCursor: 'page2',
          ),
        ];
        client.cursorPages['page2'] = Listing(
          path: '/',
          entries: [_file('c.txt')],
          nextCursor: null, // last page — allLoaded
        );

        final arg = (hostId: 'h1', rootPath: '/');
        container.listen(explorerProvider(arg), (_, _) {});
        final notifier = container.read(explorerProvider(arg).notifier);
        await _waitUntil(
          () => container.read(explorerProvider(arg)).entries.isNotEmpty,
        );

        // Initial page: cursor is set, more pages exist.
        var state = container.read(explorerProvider(arg));
        expect(state.entries.map((e) => e.name), ['a.txt', 'b.txt']);
        expect(state.hasMore, isTrue);

        await notifier.loadMore();

        // After page 2: entries merged, cursor cleared, fully loaded.
        state = container.read(explorerProvider(arg));
        expect(state.entries.map((e) => e.name), ['a.txt', 'b.txt', 'c.txt']);
        expect(state.nextCursor, isNull);
        expect(state.hasMore, isFalse);
        expect(state.loadingMore, isFalse);
      },
    );

    test('loadMore is a no-op when already fully loaded', () async {
      client.pages['/'] = [
        Listing(path: '/', entries: [_file('only.txt')], nextCursor: null),
      ];

      final arg = (hostId: 'h2', rootPath: '/');
      container.listen(explorerProvider(arg), (_, _) {});
      final notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () => container.read(explorerProvider(arg)).entries.isNotEmpty,
      );

      expect(container.read(explorerProvider(arg)).hasMore, isFalse);
      await notifier.loadMore(); // must not mutate or throw
      expect(container.read(explorerProvider(arg)).entries.map((e) => e.name), [
        'only.txt',
      ]);
    });
  });
}
