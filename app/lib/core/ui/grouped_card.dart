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

/// Figma's recurring visual unit: a rounded card containing divided rows.
/// Shared by Settings ([SettingsSection]), Servers (host list), Files
/// (explorer list), and Transfers (grouped transfer list) so they all wrap
/// their existing rows in the same container instead of each inventing one.
class GroupedCard extends StatelessWidget {
  const GroupedCard({super.key, required this.children, this.padded = true});

  final List<Widget> children;

  /// Whether the card content gets the standard padding. Rows that manage
  /// their own internal padding can opt out.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: Elevations.card,
      color: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardR),
      clipBehavior: Clip.antiAlias,
      child:
          padded
              ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Column(children: children),
              )
              : Column(children: children),
    );
  }
}
