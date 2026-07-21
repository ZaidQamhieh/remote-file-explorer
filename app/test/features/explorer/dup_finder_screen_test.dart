import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/features/explorer/dup_finder_screen.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

Entry _file(String path, {int size = 100}) =>
    Entry(name: path.split('/').last, path: path, isDir: false, size: size);

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient() : super(_testHost);

  /// path -> queue of pages returned in order (drives pagination via cursor).
  final Map<String, List<Listing>> pages = {};
  final Map<String, String> checksums = {};

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    final queue = pages[path];
    if (queue == null || queue.isEmpty) {
      return Listing(path: path, entries: const []);
    }
    return queue.removeAt(0);
  }

  @override
  Future<Map<String, String>> batchChecksums(
    List<String> paths, {
    String algo = 'sha256',
  }) async {
    return {
      for (final p in paths)
        if (checksums[p] != null) p: checksums[p]!,
    };
  }
}

void main() {
  testWidgets(
    'scan pages through the full directory listing before hashing (PR-33)',
    (tester) async {
      final client = _FakeAgentClient();
      // Root directory has two pages of files.
      client.pages['/root'] = [
        Listing(
          path: '/root',
          entries: [_file('/root/a.txt'), _file('/root/b.txt')],
          nextCursor: 'page2',
        ),
        Listing(
          path: '/root',
          entries: [_file('/root/c.txt')],
          nextCursor: null,
        ),
      ];
      // a.txt and c.txt (from different pages) are duplicates.
      client.checksums['/root/a.txt'] = 'hash1';
      client.checksums['/root/b.txt'] = 'hash2';
      client.checksums['/root/c.txt'] = 'hash1';

      await tester.pumpWidget(
        MaterialApp(
          home: DupFinderScreen(hostId: 'h1', path: '/root', client: client),
        ),
      );
      await tester.tap(find.text('Scan for Duplicates'));
      await tester.pumpAndSettle();

      // Found the cross-page duplicate group — mockup's two-stat summary
      // card (groups count / reclaimable size) replaces the old single
      // sentence header.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('groups'), findsOneWidget);
      expect(find.text('100 B'), findsWidgets);
      // SectionLabel upper-cases its title.
      expect(find.text('2 COPIES (100 B EACH)'), findsOneWidget);
    },
  );

  testWidgets('a scan that finds nothing across two pages shows no dupes', (
    tester,
  ) async {
    final client = _FakeAgentClient();
    client.pages['/root'] = [
      Listing(
        path: '/root',
        entries: [_file('/root/a.txt')],
        nextCursor: 'page2',
      ),
      Listing(path: '/root', entries: [_file('/root/b.txt')], nextCursor: null),
    ];
    client.checksums['/root/a.txt'] = 'hash1';
    client.checksums['/root/b.txt'] = 'hash2';

    await tester.pumpWidget(
      MaterialApp(
        home: DupFinderScreen(hostId: 'h1', path: '/root', client: client),
      ),
    );
    await tester.tap(find.text('Scan for Duplicates'));
    // Not pumpAndSettle: the empty state's GradientBlobHero runs a repeating
    // animation, so the widget tree never fully settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No duplicates found'), findsOneWidget);
  });
}
