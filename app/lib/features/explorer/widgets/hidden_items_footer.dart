import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HiddenItemsFooter extends StatelessWidget {
  const HiddenItemsFooter({
    super.key,
    required this.count,
    required this.revealed,
    required this.onToggle,
    this.compact = false,
  });

  final int count;
  final bool revealed;
  final VoidCallback onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = context.l10n.nHidden(count);
    final action = revealed ? context.l10n.hideLabel : context.l10n.showLabel;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final actionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );

    if (compact) {
      return Center(
        child: InkWell(
          borderRadius: Radii.smR,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  revealed ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: Spacing.xs),
                Text(label, style: style, textAlign: TextAlign.center),
                Text(action, style: actionStyle, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              revealed ? LucideIcons.eyeOff : LucideIcons.eye,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Spacing.sm),
            Text('$label · ', style: style),
            Text(action, style: actionStyle),
          ],
        ),
      ),
    );
  }
}
