import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../transfers/transfer_state.dart';

/// The set of cross-cutting actions a preview viewer offers for the file it's
/// currently showing — Share, Save (download to device), Delete, and "Show in
/// folder". Centralised here so all four viewer types (image/pdf/video/text)
/// present an identical action row through [PreviewTopBar], driven by the
/// current page's [Entry], rather than each screen wiring its own subset.
///
/// All actions run through the pinned, authenticated [AgentClient] — there is
/// no plain-network path to the agent (self-signed cert + bearer auth).
class PreviewActions {
  const PreviewActions({
    required this.entry,
    required this.host,
    required this.client,
    this.onDeleted,
  });

  final Entry entry;
  final Host host;
  final AgentClient client;

  /// Called after a successful delete so the host screen (the explorer) can
  /// refresh its listing — otherwise the listing keeps showing the deleted
  /// entry until a manual refresh.
  final VoidCallback? onDeleted;

  /// Shares the file via the OS share sheet. The agent serves content only
  /// over a pinned TLS connection with bearer auth, so we can't hand a URL to
  /// the share sheet — instead we fetch the bytes into a temp cache file and
  /// share that local path. Bounded to avoid pulling huge files into memory.
  Future<void> share(BuildContext context) async {
    await runWithFeedback<void>(
      context,
      () async {
        final dir = await getTemporaryDirectory();
        final shareDir = Directory('${dir.path}/share_cache');
        if (!await shareDir.exists()) {
          await shareDir.create(recursive: true);
        }
        final safeName = entry.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
        final file = File('${shareDir.path}/$safeName');
        await client.downloadFile(remotePath: entry.path, localFile: file);
        await Share.shareXFiles([XFile(file.path)]);
      },
      running: 'Preparing ${entry.name} to share…',
      error: 'Could not share ${entry.name}',
    );
  }

  /// Saves (downloads) the file to the device via the shared transfer queue —
  /// the same path the meta-sheet's Download action uses, so downloads show up
  /// in the transfers center and survive navigation.
  Future<void> save(BuildContext context, WidgetRef ref) async {
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/${entry.name}';
    ref.read(transferQueueProvider.notifier).enqueue(
          TransferTask.download(
            remotePath: entry.path,
            localPath: localPath,
            host: host,
          ),
        );
    if (context.mounted) showInfo(context, 'Saving ${entry.name}…');
  }

  /// Deletes the file after a confirm dialog (mirroring the meta-sheet's delete
  /// flow), then pops the preview and notifies [onDeleted]. Returns `true` if
  /// the file was deleted (so the pager can drop it from its page list).
  Future<bool> delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content:
            Text('Permanently delete "${entry.name}"? This cannot be undone.'),
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
    if (confirmed != true || !context.mounted) return false;
    try {
      final name = entry.name;
      await client.delete([entry.path]);
      onDeleted?.call();
      if (context.mounted) showSuccess(context, 'Deleted $name');
      return true;
    } catch (e) {
      if (context.mounted) showError(context, 'Delete failed: $e');
      return false;
    }
  }
}

/// The unified preview top bar shared by every viewer type. Presents the file
/// **name** + **size** (via the one [formatSize]) and a trailing action row:
/// Share, Save, Delete, and "Show in folder", all driven by [actions] for the
/// page currently visible.
///
/// "Show in folder" simply pops the preview back to the containing folder — in
/// the in-folder case the explorer listing is exactly one frame below the
/// preview route, so closing it lands the user on the file's folder.
///
/// Rendered as a real [AppBar] (cheap on Skia — no blur/shader). On dark media
/// canvases (image/video) it paints translucent black with white foreground so
/// it reads over the content; otherwise it uses the ambient theme.
class PreviewTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PreviewTopBar({
    super.key,
    required this.actions,
    this.onDelete,
    this.onShowInFolder,
    this.leadingActions = const [],
    this.onDark = false,
  });

  /// Actions for the currently visible entry.
  final PreviewActions actions;

  /// Invoked when Delete completes (so a pager can drop the page). When null,
  /// Delete just runs [PreviewActions.delete] and pops the route itself.
  final VoidCallback? onDelete;

  /// Override for "Show in folder". Defaults to popping the preview route.
  final VoidCallback? onShowInFolder;

  /// Extra per-type actions inserted before the shared ones (e.g. the text
  /// viewer's Edit and line-numbers toggle).
  final List<Widget> leadingActions;

  /// Whether the bar sits over a dark media canvas (image/video).
  final bool onDark;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final entry = actions.entry;
    final size = formatSize(entry.size);
    final fg = onDark ? Colors.white : null;

    return AppBar(
      backgroundColor: onDark ? Colors.black.withValues(alpha: 0.45) : null,
      foregroundColor: fg,
      elevation: 0,
      titleSpacing: 0,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  )),
          if (size.isNotEmpty)
            Text(size,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: fg?.withValues(alpha: 0.8) ??
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
        ],
      ),
      actions: [
        ...leadingActions,
        IconButton(
          icon: const Icon(Icons.ios_share_outlined),
          tooltip: 'Share',
          onPressed: () => actions.share(context),
        ),
        // Save needs a WidgetRef for the transfer queue — wrap a Consumer so we
        // don't force every host into a ConsumerWidget.
        Consumer(
          builder: (context, ref, _) => IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Save to device',
            onPressed: () => actions.save(context, ref),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.folder_open_outlined),
          tooltip: 'Show in folder',
          onPressed: onShowInFolder ?? () => Navigator.of(context).maybePop(),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () async {
            final deleted = await actions.delete(context);
            if (!deleted) return;
            if (onDelete != null) {
              onDelete!();
            } else if (context.mounted) {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ],
    );
  }
}
