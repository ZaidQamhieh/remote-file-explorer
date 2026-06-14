import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/theme/app_theme.dart';

// AppTheme (Wave F): the seed-based light/dark themes must keep working as the
// dynamic-color fallback, and the *From variants must honour an injected
// ColorScheme (e.g. a platform dynamic scheme) instead of the seed.

void main() {
  test('seed-based light/dark themes have the matching brightness', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppTheme.light.useMaterial3, isTrue);
  });

  test('lightFrom/darkFrom with null fall back to the seed scheme', () {
    // A null override must reproduce the seed-based themes exactly (same
    // primary), so the dynamic-color-off / no-platform-scheme path is safe.
    expect(AppTheme.lightFrom(null).colorScheme.primary,
        AppTheme.light.colorScheme.primary);
    expect(AppTheme.darkFrom(null).colorScheme.primary,
        AppTheme.dark.colorScheme.primary);
  });

  test('lightFrom/darkFrom use the provided ColorScheme', () {
    final customLight = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB00020),
      brightness: Brightness.light,
    );
    final customDark = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB00020),
      brightness: Brightness.dark,
    );

    final light = AppTheme.lightFrom(customLight);
    final dark = AppTheme.darkFrom(customDark);

    // The override scheme is used verbatim (not the brand seed).
    expect(light.colorScheme.primary, customLight.primary);
    expect(dark.colorScheme.primary, customDark.primary);
    expect(light.colorScheme.primary, isNot(AppTheme.light.colorScheme.primary));

    // Component theming is still applied (e.g. flat app bar with no tint),
    // proving only the source scheme changed.
    expect(light.appBarTheme.surfaceTintColor, Colors.transparent);
    expect(light.appBarTheme.backgroundColor, light.colorScheme.surface);
  });
}
