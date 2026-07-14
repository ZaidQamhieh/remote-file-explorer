import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:remote_file_explorer/features/settings/appearance_settings_screen.dart';
import 'package:remote_file_explorer/features/settings/file_visibility_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_helpers.dart';

// Relocated from app_settings_screen_test.dart (Settings Overhaul, Task 5):
// these controls now live on AppearanceSettingsScreen, not the top-level nav.
//
// Restyled onto the shared row system (SettingsTile.value + showSettingsPicker):
// choice interactions are now tap-row -> pumpAndSettle -> tap-sheet-option ->
// pumpAndSettle, asserting the same provider-state transitions as before.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    // A tall surface so the Theme + Display sections all fit without
    // scrolling.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: l10nDelegates,
          home: AppearanceSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('changing Layout sets the app default', (tester) async {
    final c = await pump(tester);
    expect(c.read(settingsProvider).valueOrNull!.app.gridView, isFalse);

    // Layout is now a quick-toggle tile (tap cycles list<->grid directly),
    // not a row that opens a picker sheet.
    await tester.tap(find.text('Layout'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.app.gridView, isTrue);
  });

  testWidgets('changing Density sets the app default', (tester) async {
    final c = await pump(tester);

    // Density is now a quick-toggle tile (tap cycles comfortable<->compact
    // directly), not a row that opens a picker sheet.
    await tester.tap(find.text('Density'));
    await tester.pumpAndSettle();

    expect(
      c.read(settingsProvider).valueOrNull!.app.density,
      EntryDensity.compact,
    );
  });

  testWidgets('selecting a sort field sets the app default ascending', (
    tester,
  ) async {
    final c = await pump(tester);

    await tester.tap(find.text('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();

    final sort = c.read(settingsProvider).valueOrNull!.app.sort;
    expect(sort.field, SortField.size);
    expect(sort.ascending, isTrue);
  });

  testWidgets('re-tapping the active sort field flips direction', (
    tester,
  ) async {
    final c = await pump(tester);

    // Name is the default active field; tapping it flips to descending.
    await tester.tap(find.text('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    final sort = c.read(settingsProvider).valueOrNull!.app.sort;
    expect(sort.field, SortField.name);
    expect(sort.ascending, isFalse);
  });

  testWidgets('selecting Dark sets the app-wide theme mode', (tester) async {
    final c = await pump(tester);
    expect(
      c.read(settingsProvider).valueOrNull!.app.themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.app.themeMode, ThemeMode.dark);
  });

  testWidgets('toggling "Use wallpaper colors" flips dynamicColor', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(c.read(settingsProvider).valueOrNull!.app.dynamicColor, isTrue);

    // Now a quick-toggle tile — the whole tile is tappable, no Switch.
    await tester.tap(find.text('Use wallpaper colors'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.app.dynamicColor, isFalse);
  });

  // Guards the index-keyed nullable picker: selecting "Default" (a null Color)
  // must call setSeedColor(null) and stay distinguishable from a dismissed
  // sheet. Language uses the identical index-keyed mechanism.
  testWidgets(
    'Accent Color picker sets a colour, then resets to Default (null)',
    (tester) async {
      final c = await pump(tester);
      expect(c.read(settingsProvider).valueOrNull!.app.seedColor, isNull);

      await tester.tap(find.text('Accent Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blue'));
      await tester.pumpAndSettle();
      expect(
        c.read(settingsProvider).valueOrNull!.app.seedColor,
        const Color(0xFF2196F3),
      );

      await tester.tap(find.text('Accent Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).valueOrNull!.app.seedColor, isNull);
    },
  );

  testWidgets('tapping the File visibility row pushes FileVisibilityScreen', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('File visibility'));
    await tester.pumpAndSettle();

    expect(find.byType(FileVisibilityScreen), findsOneWidget);
  });
}
