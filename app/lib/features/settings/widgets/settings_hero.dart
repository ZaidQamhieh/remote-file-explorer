import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    return ShadCard(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md3,
        Spacing.lg,
        Spacing.md3,
        Spacing.lg - 2,
      ),
      radius: Radii.lgR,
      backgroundColor: scheme.surfaceContainerHigh,
      border: ShadBorder.all(color: tint.withValues(alpha: 0.35)),
      // The icon badge's boxShadow bleeds slightly past its own corners —
      // keep the old Container's default no-clip behavior instead of
      // ShadCard's antiAlias default so it isn't cut off.
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
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
            child: Icon(icon, size: 28, color: tint),
          ),
          const SizedBox(width: Spacing.md3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
