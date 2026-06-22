import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/explorer/widgets/chmod_dialog.dart';

const _testHost = Host(id: 'h', label: 'H', address: '127.0.0.1:1');

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient() : super(_testHost);

  Entry? chmodResult;
  String? lastPath;
  String? lastMode;

  @override
  Future<Entry> chmod(String path, String mode) async {
    lastPath = path;
    lastMode = mode;
    if (chmodResult != null) return chmodResult!;
    throw Exception('not configured');
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Entry _entry({String mode = '-rwxr-xr--'}) =>
    Entry(name: 'test.txt', path: '/home/test.txt', isDir: false, mode: mode);

void main() {
  group('ChmodDialog', () {
    testWidgets('renders permission checkboxes from mode string', (
      tester,
    ) async {
      final client = _FakeAgentClient();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed:
                    () => ChmodDialog.show(
                      context,
                      entry: _entry(),
                      client: client,
                    ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog title.
      expect(find.text('Permissions'), findsOneWidget);
      // Symbolic display: -rwxr-xr-- -> rwxr-xr--
      expect(find.text('rwxr-xr--'), findsOneWidget);
      // Octal display.
      expect(find.text('0754'), findsOneWidget);
      // Row labels.
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Group'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      // Buttons.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('toggling a checkbox updates octal display', (tester) async {
      final client = _FakeAgentClient();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed:
                    () => ChmodDialog.show(
                      context,
                      entry: _entry(mode: '----------'),
                      client: client,
                    ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Initially all zeros.
      expect(find.text('0000'), findsOneWidget);
      expect(find.text('---------'), findsOneWidget);

      // Tap the first checkbox (owner read).
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(9));
      await tester.tap(checkboxes.at(0));
      await tester.pump();

      // Owner read = 0400.
      expect(find.text('0400'), findsOneWidget);
      expect(find.text('r--------'), findsOneWidget);
    });

    testWidgets('apply calls chmod and pops with result', (tester) async {
      final client = _FakeAgentClient();
      final updatedEntry = Entry(
        name: 'test.txt',
        path: '/home/test.txt',
        isDir: false,
        mode: '-rwxr-xr--',
      );
      client.chmodResult = updatedEntry;

      Entry? dialogResult;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  dialogResult = await ChmodDialog.show(
                    context,
                    entry: _entry(),
                    client: client,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(client.lastPath, '/home/test.txt');
      expect(client.lastMode, '0754');
      expect(dialogResult, isNotNull);
      expect(dialogResult!.mode, '-rwxr-xr--');
    });

    testWidgets('cancel pops without calling chmod', (tester) async {
      final client = _FakeAgentClient();

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed:
                    () => ChmodDialog.show(
                      context,
                      entry: _entry(),
                      client: client,
                    ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // chmod was never called.
      expect(client.lastPath, isNull);
    });

    testWidgets('all permissions set produces 0777', (tester) async {
      final client = _FakeAgentClient();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed:
                    () => ChmodDialog.show(
                      context,
                      entry: _entry(mode: '-rwxrwxrwx'),
                      client: client,
                    ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('0777'), findsOneWidget);
      expect(find.text('rwxrwxrwx'), findsOneWidget);
    });

    testWidgets('shows error on chmod failure', (tester) async {
      final client = _FakeAgentClient(); // throws by default

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed:
                    () => ChmodDialog.show(
                      context,
                      entry: _entry(),
                      client: client,
                    ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Dialog stays open (not popped).
      expect(find.text('Permissions'), findsOneWidget);
      // Apply button is re-enabled.
      expect(find.text('Apply'), findsOneWidget);
    });
  });
}
