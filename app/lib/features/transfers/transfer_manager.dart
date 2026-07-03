import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart';
import 'transfer_speed.dart';
import 'transfer_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet listing all transfers, grouped into collapsible
/// Active / Queued / Done / Failed sections with live per-task speed + ETA,
/// swipe-to-pause/resume and swipe-to-remove (with undo), and inline retry on
/// failures.
///
/// All engine interaction goes through [TransferQueueNotifier]; this screen is
/// pure presentation plus the read-only [transferSamplerProvider] for speed.
class TransferManagerSheet extends StatelessWidget {
  const TransferManagerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder:
          (_, controller) => DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: Radii.sheetTopR,
            ),
            child: ClipRRect(
              borderRadius: Radii.sheetTopR,
              child: Column(
                children: [
                  _buildHandle(context),
                  Expanded(child: TransferGroupedList(controller: controller)),
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

/// Header (title + clear-completed) and collapsible-section list of all
/// transfers. Shared by [TransferManagerSheet] and the Transfers tab body
/// ([HomeShell]'s `_TransfersTab`).
class TransferGroupedList extends ConsumerWidget {
  const TransferGroupedList({
    super.key,
    this.controller,
    this.showTitle = true,
  });

  /// Hooks into the host [DraggableScrollableSheet]'s scroll position; null
  /// for non-sheet hosts (e.g. a tab body), where the list scrolls on its own.
  final ScrollController? controller;

  /// Whether to show the inline "Transfers" title — off when an app bar
  /// already shows it (the tab body case).
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transferQueueProvider);

    final groups = groupTransfers(transfers);
    final doneAndFailed = [
      ...groups[TransferGroup.done]!,
      ...groups[TransferGroup.failed]!,
    ];
    final visibleGroups = [
      for (final group in TransferGroup.values)
        if (groups[group]!.isNotEmpty) group,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              if (showTitle)
                Text(
                  context.l10n.transfersTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const Spacer(),
              if (doneAndFailed.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(LucideIcons.listX, size: 18),
                  label: Text(context.l10n.clearCompletedButton),
                  onPressed: () {
                    for (final t in doneAndFailed) {
                      ref.read(transferQueueProvider.notifier).remove(t.id);
                    }
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child:
              transfers.isEmpty
                  ? _EmptyTransfers(text: context.l10n.noTransfers)
                  : ListView(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    children: [
                      for (var i = 0; i < visibleGroups.length; i++) ...[
                        if (i > 0) const SizedBox(height: Spacing.md),
                        _TransferSection(
                          group: visibleGroups[i],
                          tasks: groups[visibleGroups[i]]!,
                        ),
                      ],
                    ],
                  ),
        ),
      ],
    );
  }
}

/// Muted icon-over-text empty state, matching the Figma spec's "Empty
/// folder"/"No results" pattern (`FileBrowserScreen.tsx`) rather than a bare
/// line of text.
class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.arrowUpDown,
            size: 36,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: Spacing.sm),
          Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
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
  String localizedLabel(BuildContext context) => switch (this) {
    TransferGroup.active => context.l10n.transferGroupActive,
    TransferGroup.queued => context.l10n.transferGroupQueued,
    TransferGroup.done => context.l10n.transferGroupDone,
    TransferGroup.failed => context.l10n.transferGroupFailed,
  };
}

