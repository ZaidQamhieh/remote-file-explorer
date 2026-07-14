import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Flat-card hero banner topping a Settings category sub-screen: a category-
/// tinted icon badge, title, and subtitle, replacing the bare AppBar title
/// (Settings redesign v2). Unlike [SheetHero] this is flat — no radial-
/// gradient glow, no grabber, no close button — a full page doesn't need a
/// sheet's dismiss affordance.
class SettingsHero extends StatelessWidget {
  const SettingsHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md3,
        Spacing.md,
        Spacing.md3 - 2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.lgR,
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.22),
              borderRadius: Radii.cardR,
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 24, color: tint),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
