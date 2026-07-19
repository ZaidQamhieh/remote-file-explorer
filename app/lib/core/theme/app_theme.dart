import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'motion.dart';
import 'tokens.dart';

/// The app's light and dark themes for the "distinctive modern" look.
///
/// Both are derived from the indigo [Brand.seed] with cyan [Brand.accent] wired
/// in as the scheme's secondary. Component themes are centralised here so the
/// roomier, rounded, tactile feel applies app-wide from one place — individual
/// screens mostly deal with layout, not restyling.
class AppTheme {
  AppTheme._();

  /// Dark scheme matching the Figma spec (`figma.com/make/h4RTUMIg8O8KS2Uv9dG9GJ`):
  /// zinc-950/900/800 surfaces, blue-400 primary. Hand-picked rather than
  /// derived via [ColorScheme.fromSeed] because the algorithmic neutral ramp
  /// from a seed doesn't reproduce Tailwind's exact zinc stops. Only the
  /// default [dark] getter uses this — [darkWithSeed] (accent-color picker)
  /// and [darkFrom] (platform dynamic color) still derive their own scheme so
  /// those features are unaffected.
  static const ColorScheme _figmaDark = ColorScheme.dark(
    primary: Color(0xFF60A5FA), // blue-400
    onPrimary: Color(0xFF0B1220),
    secondary: Color(0xFF34D399), // emerald-400 (upload/success accent)
    onSecondary: Color(0xFF06281E),
    error: Color(0xFFF87171), // red-400
    onError: Color(0xFF2E0A0A),
    surface: Color(0xFF09090B), // zinc-950
    onSurface: Color(0xFFF4F4F5), // zinc-100
    onSurfaceVariant: Color(0xFF71717A), // zinc-500
    outline: Color(0xFF52525B), // zinc-600
    outlineVariant: Color(0xFF27272A), // zinc-800
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF0F0F11),
    surfaceContainer: Color(0xFF18181B), // zinc-900
    surfaceContainerHigh: Color(0xFF212125),
    surfaceContainerHighest: Color(0xFF27272A), // zinc-800
  );

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

  /// Maps a resolved Material [ColorScheme] onto shadcn_ui's role naming, so
  /// Shad* widgets pick up the same dynamic-color/AMOLED/seed inputs as the
  /// Material side instead of a fixed [ShadZincColorScheme] (PR-63).
  static ShadColorScheme shadColorSchemeFrom(ColorScheme scheme) {
    return ShadColorScheme(
      background: scheme.surface,
      foreground: scheme.onSurface,
      card: scheme.surfaceContainerLow,
      cardForeground: scheme.onSurface,
      popover: scheme.surfaceContainerHigh,
      popoverForeground: scheme.onSurface,
      primary: scheme.primary,
      primaryForeground: scheme.onPrimary,
      secondary: scheme.secondaryContainer,
      secondaryForeground: scheme.onSecondaryContainer,
      muted: scheme.surfaceContainerHighest,
      mutedForeground: scheme.onSurfaceVariant,
      accent: scheme.tertiaryContainer,
      accentForeground: scheme.onTertiaryContainer,
      destructive: scheme.error,
      destructiveForeground: scheme.onError,
      border: scheme.outlineVariant,
      input: scheme.outlineVariant,
      ring: scheme.primary,
      selection: scheme.primary.withValues(alpha: 0.2),
    );
  }

  static ThemeData toAmoled(ThemeData dark) {
    final scheme = dark.colorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: const Color(0xFF18181B), // zinc-900
      surfaceContainerHighest: const Color(0xFF27272A), // zinc-800
    );
    return dark.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: dark.appBarTheme.copyWith(backgroundColor: Colors.black),
    );
  }

  static ThemeData _build(
    Brightness brightness, [
    ColorScheme? override,
    Color? seed,
  ]) {
    // The app's own default dark theme (no platform dynamic scheme, no
    // custom accent-picker seed) is the hand-picked Figma scheme rather than
    // a seed derivation — everywhere else (a custom seed, or an injected
    // platform scheme) is untouched.
    final scheme =
        override ??
        (brightness == Brightness.dark && seed == null
            ? _figmaDark
            : ColorScheme.fromSeed(
              seedColor: seed ?? Brand.seed,
              brightness: brightness,
              secondary: Brand.accent,
            ));

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
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardR,
          side: BorderSide(color: scheme.outlineVariant),
        ),
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
          elevation: 2,
          shadowColor: scheme.primary.withValues(alpha: 0.45),
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
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        secondarySelectedColor: scheme.primary.withValues(alpha: 0.18),
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
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: Spacing.md,
        thickness: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
        },
      ),
    );
  }
}
