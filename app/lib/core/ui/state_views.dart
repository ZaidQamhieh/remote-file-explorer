import 'package:flutter/material.dart';

import '../l10n_ext.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Which empty-state message an entry list should show.
enum EmptyStateKind {
  /// The directory itself has no entries.
  emptyFolder,

  /// The directory has entries, but the current filter (bookmark tag /
  /// hidden-items visibility) hides all of them.
  noMatches,
}

/// Picks the empty-state case for an entry list: a genuinely empty folder vs.
/// one where a filter is hiding every entry. Pure so the selection logic is
/// unit-testable without a widget tree.
EmptyStateKind resolveEmptyState({required bool hasRawEntries}) =>
    hasRawEntries ? EmptyStateKind.noMatches : EmptyStateKind.emptyFolder;

/// Friendly empty-directory placeholder. Pass [kind] to distinguish a truly
/// empty folder from one where the current filter matches nothing.
class EmptyFolderView extends StatelessWidget {
  const EmptyFolderView({super.key, this.kind = EmptyStateKind.emptyFolder});

  final EmptyStateKind kind;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final noMatches = kind == EmptyStateKind.noMatches;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            noMatches ? LucideIcons.filterX : LucideIcons.folderOpen,
            size: 64,
            color: c.outline,
          ),
          const SizedBox(height: 12),
          Text(
            noMatches
                ? context.l10n.noMatchesMessage
                : context.l10n.emptyFolderMessage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Error card with a retry action.
class ErrorRetryCard extends StatelessWidget {
  const ErrorRetryCard({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert, size: 56, color: c.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw),
              label: Text(context.l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin banner shown when the explorer is displaying cached data while offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(LucideIcons.cloudOff, size: 16, color: c.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.offlineBannerText,
                style: TextStyle(color: c.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer-free lightweight skeleton list shown during first load.
class ListingSkeleton extends StatelessWidget {
  const ListingSkeleton({super.key, this.rows = 8});
  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget bar(double w) => Container(
      height: 12,
      width: w,
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return ListView.builder(
      itemCount: rows,
      itemBuilder:
          (_, __) => ListTile(
            leading: CircleAvatar(backgroundColor: c.surfaceContainerHighest),
            title: bar(160),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: bar(90),
            ),
          ),
    );
  }
}
