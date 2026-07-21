import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/storage/recent_searches.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';
import 'centered_message.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class RecentSearchesView extends ConsumerWidget {
  const RecentSearchesView({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider).valueOrNull ?? const [];

    if (recent.isEmpty) {
      return CenteredMessage(
        icon: LucideIcons.search,
        message: context.l10n.typeToSearch,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.sm,
            Spacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.recentSearches,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.09,
                  ),
                ),
              ),
              Pressable(
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  child: Text(
                    context.l10n.clearAllButton,
                    style: TextStyle(fontSize: 12.5, color: scheme.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final query in recent)
          Pressable(
            onTap: () => onSelect(query),
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 11,
                horizontal: Spacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: Radii.smR,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.history,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      query,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap:
                        () => ref
                            .read(recentSearchesProvider.notifier)
                            .remove(query),
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.xs),
                      child: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
