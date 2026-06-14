import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import 'transfer_speed.dart';
import 'transfer_state.dart';

/// Bottom sheet listing all transfers, grouped into collapsible
/// Active / Queued / Done / Failed sections with live per-task speed + ETA,
/// swipe-to-pause/resume and swipe-to-remove (with undo), and inline retry on
/// failures.
///
/// All engine interaction goes through [TransferQueueNotifier]; this screen is
/// pure presentation plus the read-only [transferSamplerProvider] for speed.
class TransferManagerSheet extends ConsumerWidget {
  const TransferManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transferQueueProvider);

    final groups = groupTransfers(transfers);
    final doneAndFailed = [
      ...groups[TransferGroup.done]!,
      ...groups[TransferGroup.failed]!,
    ];

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
                    if (doneAndFailed.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.clear_all_rounded, size: 18),
                        label: const Text('Clear completed'),
                        onPressed: () {
                          for (final t in doneAndFailed) {
                            ref
                                .read(transferQueueProvider.notifier)
                                .remove(t.id);
                          }
                        },
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
                          for (final group in TransferGroup.values)
                            if (groups[group]!.isNotEmpty)
                              _TransferSection(
                                group: group,
                                tasks: groups[group]!,
                              ),
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
// Grouping
// ---------------------------------------------------------------------------

/// The collapsible buckets the manager presents.
///
/// Note paused tasks fold into [active] (they're in-progress work the user can
/// resume), shown with a paused indicator — keeping the section list short.
enum TransferGroup { active, queued, done, failed }

extension TransferGroupLabel on TransferGroup {
  String get label => switch (this) {
        TransferGroup.active => 'Active',
        TransferGroup.queued => 'Queued',
        TransferGroup.done => 'Done',
        TransferGroup.failed => 'Failed',
      };
}

