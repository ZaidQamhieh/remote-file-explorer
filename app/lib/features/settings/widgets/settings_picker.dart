import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/sheet_chrome.dart';

/// One selectable option in a [showSettingsPicker] sheet. Provide [icon] for a
/// leading glyph, or [color] for a leading colour dot (accent-colour picker).
class SettingsOption<T> {
  const SettingsOption(this.value, this.label, {this.icon, this.color});
  final T value;
  final String label;
  final IconData? icon;
  final Color? color;
}

/// A single-choice M3 bottom sheet: [SheetHero] header + one row per option
/// in an [ActionListCard], selected option marked with a trailing checkmark.
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
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: Radii.sheetTopR,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetHero(
                  badge: const Icon(LucideIcons.slidersHorizontal),
                  title: title,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.xl,
                  ),
                  child: ActionListCard(
                    children: [
                      for (final o in options)
                        _optionTile(
                          sheetContext,
                          scheme,
                          o,
                          o.value == selected,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// One option row. Options with an [SettingsOption.icon] render as an
/// [ActionListTile]; the accent-colour picker's swatch options (no icon, a
/// [SettingsOption.color] instead) and plain text-only options (density,
/// sort field) fall back to a bare [ListTile] since [ActionListTile] always
/// wants a leading icon.
Widget _optionTile<T>(
  BuildContext sheetContext,
  ColorScheme scheme,
  SettingsOption<T> o,
  bool isSelected,
) {
  final check =
      isSelected
          ? Icon(LucideIcons.check, size: 20, color: scheme.primary)
          : const SizedBox(width: 20);
  if (o.icon != null) {
    return ActionListTile(
      icon: o.icon!,
      label: o.label,
      tint: isSelected ? scheme.primary : null,
      trailing: check,
      onTap: () => Navigator.of(sheetContext).pop(o.value),
    );
  }
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
    visualDensity: VisualDensity.compact,
    leading:
        o.color == null
            ? null
            : Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: o.color, shape: BoxShape.circle),
            ),
    title: Text(
      o.label,
      style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
        color: isSelected ? scheme.primary : null,
        fontWeight: FontWeight.w500,
      ),
    ),
    trailing: check,
    onTap: () => Navigator.of(sheetContext).pop(o.value),
  );
}
