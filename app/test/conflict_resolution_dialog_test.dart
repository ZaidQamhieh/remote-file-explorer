import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/widgets/conflict_resolution_dialog.dart';

import 'l10n_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ConflictResolution?> pumpAndOpen(
    WidgetTester tester, {
    int collidingCount = 2,
    int totalCount = 5,
    String destLabel = 'Documents',
  }) async {
    ConflictResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showConflictResolutionDialog(
                      context,
                      collidingCount: collidingCount,
                      totalCount: totalCount,
                      destLabel: destLabel,
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the collision count and destination label', (
    tester,
  ) async {
    await pumpAndOpen(
      tester,
      collidingCount: 2,
      totalCount: 5,
      destLabel: 'Documents',
    );

    expect(find.text('2 of 5 items already exist in Documents.'), findsOne);
  });

  testWidgets('uses singular "item" when totalCount is 1', (tester) async {
    await pumpAndOpen(
      tester,
      collidingCount: 1,
      totalCount: 1,
      destLabel: 'Documents',
    );

    expect(find.text('1 of 1 item already exist in Documents.'), findsOne);
  });

  testWidgets('offers Cancel, Skip these, Keep both, and Overwrite', (
    tester,
  ) async {
    await pumpAndOpen(tester);

    expect(find.text('Cancel'), findsOne);
    expect(find.text('Skip these'), findsOne);
    expect(find.text('Keep both'), findsOne);
    expect(find.text('Overwrite'), findsOne);
  });

  testWidgets('tapping Keep both returns ConflictResolution.keepBoth', (
    tester,
  ) async {
    ConflictResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showConflictResolutionDialog(
                      context,
                      collidingCount: 1,
                      totalCount: 2,
                      destLabel: 'dest',
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();

    expect(result, ConflictResolution.keepBoth);
  });

  testWidgets('tapping Overwrite returns ConflictResolution.overwrite', (
    tester,
  ) async {
    ConflictResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showConflictResolutionDialog(
                      context,
                      collidingCount: 1,
                      totalCount: 2,
                      destLabel: 'dest',
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overwrite'));
    await tester.pumpAndSettle();

    expect(result, ConflictResolution.overwrite);
  });

  testWidgets('tapping Skip these returns ConflictResolution.skip', (
    tester,
  ) async {
    ConflictResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showConflictResolutionDialog(
                      context,
                      collidingCount: 1,
                      totalCount: 2,
                      destLabel: 'dest',
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip these'));
    await tester.pumpAndSettle();

    expect(result, ConflictResolution.skip);
  });

  testWidgets('tapping Cancel returns ConflictResolution.cancel', (
    tester,
  ) async {
    ConflictResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nDelegates,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showConflictResolutionDialog(
                      context,
                      collidingCount: 1,
                      totalCount: 2,
                      destLabel: 'dest',
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, ConflictResolution.cancel);
  });
}
