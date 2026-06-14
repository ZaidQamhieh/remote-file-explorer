import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../transfer_manager.dart';
import '../transfer_state.dart';

/// A thin, tappable progress strip that appears above the explorer's bottom
/// area whenever any transfer is in flight (running or queued).
///
/// It shows aggregate progress across all in-flight tasks; tapping it opens
/// the transfer manager. When nothing is active it collapses to zero height
/// (via [SizeTransition]) so it adds no layout cost on an idle screen.
///
/// This is the *only* transfers widget mounted on the explorer screen; it's
/// deliberately self-contained (reads [transferQueueProvider] itself) so the
/// explorer can wire it in with a single line and no extra state.
class MiniTransferBar extends ConsumerWidget {
  const MiniTransferBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transferQueueProvider);
    final active =
        transfers
            .where(
              (t) =>
                  t.status == TransferStatus.running ||
                  t.status == TransferStatus.queued,
            )
            .toList();

    // Aggregate progress: sum bytes across tasks that report a known total.
    var total = 0;
    var done = 0;
    for (final t in active) {
      if (t.totalBytes > 0) {
        total += t.totalBytes;
        done += t.transferredBytes;
      }
    }
    final value = total > 0 ? (done / total).clamp(0.0, 1.0) : null;

    final scheme = Theme.of(context).colorScheme;

    return AnimatedSize(
      duration: MotionDuration.medium,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child:
          active.isEmpty
              ? const SizedBox(width: double.infinity)
              : Material(
                color: scheme.surfaceContainerHigh,
                child: InkWell(
                  onTap: () => _openManager(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      Spacing.sm,
                      Spacing.md,
                      Spacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sync_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _label(active),
                                style: Theme.of(context).textTheme.labelMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: Spacing.xs),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  Radii.chip / 2,
                                ),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  String _label(List<TransferTask> active) {
    final n = active.length;
    final running = active.where((t) => t.status == TransferStatus.running);
    final name =
        running.isNotEmpty
            ? running.first.displayName
            : active.first.displayName;
    if (n == 1) return 'Transferring $name';
    return 'Transferring $name (+${n - 1} more)';
  }

  void _openManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TransferManagerSheet(),
    );
  }
}
