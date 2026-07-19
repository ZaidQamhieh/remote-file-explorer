import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/markdown_preview.dart';

import 'l10n_helpers.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host, required this.content}) : super(host);

  final String content;
  int fetchCount = 0;

  @override
  Future<Uint8List> fetchBytes(
    String remotePath, {
    CancelToken? cancelToken,
    int maxBytes = AgentClient.kFetchBytesDefaultMaxBytes,
  }) async {
    fetchCount++;
    return Uint8List.fromList(utf8.encode(content));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads and renders markdown content', (tester) async {
    final client = _FakeAgentClient(
      host: _testHost,
      content: '# Hello\n\nSome **bold** text.',
    );
    final entry = Entry(
      name: 'README.md',
      path: '/docs/README.md',
      isDir: false,
      size: 30,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: MarkdownPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    // Rendered markdown should show the Markdown widget.
    expect(find.byType(Markdown), findsOneWidget);
    expect(client.fetchCount, 1);
  });

  testWidgets('raw toggle shows raw markdown source', (tester) async {
    const source = '# Title\n\nParagraph text.';
    final client = _FakeAgentClient(host: _testHost, content: source);
    final entry = Entry(
      name: 'notes.md',
      path: '/notes.md',
      isDir: false,
      size: source.length,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: MarkdownPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    // Initially shows rendered markdown.
    expect(find.byType(Markdown), findsOneWidget);

    // Tap the raw toggle (code icon).
    await tester.tap(find.byIcon(LucideIcons.fileText));
    await tester.pumpAndSettle();

    // Now shows raw source as SelectableText, not Markdown widget.
    expect(find.byType(Markdown), findsNothing);
    expect(find.text(source), findsOneWidget);
  });

  testWidgets('shows empty state for empty file', (tester) async {
    final client = _FakeAgentClient(host: _testHost, content: '');
    final entry = Entry(
      name: 'empty.md',
      path: '/empty.md',
      isDir: false,
      size: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: MarkdownPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('(empty file)'), findsOneWidget);
  });
}
