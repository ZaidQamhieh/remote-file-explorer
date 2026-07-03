import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/text_editor.dart';

import 'l10n_helpers.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// TextEditorScreen widget tests — headless (fake AgentClient, no real host).
//
// Covers: the editor loads and displays the text it was constructed with;
// tapping Save calls putContent with the right path + bytes + baseModified;
// a STALE_WRITE response surfaces the Reload/Overwrite dialog (both paths);
// READ_ONLY and PAYLOAD_TOO_LARGE surface via showError; and the
// unsaved-changes guard triggers a discard confirmation on back navigation.

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

final _baseModified = DateTime.utc(2026, 1, 1, 12, 0, 0);

Entry _textEntry({DateTime? modified}) => Entry(
  name: 'notes.txt',
  path: '/docs/notes.txt',
  isDir: false,
  size: 11,
  modified: modified ?? _baseModified,
);

/// A minimal [AgentClient] subclass that captures [putContent] calls and lets
/// each test script the outcome (success, or a specific typed exception).
class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host}) : super(host);

  /// Calls captured as `(path, text, baseModified)`.
  final List<(String, String, DateTime?)> putCalls = [];

  /// Queue of behaviors for successive [putContent] calls. Each entry is
  /// either an [Entry] to return, or an [Exception] to throw.
  final List<Object> putResults = [];

  /// Returned by [fetchBytes] / [meta] when reload is exercised.
  String reloadedText = 'reloaded from host';
  DateTime reloadedModified = DateTime.utc(2026, 1, 2, 0, 0, 0);

  @override
  Future<Entry> putContent(
    String remotePath,
    Uint8List bytes, {
    DateTime? baseModified,
  }) async {
    putCalls.add((remotePath, utf8.decode(bytes), baseModified));
    final result =
        putResults.isNotEmpty
            ? putResults.removeAt(0)
            : Entry(
              name: 'notes.txt',
              path: remotePath,
              isDir: false,
              modified: baseModified,
            );
    if (result is Exception) throw result;
    return result as Entry;
  }

  @override
  Future<Uint8List> fetchBytes(
    String remotePath, {
    CancelToken? cancelToken,
  }) async {
    return Uint8List.fromList(utf8.encode(reloadedText));
  }

  @override
  Future<Entry> meta(String path) async {
    return Entry(
      name: 'notes.txt',
      path: path,
      isDir: false,
      modified: reloadedModified,
    );
  }
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _FakeAgentClient client, {
  String initialText = 'hello world',
  Entry? entry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: l10nDelegates,
      home: TextEditorScreen(
        entry: entry ?? _textEntry(),
        client: client,
        initialText: initialText,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAgentClient client;

  setUp(() {
    client = _FakeAgentClient(host: _testHost);
  });

  group('Loading', () {
    testWidgets('shows the fetched text in an editable field', (tester) async {
      await _pumpEditor(tester, client, initialText: 'line one\nline two');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'line one\nline two');
      expect(field.maxLines, isNull); // multi-line / expands
      expect(field.expands, isTrue);
    });

    testWidgets('Save button is disabled until the text is edited', (
      tester,
    ) async {
      await _pumpEditor(tester, client);

      final saveButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, LucideIcons.save),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('Save', () {
    testWidgets(
      'tapping Save calls putContent with path, bytes, and baseModified',
      (tester) async {
        final entry = _textEntry(modified: _baseModified);
        await _pumpEditor(
          tester,
          client,
          initialText: 'hello world',
          entry: entry,
        );

        await tester.enterText(find.byType(TextField), 'hello world!');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(LucideIcons.save));
        await tester.pumpAndSettle();

        expect(client.putCalls, hasLength(1));
        final (path, text, baseModified) = client.putCalls.single;
        expect(path, '/docs/notes.txt');
        expect(text, 'hello world!');
        expect(baseModified, _baseModified);

        // Success feedback shown.
        expect(find.text('Saved "notes.txt"'), findsOneWidget);
      },
    );

    testWidgets(
      'after a successful save, baseModified updates for the next save',
      (tester) async {
        final entry = _textEntry(modified: _baseModified);
        final newModified = DateTime.utc(2026, 1, 1, 13, 0, 0);
        client.putResults.add(
          Entry(
            name: 'notes.txt',
            path: entry.path,
            isDir: false,
            modified: newModified,
          ),
        );

        await _pumpEditor(
          tester,
          client,
          initialText: 'hello world',
          entry: entry,
        );

        await tester.enterText(find.byType(TextField), 'edit one');
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.save));
        await tester.pumpAndSettle();

        // Second edit + save should send the *updated* baseModified.
        await tester.enterText(find.byType(TextField), 'edit two');
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.save));
        await tester.pumpAndSettle();

        expect(client.putCalls, hasLength(2));
        expect(client.putCalls[0].$3, _baseModified);
        expect(client.putCalls[1].$3, newModified);
      },
    );
  });

  group('STALE_WRITE (409)', () {
    testWidgets('surfaces a Reload/Overwrite dialog', (tester) async {
      client.putResults.add(StaleWriteException('file changed on disk'));

      await _pumpEditor(tester, client, initialText: 'hello world');
      await tester.enterText(find.byType(TextField), 'hello world!');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.save));
      await tester.pumpAndSettle();

      expect(find.text('File changed on disk'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Reload'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Overwrite'), findsOneWidget);
    });

    testWidgets('Reload re-fetches content and clears the dirty flag', (
      tester,
    ) async {
      client.putResults.add(StaleWriteException('file changed on disk'));
      client.reloadedText = 'fresh from disk';
      final newModified = DateTime.utc(2026, 1, 3, 0, 0, 0);
      client.reloadedModified = newModified;

      await _pumpEditor(tester, client, initialText: 'hello world');
      await tester.enterText(find.byType(TextField), 'hello world!');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.save));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'fresh from disk');

      // Dirty flag cleared -> Save disabled again.
      final saveButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, LucideIcons.save),
      );
      expect(saveButton.onPressed, isNull);

      // A subsequent edit + save should use the reloaded baseModified.
      await tester.enterText(find.byType(TextField), 'fresh from disk, edited');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.save));
      await tester.pumpAndSettle();

      expect(client.putCalls, hasLength(2));
      expect(client.putCalls.last.$3, newModified);
    });

    testWidgets('Overwrite re-saves with baseModified omitted', (tester) async {
      client.putResults.add(StaleWriteException('file changed on disk'));

      await _pumpEditor(tester, client, initialText: 'hello world');
      await tester.enterText(find.byType(TextField), 'hello world!');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.save));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Overwrite'));
      await tester.pumpAndSettle();

      expect(client.putCalls, hasLength(2));
      // First call (the one that failed) carried the original baseModified.
      expect(client.putCalls[0].$3, _baseModified);
      // The overwrite retry omits baseModified to force the write.
      expect(client.putCalls[1].$3, isNull);
      expect(find.text('Saved "notes.txt"'), findsOneWidget);
    });
  });

  group('READ_ONLY (403)', () {
    testWidgets('shows a read-only error message', (tester) async {
      client.putResults.add(ReadOnlyException('agent is read-only'));

      await _pumpEditor(tester, client, initialText: 'hello world');
      await tester.enterText(find.byType(TextField), 'hello world!');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.save));
      await tester.pumpAndSettle();

      expect(find.textContaining('read-only'), findsOneWidget);
    });
  });

  group('PAYLOAD_TOO_LARGE (413)', () {
    testWidgets('shows a too-large error message', (tester) async {
      client.putResults.add(PayloadTooLargeException('too large'));

      await _pumpEditor(tester, client, initialText: 'hello world');
      await tester.enterText(find.byType(TextField), 'hello world!');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.save));
      await tester.pumpAndSettle();

      expect(find.textContaining('too large'), findsOneWidget);
    });
  });

  group('Unsaved-changes guard', () {
    testWidgets('back navigation with unsaved changes prompts to discard', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: Navigator(
            onGenerateRoute:
                (settings) => MaterialPageRoute(
                  builder:
                      (context) => Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed:
                                () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => TextEditorScreen(
                                          entry: _textEntry(),
                                          client: client,
                                          initialText: 'hello world',
                                        ),
                                  ),
                                ),
                            child: const Text('Open editor'),
                          ),
                        ),
                      ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      // Dirty the editor.
      await tester.enterText(find.byType(TextField), 'hello world!');
      await tester.pumpAndSettle();

      // Attempt to pop via the back button.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);

      // "Keep editing" dismisses the dialog without popping.
      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(TextEditorScreen), findsOneWidget);

      // Now pop and confirm discard.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(TextEditorScreen), findsNothing);
      expect(find.text('Open editor'), findsOneWidget);
    });

    testWidgets('back navigation with no unsaved changes pops immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: Navigator(
            onGenerateRoute:
                (settings) => MaterialPageRoute(
                  builder:
                      (context) => Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed:
                                () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => TextEditorScreen(
                                          entry: _textEntry(),
                                          client: client,
                                          initialText: 'hello world',
                                        ),
                                  ),
                                ),
                            child: const Text('Open editor'),
                          ),
                        ),
                      ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(TextEditorScreen), findsNothing);
    });
  });
}
