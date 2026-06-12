import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/host.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../transfers/transfer_state.dart';
import '../explorer_state.dart';
import 'destination_dialog.dart';

/// A labelled icon action used in the multi-select bar — tonal icon button
/// over a small caption, for tidier iconography than bare [IconButton]s.
class BarAction extends StatelessWidget {
  const BarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: Radii.chipR,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (color ?? scheme.primary).withValues(alpha: 0.12),
                borderRadius: Radii.chipR,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: fg),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar shown while one or more entries are selected: a header with
/// the selection count and select-all/clear toggle, plus copy/move/download/
/// delete batch actions.
class SelectionBar extends ConsumerWidget {
  const SelectionBar({
    super.key,
    required this.state,
    required this.notifier,
    required this.host,
  });

  final ExplorerState state;
  final ExplorerNotifier notifier;
  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final allSelected = state.selected.length == state.entries.length &&
        state.entries.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            Spacing.md, 0, Spacing.md, Spacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.cardR,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Deselect all',
                  onPressed: notifier.clearSelection,
                ),
                Expanded(
                  child: Text(
                    '${state.selected.length} selected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      allSelected ? notifier.clearSelection : notifier.selectAll,
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                  label: Text(allSelected ? 'Clear' : 'Select all'),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                BarAction(
                  icon: Icons.copy_outlined,
                  label: 'Copy',
                  onPressed: () => _showDestPicker(context, 'copy'),
                ),
                BarAction(
                  icon: Icons.drive_file_move_outline,
                  label: 'Move',
                  onPressed: () => _showDestPicker(context, 'move'),
                ),
                BarAction(
                  icon: Icons.download_outlined,
                  label: 'Download',
                  onPressed: () => _downloadSelected(context, ref),
                ),
                BarAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: scheme.error,
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDestPicker(BuildContext context, String action) async {
    final dest = await showDialog<String>(
      context: context,
      builder: (ctx) => const DestinationDialog(hint: 'Destination path'),
    );
    if (dest == null || !context.mounted) return;
    try {
      final res = action == 'copy'
          ? await notifier.copySelected(dest)
          : await notifier.moveSelected(dest);
      if (context.mounted) {
        await _reportBatch(
            context, res, action == 'copy' ? 'Copied' : 'Moved');
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, '${action == 'copy' ? 'Copy' : 'Move'} failed: $e',
            onRetry: () => _showDestPicker(context, action));
      }
    }
  }

  /// Inspects a batch operation [res] for per-item failures and either shows a
  /// success snackbar or a dialog listing the failed items.
  Future<void> _reportBatch(BuildContext context, Map<String, dynamic> res,
      String successVerb) async {
    final results = (res['results'] as List?) ?? const [];
    final failed = results
        .whereType<Map>()
        .where((r) => r['ok'] == false)
        .toList();
    if (!context.mounted) return;
    if (failed.isEmpty) {
      final n = results.length;
      showSuccess(context, '$successVerb $n item${n == 1 ? '' : 's'}');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$successVerb with ${failed.length} error(s)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: failed.map((f) {
              final err = f['error'];
              final msg = err is Map
                  ? (err['message'] ?? err['code'] ?? 'failed')
                  : 'failed';
              return ListTile(
                dense: true,
                title: Text('${f['path'] ?? '?'}'),
                subtitle: Text('$msg'),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _downloadSelected(
      BuildContext context, WidgetRef ref) async {
    final downloadsDir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    for (final path in state.selected) {
      final name = path.split(RegExp(r'[/\\]')).last;
      ref.read(transferQueueProvider.notifier).enqueue(
            TransferTask.download(
              remotePath: path,
              localPath: '${downloadsDir.path}/$name',
              host: host,
            ),
          );
    }
    final count = state.selected.length;
    notifier.clearSelection();
    if (context.mounted) {
      showSuccess(context, 'Queued $count download${count == 1 ? '' : 's'}');
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
            'Permanently delete ${state.selected.length} item(s)? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final res = await notifier.deleteSelected();
        if (context.mounted) {
          await _reportBatch(context, res, 'Deleted');
        }
      } catch (e) {
        if (context.mounted) showError(context, 'Delete failed: $e');
      }
    }
  }
}