/// Buckets [tasks] into the four manager groups by [TransferStatus]:
/// running + paused → active, queued → queued, completed → done,
/// failed → failed. Always returns an entry for every group (possibly empty),
/// preserving input order within each bucket.
Map<TransferGroup, List<TransferTask>> groupTransfers(
  List<TransferTask> tasks,
) {
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: SectionLabel(
            widget.group.localizedLabel(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: Radii.chipR,
                  ),
                  child: Text(
                    '${widget.tasks.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Icon(
                  _expanded
                      ? LucideIcons.chevronDown
                      : LucideIcons.chevronRight,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          GroupedCard(
            padded: false,
            children: [
              for (var i = 0; i < widget.tasks.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _TransferTile(task: widget.tasks[i]),
              ],
            ],
          ),
      ],
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
      direction:
          _canPauseResume
              ? DismissDirection.horizontal
              : DismissDirection.startToEnd,
      background: _swipeBackground(context, removing: true),
      secondaryBackground:
          _canPauseResume ? _swipeBackground(context, removing: false) : null,
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
      context.l10n.removedTransfer(removed.displayName),
      action: SnackBarAction(
        label: context.l10n.undoButton,
        onPressed: () => notifier.enqueue(reenqueuableCopy(removed)),
      ),
    );
  }

  Widget _swipeBackground(BuildContext context, {required bool removing}) {
    final scheme = Theme.of(context).colorScheme;
    final color = removing ? scheme.errorContainer : scheme.tertiaryContainer;
    final onColor =
        removing ? scheme.onErrorContainer : scheme.onTertiaryContainer;
    final icon =
        removing
            ? LucideIcons.trash2
            : (task.status == TransferStatus.paused
                ? LucideIcons.play
                : LucideIcons.pause);
    return Container(
      color: color,
      alignment:
          removing
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Icon(icon, color: onColor),
    );
  }

  /// The chip's icon tint for non-terminal states: blue (scheme primary) for
  /// downloads, emerald (scheme secondary) for uploads — Figma's
  /// direction-coded status chips. Terminal states (completed/failed) keep
  /// their own universal semantic color regardless of direction.
  Color _directionColor(ColorScheme scheme) =>
      task.kind == TransferKind.upload ? scheme.secondary : scheme.primary;

  Widget _statusIcon(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final directionColor = _directionColor(scheme);
    final Widget glyph = switch (task.status) {
      TransferStatus.running => SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
          value: task.progress > 0 ? task.progress : null,
          strokeWidth: 2.5,
          color: directionColor,
        ),
      ),
      TransferStatus.completed => const Icon(
        LucideIcons.circleCheck,
        color: Brand.online,
      ),
      TransferStatus.failed => Icon(
        LucideIcons.circleAlert,
        color: scheme.error,
      ),
      TransferStatus.paused => Icon(
        LucideIcons.circlePause,
        color: directionColor,
      ),
      TransferStatus.queued => Icon(LucideIcons.clock, color: directionColor),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.smR,
      ),
      alignment: Alignment.center,
      child: glyph,
    );
  }

  Widget? _buildSubtitle(
    BuildContext context,
    WidgetRef ref,
    TransferQueueNotifier notifier,
  ) {
    final scheme = Theme.of(context).colorScheme;
    switch (task.status) {
      case TransferStatus.running:
      case TransferStatus.paused:
        final paused = task.status == TransferStatus.paused;
        // Live speed/ETA from the read-only sampler (running tasks only).
        final eta = paused ? null : ref.watch(transferSamplerProvider)[task.id];
        final meta = <String>[
          '${formatSize(task.transferredBytes)} / ${formatSize(task.totalBytes)}',
          if (paused) context.l10n.pausedStatus,
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
                  color: _directionColor(scheme),
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
            task.error ?? context.l10n.unknownError,
            style: TextStyle(color: scheme.error),
          ),
        );
      case TransferStatus.completed:
        final label =
            task.kind == TransferKind.upload
                ? context.l10n.uploadedStatus
                : (task.savedLocation != null
                    ? context.l10n.savedToLocation(task.savedLocation!)
                    : context.l10n.downloadedStatus);
        final showVerified = task.kind == TransferKind.upload && task.verified;
        if (!showVerified) {
          return Text(
            label,
            style: const TextStyle(color: Brand.online),
            overflow: TextOverflow.ellipsis,
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: Brand.online),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Spacing.xs),
              _VerifiedBadge(sha256: task.sha256),
            ],
          ),
        );
      case TransferStatus.queued:
        return Text(context.l10n.queuedStatus);
    }
  }

  Widget? _buildActions(BuildContext context, TransferQueueNotifier notifier) {
    switch (task.status) {
      case TransferStatus.running:
        return IconButton(
          icon: const Icon(LucideIcons.pause),
          tooltip: context.l10n.pauseTooltip,
          onPressed: () => notifier.pause(task.id),
        );
      case TransferStatus.paused:
        return IconButton(
          icon: const Icon(LucideIcons.play),
          tooltip: context.l10n.resumeTooltip,
          onPressed: () => notifier.retry(task.id),
        );
      case TransferStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.refreshCw),
              tooltip: context.l10n.retryButton,
              onPressed: () => notifier.retry(task.id),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x),
              tooltip: context.l10n.removeTooltip,
              onPressed: () => notifier.remove(task.id),
            ),
          ],
        );
      case TransferStatus.completed:
        return IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: context.l10n.removeTooltip,
          onPressed: () => notifier.remove(task.id),
        );
      case TransferStatus.queued:
        return IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: context.l10n.removeTooltip,
          onPressed: () => notifier.remove(task.id),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Verified badge — shown on completed uploads whose whole-file SHA-256 was
// confirmed by the agent on `POST /transfers/{id}/complete`.
// ---------------------------------------------------------------------------

/// Small M3 tonal chip reading "Verified" with a check-shield icon.
///
/// If [sha256] is available, a tooltip shows its first 10 hex characters so
/// the user can spot-check it against the source file if they want.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({this.sha256});

  final String? sha256;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: Radii.chipR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.verified,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            context.l10n.verifiedLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (sha256 == null || sha256!.isEmpty) return chip;

    final short = sha256!.length > 10 ? sha256!.substring(0, 10) : sha256!;
    return Tooltip(message: context.l10n.sha256Prefix(short), child: chip);
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
