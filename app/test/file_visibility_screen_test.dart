import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:remote_file_explorer/features/settings/file_visibility_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

// FileVisibilityScreen widget tests — the drill-in that replaced the old
// inline file-visibility card: hide-dotfiles toggle, one collapsed
// ExpansionTile per category (with a hidden count + master switch), and the
// "Custom" section (deletable chips + add field). Edits the app-DEFAULT
// visibility (hostId null) via the two-tier settings controller.

VisibilityPrefs _appVis(ProviderContainer c) =>
    c.read(settingsProvider).valueOrNull!.app.visibility;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapShad(
          const MaterialApp(
            localizationsDelegates: l10nDelegates,
            home: FileVisibilityScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('categories render collapsed by default', (tester) async {
    await pumpScreen(tester);
    // Collapsed: category labels are visible, but their chips aren't.
    for (final preset in visibilityPresets) {
      expect(find.textContaining(preset.label), findsOneWidget);
    }
    expect(find.widgetWithText(FilterChip, '.log'), findsNothing);
  });

  testWidgets('expanding a category reveals its chips', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.textContaining(logsPreset.label));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilterChip, '.log'), findsOneWidget);
  });

  testWidgets('the first category master switch applies/removes the preset', (
    tester,
  ) async {
    final container = await pumpScreen(tester);

    // "Hide dotfiles" is now a ShadSwitch (SettingsTile.toggle); category
    // master switches are still plain Switch, so the first one is index 0.
    final switchFinder = find.byType(Switch).first;
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    var prefs = _appVis(container);
    for (final ext in systemJunkPreset.extensions) {
      expect(prefs.hiddenExtensions, contains(ext));
    }
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    prefs = _appVis(container);
    for (final ext in systemJunkPreset.extensions) {
      expect(prefs.hiddenExtensions, isNot(contains(ext)));
    }
  });

  testWidgets('dotfiles toggle flips hideDotfiles', (tester) async {
    final container = await pumpScreen(tester);

    expect(_appVis(container).hideDotfiles, isTrue);

    // "Hide dotfiles" is now a ShadSwitch (SettingsTile.toggle).
    await tester.tap(find.byType(AnimatedContainer).first);
    await tester.pumpAndSettle();

    expect(_appVis(container).hideDotfiles, isFalse);
  });

  testWidgets('a non-preset extension appears as a deletable custom chip', (
    tester,
  ) async {
    final container = await pumpScreen(tester);

    // The custom-extension field sits below the category list — scroll it
    // into view first.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '.xyz'), findsOneWidget);
    expect(_appVis(container).hiddenExtensions, contains('xyz'));

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '.xyz'), findsNothing);
    expect(_appVis(container).hiddenExtensions, isNot(contains('xyz')));
  });
}
