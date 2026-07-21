import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';
import '../search_types.dart';

class CategoryChipsRow extends StatelessWidget {
  const CategoryChipsRow({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<SearchCategory> selected;
  final void Function(SearchCategory category, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        itemCount: SearchCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: Spacing.xs),
        itemBuilder: (context, i) {
          final category = SearchCategory.values[i];
          final isSelected = selected.contains(category);
          final color = _categoryColor(category);
          return _CategoryChip(
            label: category.localizedLabel(context),
            icon: category.icon,
            color: color,
            selected: isSelected,
            onTap: () => onToggle(category, !isSelected),
          );
        },
      ),
    );
  }
}

/// The mockup's `.chip`: pill, 1px border, 12px text. `.chip.active` fills
/// with a solid colour and white text/icon — here that colour is the
/// category's own tint (see `_categoryColor`) rather than always
/// `--primary`, so a selected chip and its matching result rows read as the
/// same colour (`search_result_tile.dart`'s `resultIcon`).
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fillColor = color ?? Brand.seed;
    final iconColor =
        selected ? Colors.white : (color ?? scheme.onSurfaceVariant);
    final textColor = selected ? Colors.white : scheme.onSurfaceVariant;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? fillColor : Colors.transparent,
          borderRadius: Radii.stadiumR,
          border:
              selected
                  ? null
                  : Border.all(color: scheme.outlineVariant, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: textColor)),
          ],
        ),
      ),
    );
  }
}

/// Per-category tint for the filter chips, matching the mockup's colored
/// result-type badges. Reuses the same 5 [Brand] accents as
/// `search_result_tile.dart`'s `resultIcon` so a category and its results
/// read as the same color. `other` stays untinted — it has no single
/// matching accent.
Color? _categoryColor(SearchCategory category) => switch (category) {
  SearchCategory.folder => Brand.amber,
  SearchCategory.image => Brand.seed,
  SearchCategory.video => Brand.accent,
  SearchCategory.audio => Brand.online,
  SearchCategory.document => Brand.red,
  SearchCategory.archive => Brand.amber,
  SearchCategory.other => null,
};
