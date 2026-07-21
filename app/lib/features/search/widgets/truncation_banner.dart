import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TruncationBanner extends StatelessWidget {
  const TruncationBanner({
    super.key,
    required this.truncated,
    required this.timeBudgetHit,
    required this.limit,
    this.message,
  });

  final bool truncated;
  final bool timeBudgetHit;
  final int limit;

  /// Overrides the default truncated/timed-out wording — for callers whose
  /// context isn't a search (e.g. Recents).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedMessage =
        message ??
        (truncated
            ? context.l10n.showingFirstNResults(limit)
            : context.l10n.searchTimedOut);
    return Container(
      color: Brand.amber.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 16, color: Brand.amber),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              resolvedMessage,
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
