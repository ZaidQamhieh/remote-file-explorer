import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's light and dark themes for the "distinctive modern" look.
///
/// Both are derived from the indigo [Brand.seed] with cyan [Brand.accent] wired
/// in as the scheme's secondary. Component themes are centralised here so the
/// roomier, rounded, tactile feel applies app-wide from one place — individual
/// screens mostly deal with layout, not restyling.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData lightWithSeed(Color seed) =>
      _build(Brightness.light, null, seed);
  static ThemeData darkWithSeed(Color seed) =>
      _build(Brightness.dark, null, seed);

  /// Builds the light theme from an optional [scheme] override (e.g. a
  /// platform dynamic-color scheme). When `null`, falls back to the seed-based
  /// [light] theme. All component theming is identical — only the source
  /// [ColorScheme] differs.
  static ThemeData lightFrom(ColorScheme? scheme) =>
      _build(Brightness.light, scheme);

  /// Dark counterpart to [lightFrom].
  static ThemeData darkFrom(ColorScheme? scheme) =>
      _build(Brightness.dark, scheme);

  static ThemeData toAmoled(ThemeData dark) {
    final scheme = dark.colorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF222222),
    );
    return dark.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
    );
  }

  static ThemeData _build(
    Brightness brightness, [
    ColorScheme? override,
    Color? seed,
  ]) {
    final scheme =
        override ??
        ColorScheme.fromSeed(
          seedColor: seed ?? Brand.seed,
          brightness: brightness,
          secondary: Brand.accent,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: Elevations.card,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardR),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardR),
        iconColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm + 2,
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm + 2,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipR),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: Radii.chipR,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.chipR,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.chipR,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card + 4),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(borderRadius: Radii.sheetTopR),
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card - 4),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: Spacing.md,
        thickness: 1,
      ),
    );
  }
}
