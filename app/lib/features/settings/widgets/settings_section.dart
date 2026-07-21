import 'package:flutter/material.dart';

import '../../../core/ui/grouped_card.dart';

/// A labelled section: the shared [SectionLabel] header followed by a
/// [GroupedCard] containing related rows, with a flush hairline divider
/// between rows matching the mockup's `.row{border-bottom:1px solid
/// var(--border)}` (not indented past the leading icon — that was a Figma-era
/// invention).
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.padded = true,
  });

  final String title;
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
        SectionLabel(title, trailing: trailing),
        GroupedCard(padded: padded, children: _divided(children, scheme)),
      ],
    );
  }
}

List<Widget> _divided(List<Widget> children, ColorScheme scheme) {
  if (children.length < 2) return children;
  return [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
      children[i],
    ],
  ];
}
