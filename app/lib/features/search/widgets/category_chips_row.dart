import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../search_types.dart';

class CategoryChipsRow extends StatelessWidget {
  const CategoryChipsRow({super.key, required this.selected, required this.onToggle});

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
          return FilterChip(
            label: Text(category.localizedLabel(context)),
            avatar: Icon(category.icon, size: 18),
            selected: isSelected,
            onSelected: (value) => onToggle(category, value),
          );
        },
      ),
    );
  }
}
