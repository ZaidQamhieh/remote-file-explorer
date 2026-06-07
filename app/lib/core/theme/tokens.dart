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
class Spacing {
  Spacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Corner radii.
class Radii {
  Radii._();

  static const double chip = 10;
  static const double card = 16;
  static const double sheet = 28;

  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetTopR = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// Elevation values for tonal surfaces.
class Elevations {
  Elevations._();

  static const double card = 1;
  static const double raised = 3;
}
