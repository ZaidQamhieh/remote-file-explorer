import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// A grouped section: a labelled header followed by a card containing related
/// rows. Keeps visual rhythm consistent across the settings surfaces (host
/// settings and the global App Settings screen) and, with [icon] omitted, is
/// also the shared "grouped card" wrapper used for list-style sections
/// elsewhere (e.g. Servers' Active/Offline groups, Transfers' Active/History)
/// to match the Figma design's uppercase-label-over-rounded-card pattern.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.icon,
    required this.children,
    this.trailing,
    this.padded = true,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;
  final Widget? trailing;

  /// Whether the card content gets the standard padding. Widgets that manage
  /// their own internal padding (e.g. UpdateTile) opt out.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.xs,
            0,
            Spacing.xs,
            Spacing.sm,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: Spacing.sm),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ] else
                Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child:
              padded
                  ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    child: Column(children: children),
                  )
                  : Column(children: children),
        ),
      ],
    );
  }
}
