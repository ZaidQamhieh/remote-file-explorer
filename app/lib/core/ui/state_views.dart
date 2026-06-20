import 'package:flutter/material.dart';

import '../l10n_ext.dart';

/// Friendly empty-directory placeholder.
class EmptyFolderView extends StatelessWidget {
  const EmptyFolderView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: c.outline),
          const SizedBox(height: 12),
          Text(
            context.l10n.emptyFolderMessage,
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
            Icon(Icons.error_outline, size: 56, color: c.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
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
            Icon(Icons.cloud_off, size: 16, color: c.onTertiaryContainer),
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
