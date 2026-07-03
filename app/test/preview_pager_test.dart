import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/preview.dart';
import 'package:remote_file_explorer/features/preview/preview_actions.dart';
import 'package:remote_file_explorer/features/preview/text_preview.dart';

import 'l10n_helpers.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Widget tests for the swipeable PreviewPager and the text line-numbers toggle.
// Headless: a fake AgentClient returns canned text bytes per path, no real host.

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host, required this.contentByPath})
    : super(host);

  /// Canned text content keyed by remote path.
  final Map<String, String> contentByPath;

  @override
  Future<Uint8List> fetchBytes(
    String remotePath, {
    CancelToken? cancelToken,
  }) async {
    return Uint8List.fromList(utf8.encode(contentByPath[remotePath] ?? ''));
  }
}

Entry _txt(String name, {int? size}) =>
    Entry(name: name, path: '/dir/$name', isDir: false, size: size);

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(localizationsDelegates: l10nDelegates, home: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pager renders the shared top bar and the initial page', (
    tester,
  ) async {
    final client = _FakeAgentClient(
      host: _testHost,
      contentByPath: {'/dir/a.txt': 'alpha file', '/dir/b.txt': 'bravo file'},
    );
    final entries = [_txt('a.txt'), _txt('b.txt')];

    await tester.pumpWidget(
      _wrap(
        PreviewPager(
          entries: entries,
          initialIndex: 0,
          host: _testHost,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Shared top bar + the first page's content.
    expect(find.byType(PreviewTopBar), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget); // top-bar title
    expect(find.text('alpha file'), findsOneWidget); // page body

    // Shared actions present.
    expect(find.byIcon(LucideIcons.share), findsOneWidget);
    expect(find.byIcon(LucideIcons.folderOpen), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);

    // Page indicator shows "1 of 2".
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('line-numbers toggle shows and hides the gutter', (tester) async {
    final client = _FakeAgentClient(
      host: _testHost,
      contentByPath: {'/dir/a.txt': 'one\ntwo\nthree'},
    );

    await tester.pumpWidget(
      _wrap(TextPreviewScreen(entry: _txt('a.txt', size: 13), client: client)),
    );
    await tester.pumpAndSettle();

    // The text is present; no gutter line-number "1" yet (3-line file would
    // render numbers 1..3 only when the gutter is on).
    expect(find.text('one\ntwo\nthree'), findsOneWidget);
    expect(find.text('1\n2\n3'), findsNothing);

    // Toggle on.
    await tester.tap(find.byIcon(LucideIcons.listOrdered));
    await tester.pumpAndSettle();

    expect(find.text('1\n2\n3'), findsOneWidget); // gutter shown
    expect(find.text('one\ntwo\nthree'), findsOneWidget); // text still there

    // Toggle off again.
    await tester.tap(find.byIcon(LucideIcons.listOrdered));
    await tester.pumpAndSettle();
    expect(find.text('1\n2\n3'), findsNothing);
  });
}
