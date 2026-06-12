import 'package:flutter/material.dart';

/// Design tokens for the app's "distinctive modern" look. Centralising these as
/// named constants keeps spacing, radii, and brand colours consistent across
/// every screen instead of scattered magic numbers.

/// Brand seed colours. Light and dark schemes are both derived from [seed];
/// [accent] is wired in as the scheme's secondary for actions/highlights.
class Brand {
  Brand._();

  /// Indigo — primary brand colour.
  static const Color seed = Color(0xFF4F5BD5);

  /// Cyan — accent used for secondary actions and highlights.
  static const Color accent = Color(0xFF00B4D8);

  /// Stable status colours (used directly, not from the scheme, so "online" and
  /// "error" read the same in light and dark).
  static const Color online = Color(0xFF2E9E5B);
  static const Color offline = Color(0xFF9AA0A6);
}

/// Spacing scale (logical pixels). Use these for padding, gaps, and margins.
///
/// Values: 4 / 8 / 16 / 24 / 32. [md2] (12) fills the gap between [sm] and
/// [md] for callers that need a slightly tighter "medium" spacing.
class Spacing {
  Spacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md2 = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Corner radii.
///
/// Values: 12 / 16 / 24 / 28, plus a fully-round "stadium" radius for
/// pill-shaped chips/buttons.
class Radii {
  Radii._();

  static const double chip = 10;
  static const double sm = 12;
  static const double card = 16;
  static const double lg = 24;
  static const double sheet = 28;

  /// Large, effectively-infinite radius for stadium/pill shapes (e.g.
  /// fully-rounded buttons or tags).
  static const double stadium = 999;

  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius lgR = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheetTopR = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius stadiumR =
      BorderRadius.all(Radius.circular(stadium));
}

/// Elevation values for tonal surfaces.
class Elevations {
  Elevations._();

  static const double card = 1;
  static const double raised = 3;
}

/// Surface role helpers — semantic names for [ColorScheme] surface tones used
/// across cards, sheets, and containers, so call sites read by role rather
/// than by raw scheme member name.
class SurfaceRoles {
  SurfaceRoles._();

  /// Base content surface (e.g. grid cells, list rows).
  static Color base(ColorScheme scheme) => scheme.surfaceContainerLow;

  /// Slightly raised surface (e.g. sheets, the multi-select bar).
  static Color raised(ColorScheme scheme) => scheme.surfaceContainerHigh;

  /// Tonal container behind icons/thumbnails.
  static Color iconContainer(ColorScheme scheme) =>
      scheme.surfaceContainerHighest;
}

/// Animation duration tokens (logical durations for transitions, expansions,
/// and state changes outside of the bespoke curves in `motion.dart`).
///
/// Values: 150 / 250 / 350 ms — short / medium / long. Named `MotionDuration`
/// (not `Durations`) to avoid clashing with Flutter's own `Durations` class
/// (`package:flutter/src/material/motion.dart`).
class MotionDuration {
  MotionDuration._();

  static const Duration short = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration long = Duration(milliseconds: 350);
}
