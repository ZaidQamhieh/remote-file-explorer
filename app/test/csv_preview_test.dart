import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/csv_preview.dart';

import 'l10n_helpers.dart';

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

  testWidgets('loads and renders CSV as a DataTable', (tester) async {
    const csv = 'Name,Age,City\nAlice,30,NYC\nBob,25,LA';
    final client = _FakeAgentClient(host: _testHost, content: csv);
    final entry = Entry(
      name: 'data.csv',
      path: '/data.csv',
      isDir: false,
      size: csv.length,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: CsvPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    // Headers rendered.
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Age'), findsOneWidget);
    expect(find.text('City'), findsOneWidget);
    // Data cells rendered.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(client.fetchCount, 1);
  });

  testWidgets('shows row count in app bar actions', (tester) async {
    const csv = 'A,B\n1,2\n3,4\n5,6';
    final client = _FakeAgentClient(host: _testHost, content: csv);
    final entry = Entry(
      name: 'small.csv',
      path: '/small.csv',
      isDir: false,
      size: csv.length,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: CsvPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 rows'), findsOneWidget);
  });

  testWidgets('shows empty state for empty file', (tester) async {
    final client = _FakeAgentClient(host: _testHost, content: '');
    final entry = Entry(
      name: 'empty.csv',
      path: '/empty.csv',
      isDir: false,
      size: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: CsvPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('(empty file)'), findsOneWidget);
  });

  testWidgets('singular row label for 1 data row', (tester) async {
    const csv = 'X\n42';
    final client = _FakeAgentClient(host: _testHost, content: csv);
    final entry = Entry(
      name: 'one.csv',
      path: '/one.csv',
      isDir: false,
      size: csv.length,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: CsvPreviewScreen(entry: entry, client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 row'), findsOneWidget);
  });
}
