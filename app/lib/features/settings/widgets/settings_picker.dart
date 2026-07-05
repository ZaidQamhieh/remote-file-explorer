import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// One selectable option in a [showSettingsPicker] sheet. Provide [icon] for a
/// leading glyph, or [color] for a leading colour dot (accent-colour picker).
class SettingsOption<T> {
  const SettingsOption(this.value, this.label, {this.icon, this.color});
  final T value;
  final String label;
  final IconData? icon;
  final Color? color;
}

/// A single-choice M3 bottom sheet: grabber, title, one radio row per option.
/// Resolves to the tapped option's value, or null if dismissed.
Future<T?> showSettingsPicker<T>(
  BuildContext context, {
  required String title,
  required List<SettingsOption<T>> options,
  required T selected,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: Text(title,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final o in options)
              InkWell(
                onTap: () => Navigator.of(sheetContext).pop(o.value),
                child: Container(
                  color: o.value == selected
                      ? scheme.primary.withValues(alpha: 0.12)
                      : null,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg, vertical: Spacing.md),
                  child: Row(
                    children: [
                      if (o.color != null)
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color: o.color, shape: BoxShape.circle),
                        )
                      else if (o.icon != null)
                        Icon(o.icon,
                            size: 22,
                            color: o.value == selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Text(
                          o.label,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color:
                                    o.value == selected ? scheme.primary : null,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                      if (o.value == selected)
                        Icon(Icons.check, size: 22, color: scheme.primary)
                      else
                        const SizedBox(width: 22),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Spacing.sm),
          ],
        ),
      );
    },
  );
}
