import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/explorer_screen.dart';

// HiddenItemsFooter widget tests — the "N hidden · Show/Hide" footer rendered
// at the end of the list/grid when some entries are filtered by file-
// visibility prefs. Unlike _ShowHiddenTile (view_options_sheet_test.dart),
// this widget is a plain StatelessWidget with no provider dependencies, so it
// can be pumped directly with constructor args — no ProviderContainer/
// SharedPreferences/path_provider setup needed.

void main() {
  Future<void> pumpFooter(
    WidgetTester tester, {
    required int count,
    required bool revealed,
    required VoidCallback onToggle,
    bool compact = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HiddenItemsFooter(
            count: count,
            revealed: revealed,
            onToggle: onToggle,
            compact: compact,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the hidden count and "Show" when not revealed', (
    tester,
  ) async {
    await pumpFooter(tester, count: 3, revealed: false, onToggle: () {});

    expect(find.text('3 hidden · '), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);
  });

  testWidgets('shows "Hide" when entries are revealed', (tester) async {
    await pumpFooter(tester, count: 2, revealed: true, onToggle: () {});

    expect(find.text('2 hidden · '), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Show'), findsNothing);
  });

  testWidgets('tapping the footer invokes onToggle', (tester) async {
    var toggled = false;
    await pumpFooter(
      tester,
      count: 1,
      revealed: false,
      onToggle: () => toggled = true,
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(toggled, isTrue);
  });

  testWidgets('compact mode lays the label out in a column for grid cells', (
    tester,
  ) async {
    var toggled = false;
    await pumpFooter(
      tester,
      count: 5,
      revealed: false,
      onToggle: () => toggled = true,
      compact: true,
    );

    expect(find.text('5 hidden'), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    // Compact mode wraps the label in a Column instead of the full-width Row
    // used by the non-compact layout.
    expect(
      find.descendant(of: find.byType(InkWell), matching: find.byType(Column)),
      findsOneWidget,
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(toggled, isTrue);
  });
}
