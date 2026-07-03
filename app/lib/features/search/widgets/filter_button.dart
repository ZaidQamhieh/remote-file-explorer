import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(LucideIcons.slidersHorizontal);
    return IconButton(
      tooltip: context.l10n.searchFiltersTooltip,
      onPressed: onPressed,
      icon:
          activeCount > 0
              ? Badge(label: Text('$activeCount'), child: icon)
              : icon,
    );
  }
}
