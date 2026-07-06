import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remote_file_explorer/features/settings/widgets/settings_picker.dart';

void main() {
  testWidgets('returns the tapped option and marks the selected one', (
    tester,
  ) async {
    late final BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    final future = showSettingsPicker<ThemeMode>(
      ctx,
      title: 'Theme',
      selected: ThemeMode.dark,
      options: const [
        SettingsOption(
          ThemeMode.system,
          'System default',
          icon: LucideIcons.sunMoon,
        ),
        SettingsOption(ThemeMode.light, 'Light', icon: LucideIcons.sun),
        SettingsOption(ThemeMode.dark, 'Dark', icon: LucideIcons.moon),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    final result = await future;
    expect(result, ThemeMode.light);
  });
}
