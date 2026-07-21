import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The mockup's `.section-label`: 10.5px/700, uppercase, `.09em` tracking,
/// faint colour. Shared so every list section (Devices, Files, Transfers,
/// Settings) uses one consistent label style instead of each screen
/// inventing its own.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.xs, 0, Spacing.xs, Spacing.sm),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.945,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The mockup's `.card`: flat `surface` background, 1px `border`, `r-lg`
/// radius, 14px padding — no `Card`/elevation. Shared by Settings, Devices,
/// Files, and Transfers so they all wrap their rows in the same container
/// instead of each inventing one.
class GroupedCard extends StatelessWidget {
  const GroupedCard({super.key, required this.children, this.padded = true});

  final List<Widget> children;

  /// Whether the card content gets the standard padding. Rows that manage
  /// their own internal padding can opt out.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padded ? const EdgeInsets.all(14) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: scheme.outlineVariant),
      ),
      // Not every row inside here has been rebuilt off Material widgets yet
      // (ListTile/InkWell mid zero-reuse migration elsewhere in the app) —
      // this transparent Material ancestor keeps their splashes/backgrounds
      // working without painting anything of its own.
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}
