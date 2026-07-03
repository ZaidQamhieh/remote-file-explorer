import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class GlobIndicator extends StatelessWidget {
  const GlobIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: const Icon(LucideIcons.regex, size: 18),
          label: Text(context.l10n.globPattern),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
