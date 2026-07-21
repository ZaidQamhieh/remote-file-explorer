import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/storage/transfer_journal.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/grouped_card.dart';

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
        title: Text(context.l10n.transferHistoryTitle),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.trash2),
            onPressed: () async {
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
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Brand.online.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          isUpload ? LucideIcons.upload : LucideIcons.download,
          size: 18,
          color: Brand.online,
        ),
      ),
      title: Text(
        record.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${record.hostLabel} · ${formatSize(record.bytes)}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Brand.online.withValues(alpha: 0.16),
          borderRadius: Radii.stadiumR,
        ),
        child: Text(
          'Completed',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Brand.online,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
