import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The mockup's `.iconbtn` (34x34, 19px svg) — filter/tune icon in the
/// search app bar. [activeCount] shows a small dot badge when filters are
/// applied; the mockup itself has no badge on this button, but the app has
/// real active-filter state to surface, so a minimal literal-`.badge`-style
/// dot is added rather than inventing a fake mockup element.
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
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onPressed,
      child: Semantics(
        button: true,
        label: context.l10n.searchFiltersTooltip,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  LucideIcons.slidersHorizontal,
                  size: 19,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (activeCount > 0)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    decoration: BoxDecoration(
                      color: Brand.seed,
                      borderRadius: Radii.stadiumR,
                    ),
                    child: Text(
                      '$activeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
