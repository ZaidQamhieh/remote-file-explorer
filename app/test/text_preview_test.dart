import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/preview_common.dart';
import 'package:remote_file_explorer/features/preview/text_editor.dart';
import 'package:remote_file_explorer/features/preview/text_preview.dart';

// TextPreviewScreen widget tests — headless (fake AgentClient, no real host).
//
// Covers: the preview loads and displays fetched text, and the Edit
// affordance opens TextEditorScreen pre-loaded with the same text (so it
// doesn't need to re-fetch).

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host, required this.content}) : super(host);

  final String content;
  int fetchCount = 0;

  @override
  Future<Uint8List> fetchBytes(String remotePath, {CancelToken? cancelToken}) async {
    fetchCount++;
    return Uint8List.fromList(utf8.encode(content));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads and displays fetched text', (tester) async {
    final client = _FakeAgentClient(host: _testHost, content: 'hello world');
    final entry = Entry(name: 'notes.txt', path: '/docs/notes.txt', isDir: false, size: 11);

    await tester.pumpWidget(
      MaterialApp(home: TextPreviewScreen(entry: entry, client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.text('hello world'), findsOneWidget);
    expect(client.fetchCount, 1);
  });

  testWidgets('shows an Edit action for small text files and opens the editor '
      'pre-loaded with the same text', (tester) async {
    final client = _FakeAgentClient(host: _testHost, content: 'hello world');
    final entry = Entry(
      name: 'notes.txt',
      path: '/docs/notes.txt',
      isDir: false,
      size: 11,
      modified: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(home: TextPreviewScreen(entry: entry, client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(TextEditorScreen), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hello world');

    // Opening the editor reuses the text already fetched by the preview.
    expect(client.fetchCount, 1);
  });

  testWidgets('does not show Edit for files over kMaxEditableBytes', (tester) async {
    final client = _FakeAgentClient(host: _testHost, content: 'hello world');
    final entry = Entry(
      name: 'notes.txt',
      path: '/docs/notes.txt',
      isDir: false,
      size: kMaxEditableBytes + 1,
    );

    await tester.pumpWidget(
      MaterialApp(home: TextPreviewScreen(entry: entry, client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
}
