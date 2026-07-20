import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
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
          return FilterChip(
            label: Text(category.localizedLabel(context)),
            avatar: Icon(category.icon, size: 18, color: color),
            selected: isSelected,
            selectedColor: color?.withValues(alpha: 0.18),
            checkmarkColor: color,
            onSelected: (value) => onToggle(category, value),
          );
        },
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
