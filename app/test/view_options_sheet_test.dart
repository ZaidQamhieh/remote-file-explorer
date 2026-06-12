import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/api/providers.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:remote_file_explorer/features/explorer/explorer_state.dart';
import 'package:remote_file_explorer/features/explorer/widgets/view_options_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ViewOptionsSheet widget tests — exercises the popover that folds list/grid,
// density, and sort into one persisted set of controls.
//
// Mirrors explorer_state_test.dart's setup: a fake AgentClient overriding
// clientProvider, plus a mocked path_provider channel for ListingCache.

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

class _EmptyAgentClient extends AgentClient {
  _EmptyAgentClient({required Host host}) : super(host);

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    return Listing(path: path, entries: const [], nextCursor: null);
  }
}

Future<void> _waitUntil(bool Function() predicate,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('rfe_view_options_test_');
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tmpDir.path;
        }
        return null;
      },
    );
  });

  Future<ExplorerNotifier> pumpSheet(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        clientProvider.overrideWith(
            (ref, hostId) async => _EmptyAgentClient(host: _testHost)),
      ],
    );
    addTearDown(container.dispose);

    const arg = (hostId: 'h1', rootPath: '/');
    container.listen(explorerProvider(arg), (_, _) {});
    final notifier = container.read(explorerProvider(arg).notifier);
    await _waitUntil(
        () => !container.read(explorerProvider(arg)).loading);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ViewOptionsSheet(
                state: container.read(explorerProvider(arg)),
                notifier: notifier,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  group('Layout (list/grid) control', () {
    testWidgets('toggling Grid persists per-host grid view', (tester) async {
      final notifier = await pumpSheet(tester);

      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();

      final prefs = notifier.ref.read(viewPrefsProvider).valueOrNull!;
      expect(prefs.gridViewFor('h1'), isTrue);
    });
  });

  group('Density control', () {
    testWidgets('toggling Compact persists density', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('Compact'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(ViewOptionsSheet)));
      final prefs = container.read(viewPrefsProvider).valueOrNull!;
      expect(prefs.density, EntryDensity.compact);
    });
  });

  group('Sort control', () {
    testWidgets('selecting a new field sorts ascending by that field',
        (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Size'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(ViewOptionsSheet)));
      final prefs = container.read(viewPrefsProvider).valueOrNull!;
      expect(prefs.sort.field, SortField.size);
      expect(prefs.sort.ascending, isTrue);
    });

    testWidgets('re-selecting the active field flips direction',
        (tester) async {
      await pumpSheet(tester);

      // First tap selects Name (already the default field) -> still
      // ascending=true initially, so tapping the already-active "Name" chip
      // flips it to descending.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Name'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(ViewOptionsSheet)));
      final prefs = container.read(viewPrefsProvider).valueOrNull!;
      expect(prefs.sort.field, SortField.name);
      expect(prefs.sort.ascending, isFalse);
    });

    testWidgets('shows an arrow icon on the active sort chip',
        (tester) async {
      await pumpSheet(tester);

      // Name is the default active field -> its chip shows a direction
      // arrow as its avatar.
      final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Name'));
      expect(chip.selected, isTrue);
      expect(chip.avatar, isNotNull);
    });
  });
}
