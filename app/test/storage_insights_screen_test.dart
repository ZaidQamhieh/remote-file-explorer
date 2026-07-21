import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remote_file_explorer/core/models/drive.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/ui/state_views.dart';
import 'package:remote_file_explorer/features/explorer/drives_view.dart'
    show drivesProvider;
import 'package:remote_file_explorer/features/hosts/storage_insights_screen.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

const _host = Host(id: 'h1', label: 'Test PC', address: '100.64.0.1');

Widget _app(Override override) => ProviderScope(
  overrides: [override],
  child: wrapShad(
    const MaterialApp(
      localizationsDelegates: l10nDelegates,
      home: StorageInsightsScreen(host: _host),
    ),
  ),
);

void main() {
  testWidgets('renders the total card and a gauge per capacity drive', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        drivesProvider('h1').overrideWith(
          (ref) async => const [
            Drive(path: '/', totalBytes: 1000, freeBytes: 400, isOS: true),
            Drive(path: '/data', totalBytes: 2000, freeBytes: 1000),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Donut ring (total used/free) plus a breakdown row per capacity drive
    // (2) plus the aggregate "Free space" row.
    expect(find.text('53%'), findsOneWidget); // (3000-1400)/3000 = 53.3%
    expect(find.text('Free space'), findsOneWidget);
    expect(find.text('Open storage-by-type map'), findsOneWidget);
  });

  testWidgets('shows the empty view when no drive has capacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        drivesProvider(
          'h1',
        ).overrideWith((ref) async => const [Drive(path: '/mnt')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyFolderView), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows an error card when drives fail to load', (tester) async {
    await tester.pumpWidget(
      _app(
        drivesProvider(
          'h1',
        ).overrideWith((ref) async => throw Exception('boom')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorRetryCard), findsOneWidget);
    expect(find.textContaining('Could not load storage'), findsOneWidget);
  });
}
