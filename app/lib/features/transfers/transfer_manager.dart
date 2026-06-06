import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transfer_state.dart';

/// Bottom sheet listing all active, queued, and recently completed transfers.
class TransferManagerSheet extends ConsumerWidget {
  const TransferManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transferQueueProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          _buildHandle(context),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Transfers',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (transfers.any((t) =>
                    t.status == TransferStatus.completed ||
                    t.status == TransferStatus.failed))
                  TextButton(
                    onPressed: () {
                      for (final t in transfers
                          .where((t) =>
                              t.status == TransferStatus.completed ||
                              t.status == TransferStatus.failed)
                          .toList()) {
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
                : ListView.builder(
                    controller: controller,
                    itemCount: transfers.length,
                    itemBuilder: (ctx, i) =>
                        _TransferTile(task: transfers[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
// Transfer tile
// ---------------------------------------------------------------------------

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferQueueProvider.notifier);

    return ListTile(
      leading: _statusIcon(context),
      title: Text(task.displayName, overflow: TextOverflow.ellipsis),
      subtitle: _buildSubtitle(context),
      trailing: _buildActions(context, notifier),
    );
  }

  Widget _statusIcon(BuildContext context) {
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
        return const Icon(Icons.check_circle, color: Colors.green);
      case TransferStatus.failed:
        return Icon(Icons.error_outline,
            color: Theme.of(context).colorScheme.error);
      case TransferStatus.paused:
        return const Icon(Icons.pause_circle_outline, color: Colors.orange);
      case TransferStatus.queued:
        return const Icon(Icons.schedule, color: Colors.grey);
    }
  }

  Widget? _buildSubtitle(BuildContext context) {
    switch (task.status) {
      case TransferStatus.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: task.progress > 0 ? task.progress : null),
            const SizedBox(height: 2),
            Text(
              '${_fmt(task.transferredBytes)} / ${_fmt(task.totalBytes)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case TransferStatus.failed:
        return Text(
          task.error ?? 'Unknown error',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          overflow: TextOverflow.ellipsis,
        );
      case TransferStatus.completed:
        return Text(
          task.kind == TransferKind.upload ? 'Uploaded' : 'Downloaded',
          style: const TextStyle(color: Colors.green),
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
