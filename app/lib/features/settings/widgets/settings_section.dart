import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
            Spacing.md2,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: scheme.primary),
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
        ShadCard(
          padding: EdgeInsets.zero,
          radius: Radii.cardR,
          // surfaceContainerLow + a black shadow are both nearly identical to
          // the near-black page background on this theme — invisible instead
          // of "elevated". surfaceContainerHigh + a fully-opaque border is
          // the same recipe the host-card hero already uses successfully.
          backgroundColor: scheme.surfaceContainerHigh,
          // scheme.outlineVariant (zinc-800, 0x27272A) at 1px reads as
          // basically invisible next to a near-black background — use the
          // lighter scheme.outline (zinc-600) at 1.5px so the card edge is
          // actually perceptible, not just technically non-zero.
          border: ShadBorder.all(color: scheme.outline, width: 1.5),
          clipBehavior: Clip.antiAlias,
          // ShadCard paints its background on a plain DecoratedBox, not a
          // Material ancestor — without this, rows nested inside (ListTile,
          // InkWell) lose ink splashes and Flutter throws in debug/test.
          child: Material(
            type: MaterialType.transparency,
            child:
                padded
                    ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      child: Column(children: _divided(children, scheme, 56)),
                    )
                    : Column(children: _divided(children, scheme, 62)),
          ),
        ),
      ],
    );
  }
}

/// Interleaves a hairline divider between rows, indented past the leading
/// icon badge so it only underlines the text — matches [ActionListCard]'s
/// row separation instead of leaving stacked toggles/rows visually fused.
List<Widget> _divided(
  List<Widget> children,
  ColorScheme scheme,
  double indent,
) {
  if (children.length < 2) return children;
  return [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0)
        Divider(
          height: 1,
          indent: indent,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      children[i],
    ],
  ];
}
