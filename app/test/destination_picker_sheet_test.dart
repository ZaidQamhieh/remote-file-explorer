import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/api/providers.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/features/explorer/widgets/destination_picker_sheet.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

Entry _dir(String path) =>
    Entry(name: path.split('/').last, path: path, isDir: true);

Entry _file(String path) =>
    Entry(name: path.split('/').last, path: path, isDir: false, size: 5);

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host}) : super(host);

  final Map<String, Listing> pages = {};

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    final listing = pages[path];
    if (listing == null) {
      throw StateError('No fake page registered for path "$path"');
    }
    return listing;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAgentClient client;

  setUp(() {
    client = _FakeAgentClient(host: _testHost);
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required String originPath,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => ElevatedButton(
                    onPressed:
                        () => showDestinationPicker(
                          context,
                          hostId: 'h1',
                          originPath: originPath,
                          itemCount: 2,
                          isCopy: false,
                        ),
                    child: const Text('open'),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Let the sheet animate in and the initial _load microtask resolve.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shows only folders from the listing, not files', (tester) async {
    client.pages['/root'] = Listing(
      path: '/root',
      entries: [
        _dir('/root/Documents'),
        _file('/root/notes.txt'),
        _dir('/root/Photos'),
      ],
    );

    await pumpSheet(tester, originPath: '/root');

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
  });

  testWidgets('title shows the verb and item count', (tester) async {
    client.pages['/root'] = Listing(
      path: '/root',
      entries: [_dir('/root/Documents')],
    );

    await pumpSheet(tester, originPath: '/root');

    expect(find.textContaining('Move 2 items to'), findsOneWidget);
  });

  testWidgets('confirm button is disabled while showing the origin directory', (
    tester,
  ) async {
    client.pages['/root'] = Listing(
      path: '/root',
      entries: [_dir('/root/Documents')],
    );

    await pumpSheet(tester, originPath: '/root');

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Move here'),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('confirm button enables after navigating away from the origin', (
    tester,
  ) async {
    client.pages['/root'] = Listing(
      path: '/root',
      entries: [_dir('/root/Documents')],
    );
    client.pages['/root/Documents'] = Listing(
      path: '/root/Documents',
      entries: [],
    );

    await pumpSheet(tester, originPath: '/root');

    await tester.tap(find.text('Documents'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Move here'),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('confirming pops the sheet with the current directory path', (
    tester,
  ) async {
    client.pages['/root'] = Listing(
      path: '/root',
      entries: [_dir('/root/Documents')],
    );
    client.pages['/root/Documents'] = Listing(
      path: '/root/Documents',
      entries: [],
    );

    String? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientProvider.overrideWith((ref, hostId) async => client)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => ElevatedButton(
                    onPressed: () async {
                      result = await showDestinationPicker(
                        context,
                        hostId: 'h1',
                        originPath: '/root',
                        itemCount: 1,
                        isCopy: false,
                      );
                    },
                    child: const Text('open'),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Documents'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Move here'));
    await tester.pumpAndSettle();

    expect(result, '/root/Documents');
  });
}
