import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/host.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/pressable.dart';
import '../../transfers/transfer_state.dart';
import '../clipboard_state.dart';
import '../explorer_state.dart';
import 'batch_report.dart';

/// An icon action in `.selbar-actions` — the mockup's plain 34x34 `.iconbtn`
/// (icon only, label carried by the tooltip), replacing `InkWell` + a
/// 44px tonal square + caption.
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
    return Tooltip(
      message: label,
      child: Pressable(
        onTap: onPressed,
        pressedScale: 0.92,
        child: SizedBox(width: 34, height: 34, child: Icon(icon, color: fg)),
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

    // Mockup's `.selection-bar`: flush bottom bar, surface-2, top border
    // only (no radius) — count label on the left, `.selbar-actions` (a
    // tight-gap row of plain iconbtns) on the right.
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.nSelected(state.selected.length),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BarAction(
                  icon: LucideIcons.scissors,
                  label: context.l10n.cutButton,
                  onPressed: () => _cutSelected(context, ref),
                ),
                BarAction(
                  icon: LucideIcons.copy,
                  label: context.l10n.copyButton,
                  onPressed: () => _copySelected(context, ref),
                ),
                BarAction(
                  icon: LucideIcons.archive,
                  label: context.l10n.compressButton,
                  onPressed: () => _compressSelected(context, ref),
                ),
                BarAction(
                  icon: LucideIcons.download,
                  label: context.l10n.downloadButton,
                  onPressed: () => _downloadSelected(context, ref),
                ),
                BarAction(
                  icon: LucideIcons.trash2,
                  label: context.l10n.deleteButton,
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

  /// Fills the clipboard (copy mode) with the current selection and clears
  /// it — paste happens later, from any folder on this host (see
  /// `explorer_screen.dart`'s `_paste`).
  void _copySelected(BuildContext context, WidgetRef ref) {
    final paths = state.selected.toList();
    final count = paths.length;
    ref.read(clipboardProvider.notifier).copy(paths, host.id);
    notifier.clearSelection();
    showSuccess(context, context.l10n.clipboardCopiedHint(count));
  }

  /// Fills the clipboard (cut mode) with the current selection and clears
  /// it — paste happens later, from any folder on this host (see
  /// `explorer_screen.dart`'s `_paste`).
  void _cutSelected(BuildContext context, WidgetRef ref) {
    final paths = state.selected.toList();
    final count = paths.length;
    ref.read(clipboardProvider.notifier).cut(paths, host.id);
    notifier.clearSelection();
    showSuccess(context, context.l10n.clipboardCutHint(count));
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
      if (context.mounted) {
        showSuccess(context, context.l10n.compressedTo(entry.name));
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.compressFailed(humanizeError(e)));
      }
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
      showSuccess(context, context.l10n.queuedNDownloads(count));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final count = state.selected.length;
    // Three-way: Cancel / Delete forever / Move to Trash. `null` = cancel,
    // false = trash (default, reversible), true = permanent.
    final permanent = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(ctx.l10n.deleteTitle),
            description: Text(
              '${ctx.l10n.moveNItemsToTrash(count)} '
              '${ctx.l10n.canRestoreFromTrash(count)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: Text(ctx.l10n.deleteForeverButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.moveToTrashButton),
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
          permanent
              ? context.l10n.deletedLabel
              : context.l10n.movedToTrashLabel,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.deleteFailed(humanizeError(e)));
      }
    }
  }
}
