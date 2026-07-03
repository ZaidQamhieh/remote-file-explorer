import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/storage/recent_searches.dart';
import '../../../core/theme/tokens.dart';
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
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton(
                onPressed:
                    () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(context.l10n.clearAllButton),
              ),
            ],
          ),
        ),
        for (final query in recent)
          ListTile(
            leading: const Icon(LucideIcons.history),
            title: Text(query),
            trailing: IconButton(
              icon: const Icon(LucideIcons.x, size: 18),
              tooltip: context.l10n.removeTooltip,
              onPressed:
                  () => ref.read(recentSearchesProvider.notifier).remove(query),
            ),
            onTap: () => onSelect(query),
          ),
      ],
    );
  }
}
