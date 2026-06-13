import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:remote_file_explorer/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FileVisibilitySection widget tests — the global "File visibility" settings
// card (hide-dotfiles switch, preset chips, hidden-extensions chips, and the
// add-extension field), backed by visibilityPrefsProvider.

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

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hideDotfiles, isFalse);
    });
  });

  group('Presets', () {
    testWidgets('tapping a preset chip adds its extensions and selects it',
        (tester) async {
      final container = await pumpSection(tester);

      final chipBefore =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Logs'));
      expect(chipBefore.selected, isFalse);

      await tester.tap(find.widgetWithText(FilterChip, 'Logs'));
      await tester.pumpAndSettle();

      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, containsAll(logsPreset.extensions));
      for (final ext in logsPreset.extensions) {
        expect(find.widgetWithText(InputChip, '.$ext'), findsOneWidget);
      }

      final chipAfter =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Logs'));
      expect(chipAfter.selected, isTrue);
    });

    testWidgets('tapping a selected preset chip removes it (toggles off)',
        (tester) async {
      final container = await pumpSection(tester);

      // Turn it on…
      await tester.tap(find.widgetWithText(FilterChip, 'Logs'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Logs'))
            .selected,
        isTrue,
      );

      // …then tap again to turn it off.
      await tester.tap(find.widgetWithText(FilterChip, 'Logs'));
      await tester.pumpAndSettle();

      final chip =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Logs'));
      expect(chip.selected, isFalse);
      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      for (final ext in logsPreset.extensions) {
        expect(prefs.hiddenExtensions, isNot(contains(ext)));
      }
    });
  });

  group('Custom extensions', () {
    testWidgets('adding an extension shows a chip and persists',
        (tester) async {
      final container = await pumpSection(tester);

      expect(find.text('None — add one below or use a preset above.'),
          findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tmp');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '.tmp'), findsOneWidget);
      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, contains('tmp'));
    });

    testWidgets('deleting a chip removes the extension', (tester) async {
      final container = await pumpSection(tester);
      await container.read(visibilityPrefsProvider.future);
      await container
          .read(visibilityPrefsProvider.notifier)
          .addExtension('tmp');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '.tmp'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '.tmp'), findsNothing);
      final prefs = container.read(visibilityPrefsProvider).valueOrNull!;
      expect(prefs.hiddenExtensions, isNot(contains('tmp')));
    });
  });
}
