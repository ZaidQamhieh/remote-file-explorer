import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/storage/transfer_journal.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';

/// Date-grouped ("Today" / "Yesterday" / older) transfer history, matching
/// the mockup's `transfer-journal` screen shape.
///
/// The mockup shows both green "Completed" and red "Failed" rows in the
/// journal. The real [TransferJournalNotifier] only ever logs a record on
/// successful completion (`_logToJournal` in `transfer_state.dart` — there is
/// no failure path that writes to the journal), so every row here is
/// necessarily a completed transfer. Rather than fabricate a "Failed" badge
/// with no failed records behind it, every row shows the real "Completed"
/// badge; adding failed-transfer journaling would be a business-logic change
/// out of scope for this view-layer rewrite.
class TransferJournalScreen extends ConsumerWidget {
  const TransferJournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journalAsync = ref.watch(transferJournalProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: ScreenHeader(context.l10n.transferHistoryTitle),
        actions: [
          _AppbarIconBtn(
            icon: LucideIcons.trash2,
            tooltip: context.l10n.clearTooltip,
            onTap: () async {
              final confirmed = await showShadDialog<bool>(
                context: context,
                builder:
                    (ctx) => ShadDialog.alert(
                      title: Text(ctx.l10n.clearHistoryTitle),
                      description: Text(ctx.l10n.clearHistoryConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(ctx.l10n.cancelButton),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(ctx.l10n.clearTooltip),
                        ),
                      ],
                    ),
              );
              if (confirmed == true) {
                await ref.read(transferJournalProvider.notifier).clear();
              }
            },
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: journalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(context.l10n.couldNotLoadHistory)),
        data: (records) {
          if (records.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GradientBlobHero(icon: LucideIcons.history, size: 120),
                  const SizedBox(height: Spacing.md),
                  Text(
                    context.l10n.noTransfersYet,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          final groups = _groupByDay(records);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            children: [
              for (final group in groups) ...[
                SectionLabel(group.label),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: GroupedCard(
                    padded: false,
                    children: [
                      for (var i = 0; i < group.records.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _JournalRow(record: group.records[i]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DayGroup {
  const _DayGroup(this.label, this.records);
  final String label;
  final List<TransferRecord> records;
}

/// Buckets [records] (already newest-first) into "Today" / "Yesterday" /
/// "M/D" groups by real [TransferRecord.completedAt] calendar dates —
/// preserves the mockup's date-grouped shape without inventing a boundary.
List<_DayGroup> _groupByDay(List<TransferRecord> records) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  String labelFor(DateTime dt) {
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return '${dt.month}/${dt.day}';
  }

  final groups = <_DayGroup>[];
  for (final r in records) {
    final label = labelFor(r.completedAt);
    if (groups.isNotEmpty && groups.last.label == label) {
      groups.last.records.add(r);
    } else {
      groups.add(_DayGroup(label, [r]));
    }
  }
  return groups;
}

class _JournalRow extends StatelessWidget {
  const _JournalRow({required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final isUpload = record.kind == 'upload';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Brand.online.withValues(alpha: 0.14),
              borderRadius: Radii.smR,
            ),
            alignment: Alignment.center,
            child: Icon(
              isUpload ? LucideIcons.upload : LucideIcons.download,
              size: 18,
              color: Brand.online,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${record.hostLabel} · ${formatSize(record.bytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Brand.online.withValues(alpha: 0.14),
              borderRadius: Radii.stadiumR,
            ),
            child: const Text(
              'Completed',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Brand.online,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.iconbtn`: 34x34, 19px glyph — replaces a raw [IconButton]
/// in this screen's app bar actions.
class _AppbarIconBtn extends StatelessWidget {
  const _AppbarIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.92,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
