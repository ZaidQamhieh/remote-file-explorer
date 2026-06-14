import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:remote_file_explorer/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FileVisibilitySection widget tests — the App Settings "File visibility" card
// that edits the app-DEFAULT visibility (hostId null): hide-dotfiles switch,
// one section per category with a toggle chip per file type, and a "Custom"
// section (deletable chips + add field) at the end. Backed by the two-tier
// settings controller (settingsProvider).

VisibilityPrefs _appVis(ProviderContainer c) =>
    c.read(settingsProvider).valueOrNull!.app.visibility;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSection(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: FileVisibilitySection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('Hide dotfiles switch', () {
    testWidgets('defaults to on and toggling persists the choice',
        (tester) async {
      final container = await pumpSection(tester);

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );

      await tester.tap(find.text('Hide dotfiles'));
      await tester.pumpAndSettle();

      final prefs = _appVis(container);
      expect(prefs.hideDotfiles, isFalse);
    });
  });

  group('Category sections', () {
    testWidgets('each category renders as a labeled section', (tester) async {
      await pumpSection(tester);
      // Section headers are plain text (not chips), one per preset.
      for (final preset in visibilityPresets) {
        expect(find.text(preset.label), findsOneWidget);
      }
    });

    testWidgets('tapping a file-type chip toggles just that extension',
        (tester) async {
      final container = await pumpSection(tester);

      // ".log" is the Logs category's first file type.
      final before =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, '.log'));
      expect(before.selected, isFalse);

      await tester.tap(find.widgetWithText(FilterChip, '.log'));
      await tester.pumpAndSettle();

      var prefs = _appVis(container);
      expect(prefs.hiddenExtensions, contains('log'));
      // Only that one extension is hidden — not the whole category.
      expect(prefs.hiddenExtensions, isNot(contains('old')));
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '.log'))
            .selected,
        isTrue,
      );

      // Tapping again toggles it back off.
      await tester.tap(find.widgetWithText(FilterChip, '.log'));
      await tester.pumpAndSettle();
      prefs = _appVis(container);
      expect(prefs.hiddenExtensions, isNot(contains('log')));
    });

    testWidgets('tapping a name chip toggles an exact name', (tester) async {
      final container = await pumpSection(tester);

      // System junk includes the exact name "Thumbs.db".
      await tester.tap(find.widgetWithText(FilterChip, 'Thumbs.db'));
      await tester.pumpAndSettle();

      final prefs = _appVis(container);
      expect(prefs.hiddenNames, contains('Thumbs.db'));
    });
  });

  group('Custom section', () {
    testWidgets('a non-preset extension appears as a deletable custom chip',
        (tester) async {
      final container = await pumpSection(tester);

      expect(find.text('None — add an extension below.'), findsOneWidget);

      // "xyz" is not part of any preset, so it lands in the Custom section.
      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '.xyz'), findsOneWidget);
      expect(_appVis(container).hiddenExtensions,
          contains('xyz'));

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '.xyz'), findsNothing);
      expect(_appVis(container).hiddenExtensions,
          isNot(contains('xyz')));
    });

    testWidgets('a preset extension stays in its category, not Custom',
        (tester) async {
      final container = await pumpSection(tester);

      // "tmp" belongs to System junk, so typing it selects that category's
      // chip rather than creating a custom chip.
      await tester.enterText(find.byType(TextField), 'tmp');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_appVis(container).hiddenExtensions,
          contains('tmp'));
      // Rendered as a selected FilterChip (category), not an InputChip (custom).
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '.tmp'))
            .selected,
        isTrue,
      );
      expect(find.widgetWithText(InputChip, '.tmp'), findsNothing);
      expect(find.text('None — add an extension below.'), findsOneWidget);
    });
  });
}