/// Buckets [tasks] into the four manager groups by [TransferStatus]:
/// running + paused → active, queued → queued, completed → done,
/// failed → failed. Always returns an entry for every group (possibly empty),
/// preserving input order within each bucket.
Map<TransferGroup, List<TransferTask>> groupTransfers(
    List<TransferTask> tasks) {
  final out = {for (final g in TransferGroup.values) g: <TransferTask>[]};
  for (final t in tasks) {
    final group = switch (t.status) {
      TransferStatus.running || TransferStatus.paused => TransferGroup.active,
      TransferStatus.queued => TransferGroup.queued,
      TransferStatus.completed => TransferGroup.done,
      TransferStatus.failed => TransferGroup.failed,
    };
    out[group]!.add(t);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Section (collapsible) — header + its tiles
// ---------------------------------------------------------------------------

class _TransferSection extends StatefulWidget {
  const _TransferSection({required this.group, required this.tasks});

  final TransferGroup group;
  final List<TransferTask> tasks;

  @override
  State<_TransferSection> createState() => _TransferSectionState();
}

class _TransferSectionState extends State<_TransferSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: widget.group.label,
          count: widget.tasks.length,
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final t in widget.tasks) _TransferTile(task: t),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Spacing.xs),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm, vertical: 1),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer tile — swipeable, with live speed/ETA and inline retry
// ---------------------------------------------------------------------------

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.task});
  final TransferTask task;

  /// Whether this task can be paused/resumed (i.e. it's active or queued).
  bool get _canPauseResume =>
      task.status == TransferStatus.running ||
      task.status == TransferStatus.queued ||
      task.status == TransferStatus.paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferQueueProvider.notifier);

    final tile = ListTile(
      key: ValueKey('tile-${task.id}'),
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
      subtitle: _buildSubtitle(context, ref, notifier),
      trailing: _buildActions(context, notifier),
    );

    return Dismissible(
      key: ValueKey('dismiss-${task.id}'),
      // Swipe-left (endToStart) = pause/resume; swipe-right (startToEnd) =
      // remove. Pause/resume is a non-dismissing action (we veto the dismissal
      // and toggle), remove actually dismisses and offers undo.
      direction: _canPauseResume
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      background: _swipeBackground(context, removing: true),
      secondaryBackground: _canPauseResume
          ? _swipeBackground(context, removing: false)
          : null,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Pause/resume toggle — never actually dismiss the row.
          _togglePauseResume(notifier);
          return false;
        }
        // startToEnd → remove with undo.
        _removeWithUndo(context, ref);
        return true;
      },
      child: tile,
    );
  }

  void _togglePauseResume(TransferQueueNotifier notifier) {
    if (task.status == TransferStatus.paused) {
      notifier.retry(task.id);
    } else {
      notifier.pause(task.id);
    }
  }

  void _removeWithUndo(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferQueueProvider.notifier);
    // Capture the task before removal so Undo can re-enqueue an equivalent one.
    final removed = task;
    notifier.remove(removed.id);
    showSuccess(
      context,
      'Removed ${removed.displayName}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => notifier.enqueue(reenqueuableCopy(removed)),
      ),
    );
  }

  Widget _swipeBackground(BuildContext context, {required bool removing}) {
    final scheme = Theme.of(context).colorScheme;
    final color = removing ? scheme.errorContainer : scheme.tertiaryContainer;
    final onColor =
        removing ? scheme.onErrorContainer : scheme.onTertiaryContainer;
    final icon = removing
        ? Icons.delete_outline_rounded
        : (task.status == TransferStatus.paused
            ? Icons.play_arrow_rounded
            : Icons.pause_rounded);
    return Container(
      color: color,
      alignment: removing ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Icon(icon, color: onColor),
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

  Widget? _buildSubtitle(
      BuildContext context, WidgetRef ref, TransferQueueNotifier notifier) {
    final scheme = Theme.of(context).colorScheme;
    switch (task.status) {
      case TransferStatus.running:
      case TransferStatus.paused:
        final paused = task.status == TransferStatus.paused;
        // Live speed/ETA from the read-only sampler (running tasks only).
        final eta = paused
            ? null
            : ref.watch(transferSamplerProvider)[task.id];
        final meta = <String>[
          '${formatSize(task.transferredBytes)} / ${formatSize(task.totalBytes)}',
          if (paused) 'Paused',
          if (eta?.speedLabel != null) eta!.speedLabel!,
          if (eta?.etaLabel != null) eta!.etaLabel!,
        ].join(' · ');
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
              Text(meta, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      case TransferStatus.failed:
        // Inline error text with a Retry button (button lives in trailing).
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            task.error ?? 'Unknown error',
            style: TextStyle(color: scheme.error),
          ),
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
      case TransferStatus.queued:
        return const Text('Queued');
    }
  }

  Widget? _buildActions(BuildContext context, TransferQueueNotifier notifier) {
    switch (task.status) {
      case TransferStatus.running:
        return IconButton(
          icon: const Icon(Icons.pause),
          tooltip: 'Pause',
          onPressed: () => notifier.pause(task.id),
        );
      case TransferStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          tooltip: 'Resume',
          onPressed: () => notifier.retry(task.id),
        );
      case TransferStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
              onPressed: () => notifier.retry(task.id),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
              onPressed: () => notifier.remove(task.id),
            ),
          ],
        );
      case TransferStatus.completed:
        return IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Remove',
          onPressed: () => notifier.remove(task.id),
        );
      case TransferStatus.queued:
        return IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Remove',
          onPressed: () => notifier.remove(task.id),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Re-enqueue helper (undo)
// ---------------------------------------------------------------------------

/// Builds a fresh [TransferTask] equivalent to [task] so a removed transfer can
/// be re-queued by the Undo action.
///
/// The engine's task factories mint a new id and reset progress/status to a
/// clean `queued` state, which is exactly what re-enqueueing needs — a removed
/// task restarts rather than trying to resume an id the queue no longer holds.
TransferTask reenqueuableCopy(TransferTask task) {
  return switch (task.kind) {
    TransferKind.upload => TransferTask.upload(
        localPath: task.localPath,
        remotePath: task.remotePath,
        host: task.host,
        overwrite: task.overwrite,
      ),
    TransferKind.download => TransferTask.download(
        remotePath: task.remotePath,
        localPath: task.localPath,
        host: task.host,
      ),
  };
}
