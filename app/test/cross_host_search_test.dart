import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/search/cross_host_search_screen.dart';

import 'l10n_helpers.dart';

void main() {
  const hosts = [
    Host(id: 'h1', label: 'Desktop', address: '192.168.1.10:8765'),
    Host(id: 'h2', label: 'Laptop', address: '192.168.1.20:8765'),
  ];

  Widget buildApp({List<Host> hostList = hosts}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: CrossHostSearchScreen(hosts: hostList),
      ),
    );
  }

  testWidgets('renders search field with hint text', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search all hosts...'), findsOneWidget);
  });

  testWidgets('shows empty prompt when query is blank', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('Type to search across all hosts'), findsOneWidget);
  });

  testWidgets('shows empty prompt for single-char query', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();

    // Single char is below the 2-char minimum, so still shows the prompt.
    expect(find.text('Type to search across all hosts'), findsOneWidget);
  });

  testWidgets('shows searching indicator after debounce', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'test query');
    // Advance past the 400ms debounce.
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Searching 2 hosts...'), findsOneWidget);
  });

  test('CrossHostResult associates host with entry', () {
    const host = Host(id: 'h1', label: 'PC', address: '127.0.0.1:1');
    const entry = Entry(name: 'file.txt', path: '/file.txt', isDir: false);
    final result = CrossHostResult(host, entry);
    expect(result.host.label, 'PC');
    expect(result.entry.name, 'file.txt');
  });

  testWidgets('accepts empty host list gracefully', (tester) async {
    await tester.pumpWidget(buildApp(hostList: const []));
    await tester.pump();

    expect(find.text('Type to search across all hosts'), findsOneWidget);
  });

  testWidgets('shows searching with correct host count', (tester) async {
    await tester.pumpWidget(
      buildApp(
        hostList: const [
          Host(id: 'h1', label: 'A', address: '127.0.0.1:1'),
          Host(id: 'h2', label: 'B', address: '127.0.0.1:2'),
          Host(id: 'h3', label: 'C', address: '127.0.0.1:3'),
        ],
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'test query');
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Searching 3 hosts...'), findsOneWidget);
  });
}
