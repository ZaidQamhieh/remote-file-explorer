import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The mockup's `.chip.active`: pill, filled `--primary`, white text/icon —
/// used here as a static (non-tappable) indicator that the query is a
/// glob/regex pattern.
class GlobIndicator extends StatelessWidget {
  const GlobIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Brand.seed,
            borderRadius: Radii.stadiumR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.regex, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                context.l10n.globPattern,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
