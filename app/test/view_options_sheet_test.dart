import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/api/providers.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:remote_file_explorer/features/explorer/explorer_state.dart';
import 'package:remote_file_explorer/features/explorer/widgets/view_options_sheet.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

// ViewOptionsSheet widget tests — exercises the popover that folds list/grid,
// density, and sort into one persisted set of controls.
//
// Mirrors explorer_state_test.dart's setup: a fake AgentClient overriding
// clientProvider, plus a mocked path_provider channel for ListingCache.

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

/// Returns [entries] (default empty) for any directory listing — lets tests
/// seed [ExplorerState.hiddenCount] without a full fake-client setup.
class _EmptyAgentClient extends AgentClient {
  _EmptyAgentClient({required Host host, this.entries = const []})
    : super(host);

  final List<Entry> entries;

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    return Listing(path: path, entries: entries, nextCursor: null);
  }
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
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

  /// Pumps [ViewOptionsSheet] backed by an explorer state whose entries are
  /// [entries] (default empty — no hidden items). Returns the container so
  /// callers can re-read [ExplorerState] (e.g. after a toggle) and the
  /// notifier for the host's "h1" explorer provider.
  Future<(ProviderContainer, ExplorerNotifier)> pumpSheet(
    WidgetTester tester, {
    List<Entry> entries = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        clientProvider.overrideWith(
          (ref, hostId) async =>
              _EmptyAgentClient(host: _testHost, entries: entries),
        ),
      ],
    );
    addTearDown(container.dispose);

    const arg = (hostId: 'h1', rootPath: '/');
    late ExplorerNotifier notifier;
    // ListingCache does real file I/O, so both creating the notifier (which
    // schedules its initial _load) and waiting for that load to land need to
    // run via runAsync to progress inside testWidgets' fake-async zone.
    await tester.runAsync(() async {
      container.listen(explorerProvider(arg), (_, _) {});
      notifier = container.read(explorerProvider(arg).notifier);
      await _waitUntil(
        () =>
            !container.read(explorerProvider(arg)).loading &&
            container.read(explorerProvider(arg)).entries.length ==
                entries.length,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapShad(
          MaterialApp(
            localizationsDelegates: l10nDelegates,
            home: Scaffold(
              body: Builder(
                builder: (context) => ViewOptionsSheet(notifier: notifier),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, notifier);
  }

  group('Layout (list/grid) control', () {
    testWidgets('toggling Grid persists per-host grid view', (tester) async {
      final (_, notifier) = await pumpSheet(tester);

      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();

      final settings = notifier.ref.read(settingsProvider).valueOrNull!;
      expect(settings.app.gridView, isTrue);
    });

    // Regression (BUGS_REPORTED.md): the sheet must reflect the live explorer
    // state, not a snapshot captured when it opened. Before the fix the
    // segmented control kept its open-time selection, so tapping Grid changed
    // the listing but the selected segment never moved.
    testWidgets('selected Layout segment updates after tapping Grid', (
      tester,
    ) async {
      final (container, _) = await pumpSheet(tester);
      const arg = (hostId: 'h1', rootPath: '/');
      expect(
        container.read(explorerProvider(arg)).gridView,
        isFalse,
        reason: 'starts on List',
      );

      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();

      expect(
        container.read(explorerProvider(arg)).gridView,
        isTrue,
        reason: 'selection must follow the live state, not the snapshot',
      );
    });
  });

  group('Density control', () {
    testWidgets('toggling Compact persists density', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('Compact'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViewOptionsSheet)),
      );
      final settings = container.read(settingsProvider).valueOrNull!;
      expect(settings.app.density, EntryDensity.compact);
    });
  });

  group('Sort control', () {
    testWidgets('selecting a new field sorts ascending by that field', (
      tester,
    ) async {
      final (container, _) = await pumpSheet(tester);

      await tester.tap(find.text('Size'));
      await tester.pumpAndSettle();

      const arg = (hostId: 'h1', rootPath: '/');
      final sort = container.read(explorerProvider(arg)).sort;
      expect(sort.field, SortField.size);
      expect(sort.ascending, isTrue);
    });

    testWidgets('re-selecting the active field flips direction', (
      tester,
    ) async {
      final (container, _) = await pumpSheet(tester);

      // First tap selects Name (already the default field) -> still
      // ascending=true initially, so tapping the already-active "Name" row
      // flips it to descending.
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();

      const arg = (hostId: 'h1', rootPath: '/');
      final sort = container.read(explorerProvider(arg)).sort;
      expect(sort.field, SortField.name);
      expect(sort.ascending, isFalse);
    });

    testWidgets('shows a direction arrow on the active sort row', (
      tester,
    ) async {
      await pumpSheet(tester);

      // Name is the default active field, ascending -> shows an up arrow;
      // no other row shows a direction icon.
      expect(find.byIcon(LucideIcons.arrowUp), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowDown), findsNothing);
    });
  });

  group('Show hidden files toggle', () {
    testWidgets('shows hidden count as a subtitle and toggles showHidden '
        'when entries include hidden items', (tester) async {
      // Default VisibilityPrefs hides dotfiles, so the ".env" entry below
      // makes ExplorerState.hiddenCount == 1.
      final (container, _) = await pumpSheet(
        tester,
        entries: const [
          Entry(name: 'readme.txt', path: '/readme.txt', isDir: false),
          Entry(name: '.env', path: '/.env', isDir: false),
        ],
      );

      const arg = (hostId: 'h1', rootPath: '/');
      expect(container.read(explorerProvider(arg)).hiddenCount, 1);
      expect(find.text('1 hidden by file visibility settings'), findsOneWidget);
      expect(container.read(explorerProvider(arg)).showHidden, isFalse);

      await tester.tap(find.text('Show hidden items'));
      await tester.pumpAndSettle();

      expect(container.read(explorerProvider(arg)).showHidden, isTrue);
    });

    testWidgets('has no subtitle when there are no hidden entries', (
      tester,
    ) async {
      final (container, _) = await pumpSheet(
        tester,
        entries: const [
          Entry(name: 'readme.txt', path: '/readme.txt', isDir: false),
        ],
      );

      const arg = (hostId: 'h1', rootPath: '/');
      expect(container.read(explorerProvider(arg)).hiddenCount, 0);
      expect(
        find.textContaining('hidden by file visibility settings'),
        findsNothing,
      );
      // The toggle itself is always present (mockup's Options card shows it
      // unconditionally), unlike the old count-gated tile.
      expect(find.text('Show hidden items'), findsOneWidget);
    });
  });
}
