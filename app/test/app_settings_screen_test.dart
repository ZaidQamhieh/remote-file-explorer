import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:remote_file_explorer/features/settings/app_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// AppSettingsScreen widget tests — the global "general settings" surface that
// edits the app-wide view defaults via settingsProvider.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    // A tall surface so the Appearance + Display sections all fit without
    // scrolling (the sort chips sit near the bottom of the list).
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
        child: const MaterialApp(home: AppSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('changing Layout sets the app default', (tester) async {
    final c = await pump(tester);
    expect(c.read(settingsProvider).valueOrNull!.app.gridView, isFalse);

    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.app.gridView, isTrue);
  });

  testWidgets('changing Density sets the app default', (tester) async {
    final c = await pump(tester);

    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.app.density,
        EntryDensity.compact);
  });

  testWidgets('selecting a sort field sets the app default ascending',
      (tester) async {
    final c = await pump(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Size'));
    await tester.pumpAndSettle();

    final sort = c.read(settingsProvider).valueOrNull!.app.sort;
    expect(sort.field, SortField.size);
    expect(sort.ascending, isTrue);
  });

  testWidgets('re-tapping the active sort field flips direction',
      (tester) async {
    final c = await pump(tester);

    // Name is the default active field; tapping it flips to descending.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Name'));
    await tester.pumpAndSettle();

    final sort = c.read(settingsProvider).valueOrNull!.app.sort;
    expect(sort.field, SortField.name);
    expect(sort.ascending, isFalse);
  });

  // --- Appearance (Wave F) -------------------------------------------------

  testWidgets('selecting Dark sets the app-wide theme mode', (tester) async {
    final c = await pump(tester);
    expect(c.read(settingsProvider).valueOrNull!.app.themeMode,
        ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(
        c.read(settingsProvider).valueOrNull!.app.themeMode, ThemeMode.dark);
  });

  testWidgets('toggling "Use wallpaper colors" flips dynamicColor',
      (tester) async {
    final c = await pump(tester);
    expect(c.read(settingsProvider).valueOrNull!.app.dynamicColor, isTrue);

    await tester.tap(find.text('Use wallpaper colors'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.app.dynamicColor, isFalse);
  });
}
