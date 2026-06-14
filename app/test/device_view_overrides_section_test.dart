import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/settings/settings_controller.dart';
import 'package:remote_file_explorer/features/settings/widgets/device_view_overrides_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

// DeviceViewOverridesSection widget tests — the per-device "Use app default /
// Override" controls plus "Reset to app defaults".

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DeviceViewOverridesSection(hostId: 'h1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('defaults to inheriting — no overrides, reset disabled', (
    tester,
  ) async {
    final c = await pump(tester);

    expect(c.read(settingsProvider).valueOrNull!.hasOverride('h1'), isFalse);
    expect(find.text('Using app default (List)'), findsOneWidget);

    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reset to app defaults'),
    );
    expect(reset.onPressed, isNull, reason: 'nothing to reset');
  });

  testWidgets('toggling Layout override creates a device override', (
    tester,
  ) async {
    final c = await pump(tester);

    // The Layout row's switch is the first SwitchListTile.
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    final s = c.read(settingsProvider).valueOrNull!;
    expect(s.hasOverride('h1'), isTrue);
    expect(s.overridesFor('h1').gridView, isNotNull);
    expect(find.text('Overridden for this device'), findsOneWidget);
  });

  testWidgets('Reset clears all overrides for the host', (tester) async {
    final c = await pump(tester);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).valueOrNull!.hasOverride('h1'), isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Reset to app defaults'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).valueOrNull!.hasOverride('h1'), isFalse);
  });
}
