import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/archive_entry.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/archive_preview.dart';
import 'package:remote_file_explorer/features/preview/preview.dart';

import 'l10n_helpers.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host, this.entries = const [], this.error})
    : super(host);

  final List<ArchiveEntry> entries;
  final Exception? error;
  int archiveListCount = 0;

  @override
  Future<List<ArchiveEntry>> archiveList(String path, {int? limit}) async {
    archiveListCount++;
    if (error != null) throw error!;
    return entries;
  }
}

Entry _zipEntry(String name) =>
    Entry(name: name, path: '/archives/$name', isDir: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArchiveEntry.fromJson', () {
    test('parses correctly', () {
      final entry = ArchiveEntry.fromJson({
        'path': 'docs/readme.md',
        'size': 1024,
        'modified': '2026-01-01T00:00:00Z',
        'isDir': false,
      });
      expect(entry.path, 'docs/readme.md');
      expect(entry.size, 1024);
      expect(entry.isDir, false);
    });

    test('handles missing fields with defaults', () {
      final entry = ArchiveEntry.fromJson({});
      expect(entry.path, '');
      expect(entry.size, 0);
      expect(entry.isDir, false);
    });
  });

  group('ArchivePreviewScreen', () {
    testWidgets('shows loading then archive contents', (tester) async {
      final entries = [
        ArchiveEntry(
          path: 'src/',
          size: 0,
          modified: DateTime(2026),
          isDir: true,
        ),
        ArchiveEntry(
          path: 'src/main.dart',
          size: 2048,
          modified: DateTime(2026),
          isDir: false,
        ),
        ArchiveEntry(
          path: 'README.md',
          size: 512,
          modified: DateTime(2026),
          isDir: false,
        ),
      ];
      final client = _FakeAgentClient(host: _testHost, entries: entries);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: ArchivePreviewScreen(
            entry: _zipEntry('project.zip'),
            client: client,
          ),
        ),
      );

      // Loading state.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Contents rendered.
      expect(find.text('src/'), findsOneWidget);
      expect(find.text('src/main.dart'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
      // Entry count shown.
      expect(find.text('3 entries'), findsOneWidget);
      expect(client.archiveListCount, 1);
    });

    testWidgets('shows empty archive message', (tester) async {
      final client = _FakeAgentClient(host: _testHost);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: ArchivePreviewScreen(
            entry: _zipEntry('empty.zip'),
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Empty archive'), findsOneWidget);
    });

    testWidgets('shows error state with retry', (tester) async {
      final client = _FakeAgentClient(
        host: _testHost,
        error: Exception('network timeout'),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: ArchivePreviewScreen(
            entry: _zipEntry('broken.zip'),
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not read archive'), findsOneWidget);
    });

    testWidgets('tapping a directory filters to its contents', (tester) async {
      final entries = [
        ArchiveEntry(
          path: 'docs/',
          size: 0,
          modified: DateTime(2026),
          isDir: true,
        ),
        ArchiveEntry(
          path: 'docs/guide.md',
          size: 100,
          modified: DateTime(2026),
          isDir: false,
        ),
        ArchiveEntry(
          path: 'src/main.dart',
          size: 200,
          modified: DateTime(2026),
          isDir: false,
        ),
      ];
      final client = _FakeAgentClient(host: _testHost, entries: entries);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: ArchivePreviewScreen(
            entry: _zipEntry('project.zip'),
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All three visible initially.
      expect(find.text('docs/'), findsOneWidget);
      expect(find.text('docs/guide.md'), findsOneWidget);
      expect(find.text('src/main.dart'), findsOneWidget);

      // Tap the directory to filter.
      await tester.tap(find.text('docs/'));
      await tester.pumpAndSettle();

      // Only entries starting with 'docs/' visible.
      expect(find.text('docs/'), findsOneWidget);
      expect(find.text('docs/guide.md'), findsOneWidget);
      expect(find.text('src/main.dart'), findsNothing);

      // Filter breadcrumb shown.
      expect(find.text('/docs/'), findsOneWidget);
    });

    testWidgets('singular entry label for 1 entry', (tester) async {
      final entries = [
        ArchiveEntry(
          path: 'only.txt',
          size: 42,
          modified: DateTime(2026),
          isDir: false,
        ),
      ];
      final client = _FakeAgentClient(host: _testHost, entries: entries);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: ArchivePreviewScreen(
            entry: _zipEntry('single.zip'),
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 entry'), findsOneWidget);
    });
  });

  group('archive preview routing', () {
    test('archive extensions are previewable', () {
      for (final ext in ['zip', 'tar', 'gz', 'tgz', 'bz2', '7z', 'rar']) {
        final entry = Entry(
          name: 'test.$ext',
          path: '/test.$ext',
          isDir: false,
        );
        expect(isPreviewable(entry), isTrue, reason: ext);
      }
    });

    test('archive entries count among previewable siblings', () {
      final zip = Entry(name: 'a.zip', path: '/a.zip', isDir: false);
      final txt = Entry(name: 'b.txt', path: '/b.txt', isDir: false);
      final blob = Entry(name: 'c.bin', path: '/c.bin', isDir: false);
      final r = previewableSiblings([zip, txt, blob], zip);
      expect(r.entries.map((e) => e.name), ['a.zip', 'b.txt']);
      expect(r.index, 0);
    });
  });
}
