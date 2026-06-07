import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import 'transfer_state.dart';

/// Bottom sheet listing all active, queued, and recently completed transfers.
class TransferManagerSheet extends ConsumerWidget {
  const TransferManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transferQueueProvider);

    final active = transfers
        .where((t) =>
            t.status == TransferStatus.running ||
            t.status == TransferStatus.queued ||
            t.status == TransferStatus.paused)
        .toList();
    final done = transfers
        .where((t) =>
            t.status == TransferStatus.completed ||
            t.status == TransferStatus.failed)
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, controller) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: Radii.sheetTopR,
        ),
        child: ClipRRect(
          borderRadius: Radii.sheetTopR,
          child: Column(
            children: [
              _buildHandle(context),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Row(
                  children: [
                    Text('Transfers',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (done.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          for (final t in done) {
                            ref
                                .read(transferQueueProvider.notifier)
                                .remove(t.id);
                          }
                        },
                        child: const Text('Clear done'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: transfers.isEmpty
                    ? const Center(child: Text('No transfers'))
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        children: [
                          if (active.isNotEmpty) ...[
                            _SectionHeader(
                              label: 'Active',
                              count: active.length,
                            ),
                            for (final t in active) _TransferTile(task: t),
                          ],
                          if (done.isNotEmpty) ...[
                            _SectionHeader(
                              label: 'Completed',
                              count: done.length,
                            ),
                            for (final t in done) _TransferTile(task: t),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header — groups active vs. completed transfers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: Radii.chipR,
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer tile
// ---------------------------------------------------------------------------

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferQueueProvider.notifier);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      leading: _statusIcon(context),
      title: Text(
        task.displayName,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: _buildSubtitle(context),
      trailing: _buildActions(context, notifier),
    );
  }

  Widget _statusIcon(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (task.status) {
      case TransferStatus.running:
        return SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            value: task.progress > 0 ? task.progress : null,
            strokeWidth: 3,
          ),
        );
      case TransferStatus.completed:
        return const Icon(Icons.check_circle, color: Brand.online);
      case TransferStatus.failed:
        return Icon(Icons.error_outline, color: scheme.error);
      case TransferStatus.paused:
        return Icon(Icons.pause_circle_outline, color: scheme.tertiary);
      case TransferStatus.queued:
        return Icon(Icons.schedule, color: scheme.outline);
    }
  }

  Widget? _buildSubtitle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (task.status) {
      case TransferStatus.running:
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.chip / 2),
                child: LinearProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${_fmt(task.transferredBytes)} / ${_fmt(task.totalBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      case TransferStatus.failed:
        return Text(
          task.error ?? 'Unknown error',
          style: TextStyle(color: scheme.error),
          overflow: TextOverflow.ellipsis,
        );
      case TransferStatus.completed:
        final label = task.kind == TransferKind.upload
            ? 'Uploaded'
            : (task.savedLocation != null
                ? 'Saved to ${task.savedLocation}'
                : 'Downloaded');
        return Text(
          label,
          style: const TextStyle(color: Brand.online),
          overflow: TextOverflow.ellipsis,
        );
      default:
        return Text(task.status.name);
    }
  }

  Widget? _buildActions(BuildContext context, TransferQueueNotifier notifier) {
    switch (task.status) {
      case TransferStatus.running:
        return IconButton(
          icon: const Icon(Icons.pause),
          onPressed: () => notifier.pause(task.id),
        );
      case TransferStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () => notifier.retry(task.id),
        );
      case TransferStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => notifier.retry(task.id),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => notifier.remove(task.id),
            ),
          ],
        );
      case TransferStatus.completed:
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => notifier.remove(task.id),
        );
      default:
        return null;
    }
  }
}

String _fmt(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
