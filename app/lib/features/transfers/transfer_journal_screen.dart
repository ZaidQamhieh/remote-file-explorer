import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/storage/transfer_journal.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';

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
                  Icon(
                    LucideIcons.history,
                    size: 64,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
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
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final r = records[index];
              final isUpload = r.kind == 'upload';
              return ListTile(
                leading: Icon(
                  isUpload ? LucideIcons.upload : LucideIcons.download,
                  color: isUpload ? scheme.tertiary : scheme.primary,
                ),
                title: Text(
                  r.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${r.hostLabel} · ${formatSize(r.bytes)}'),
                trailing: Text(
                  _formatRelative(context, r.completedAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatRelative(BuildContext context, DateTime dt) {
    final l = context.l10n;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l.relativeJustNow;
    if (diff.inHours < 1) return l.relativeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l.relativeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l.relativeDaysAgo(diff.inDays);
    return '${dt.month}/${dt.day}';
  }
}
