import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/host.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../transfers/transfer_state.dart';
import '../clipboard_state.dart';
import '../explorer_state.dart';
import 'batch_report.dart';

/// A labelled icon action used in the bottom contextual action bar — tonal
/// icon button over a small caption, for tidier iconography than bare
/// [IconButton]s.
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom contextual action bar shown while one or more entries are
/// selected: `surfaceContainerHigh` surface with r28 top corners, holding
/// Cut / Copy / Download / Delete batch actions (Delete in `error` color).
///
/// Cut and Copy fill the app-scoped [clipboardProvider] (see
/// `clipboard_state.dart`) instead of moving/copying immediately — the user
/// then navigates to a destination folder and taps the Paste FAB (see
/// `explorer_screen.dart`'s `_buildFab`/`_paste`).
///
/// The selection count + select-all/invert controls live in the app bar
/// (see `explorer_screen.dart`'s `_SelectionAppBar`), not here — this bar is
/// actions-only.
///
/// Note: the design spec calls for a "Share" action; the app has no share
/// integration (would require a new package), so "Download" — the existing,
/// functionally closest action (saves files locally, from where the OS share
/// sheet can take over) — fills that slot.
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

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.sheetTopR,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            BarAction(
              icon: Icons.content_cut,
              label: 'Cut',
              onPressed: () => _cutSelected(context, ref),
            ),
            BarAction(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onPressed: () => _copySelected(context, ref),
            ),
            BarAction(
              icon: Icons.folder_zip_outlined,
              label: 'Compress',
              onPressed: () => _compressSelected(context, ref),
            ),
            BarAction(
              icon: Icons.download_outlined,
              label: 'Download',
              onPressed: () => _downloadSelected(context, ref),
            ),
            BarAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: scheme.error,
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Fills the clipboard (copy mode) with the current selection and clears
  /// it — paste happens later, from any folder on this host (see
  /// `explorer_screen.dart`'s `_paste`).
  void _copySelected(BuildContext context, WidgetRef ref) {
    final paths = state.selected.toList();
    final count = paths.length;
    ref.read(clipboardProvider.notifier).copy(paths, host.id);
    notifier.clearSelection();
    showSuccess(
      context,
      '$count item${count == 1 ? '' : 's'} copied — open a folder and tap Paste',
    );
  }

  /// Fills the clipboard (cut mode) with the current selection and clears
  /// it — paste happens later, from any folder on this host (see
  /// `explorer_screen.dart`'s `_paste`).
  void _cutSelected(BuildContext context, WidgetRef ref) {
    final paths = state.selected.toList();
    final count = paths.length;
    ref.read(clipboardProvider.notifier).cut(paths, host.id);
    notifier.clearSelection();
    showSuccess(
      context,
      '$count item${count == 1 ? '' : 's'} cut — open a folder and tap Paste',
    );
  }

  /// Zips the current selection into a new archive in the current folder. The
  /// name is derived from the selection (the single item's name, or the
  /// folder's name for a multi-select); the agent auto-renames on collision so
  /// this never clobbers an existing file.
  Future<void> _compressSelected(BuildContext context, WidgetRef ref) async {
    final paths = state.selected.toList();
    final dirPath = state.currentPath;
    final sep = dirPath.contains('\\') ? '\\' : '/';
    final stem =
        paths.length == 1
            ? basenameOf(paths.first)
            : (folderLabel(dirPath) == 'Root'
                ? 'Archive'
                : folderLabel(dirPath));
    final dest =
        dirPath.endsWith(sep) ? '$dirPath$stem.zip' : '$dirPath$sep$stem.zip';
    try {
      final entry = await notifier.compressSelected(dest, sources: paths);
      notifier.clearSelection();
      if (context.mounted) showSuccess(context, 'Compressed to ${entry.name}');
    } catch (e) {
      if (context.mounted) showError(context, 'Compress failed: $e');
    }
  }

  Future<void> _downloadSelected(BuildContext context, WidgetRef ref) async {
    final downloadsDir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    for (final path in state.selected) {
      final name = path.split(RegExp(r'[/\\]')).last;
      ref
          .read(transferQueueProvider.notifier)
          .enqueue(
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
    final count = state.selected.length;
    // Three-way: Cancel / Delete forever / Move to Trash. `null` = cancel,
    // false = trash (default, reversible), true = permanent.
    final permanent = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete?'),
            content: Text(
              'Move $count item${count == 1 ? '' : 's'} to Trash? '
              'You can restore ${count == 1 ? 'it' : 'them'} later from Trash.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: const Text('Delete forever'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
    );
    if (permanent == null) return;
    try {
      final res = await notifier.deleteSelected(permanent: permanent);
      if (context.mounted) {
        await reportBatchResult(
          context,
          res,
          permanent ? 'Deleted' : 'Moved to Trash',
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Delete failed: $e');
    }
  }
}
