import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/platform/file_opener.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../explorer/meta_sheet.dart';
import '../share/share_sheet.dart';
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
      running: context.l10n.preparingToShare(entry.name),
      error: context.l10n.couldNotShare(entry.name),
    );
  }

  /// Opens the file in an external app via the system's "Open with" chooser.
  /// Like [share], this fetches the file to a temp cache first because the
  /// agent serves content only over a pinned TLS connection with bearer auth.
  Future<void> openWith(BuildContext context) async {
    await runWithFeedback<void>(
      context,
      () async {
        final dir = await getTemporaryDirectory();
        final openDir = Directory('${dir.path}/open_cache');
        if (!await openDir.exists()) {
          await openDir.create(recursive: true);
        }
        final safeName = entry.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
        final file = File('${openDir.path}/$safeName');
        await client.downloadFile(remotePath: entry.path, localFile: file);
        final mimeType = entry.mimeType ?? _mimeFromExtension(entry.name);
        await FileOpener.open(file, mimeType);
      },
      running: context.l10n.preparingToOpen(entry.name),
      error: context.l10n.couldNotOpen(entry.name),
    );
  }

  /// Saves (downloads) the file to the device via the shared transfer queue —
  /// the same path the meta-sheet's Download action uses, so downloads show up
  /// in the transfers center and survive navigation.
  Future<void> save(BuildContext context, WidgetRef ref) async {
    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/${entry.name}';
    ref
        .read(transferQueueProvider.notifier)
        .enqueue(
          TransferTask.download(
            remotePath: entry.path,
            localPath: localPath,
            host: host,
          ),
        );
    if (context.mounted) showInfo(context, context.l10n.savingFile(entry.name));
  }

  /// Deletes the file after a confirm dialog (mirroring the meta-sheet's delete
  /// flow), then pops the preview and notifies [onDeleted]. Returns `true` if
  /// the file was deleted (so the pager can drop it from its page list).
  Future<bool> delete(BuildContext context) async {
    // null = cancel, false = trash (default, reversible), true = permanent.
    final permanent = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(ctx.l10n.deleteTitle),
            description: Text(ctx.l10n.moveToTrashConfirm(entry.name)),
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
    if (permanent == null || !context.mounted) return false;
    try {
      final name = entry.name;
      await client.delete([entry.path], permanent: permanent);
      onDeleted?.call();
      if (context.mounted) {
        showSuccess(
          context,
          permanent
              ? context.l10n.deletedName(name)
              : context.l10n.movedToTrashName(name),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.deleteFailed(humanizeError(e)));
      }
      return false;
    }
  }
}

/// The unified preview top bar shared by every viewer type. Presents the file
/// **name** + **size** (via the one [formatSize]) and a trailing 2-icon
/// action row — Share (mint a link, [openShareLinkSheet]) and "..."
/// ([openPreviewMetaSheet]) — matching the mockup's preview chrome exactly.
/// Save/delete/rename/open-with/QR-handoff all now live behind the "..."
/// meta sheet instead of being spread across individual top-bar icons.
///
/// Rendered as a real [AppBar] (cheap on Skia — no blur/shader). On dark media
/// canvases (image/video) it paints translucent black with white foreground so
/// it reads over the content; otherwise it uses the ambient theme.
class PreviewTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PreviewTopBar({
    super.key,
    required this.actions,
    this.onChanged,
    this.leadingActions = const [],
    this.onDark = false,
  });

  /// Actions for the currently visible entry.
  final PreviewActions actions;

  /// Invoked when the meta sheet reports a change (rename/delete/extract/…)
  /// so a pager can react (e.g. drop the current page). When null, the
  /// preview route itself is popped — the safe default for a single-entry
  /// preview, where a changed/deleted file has nothing else useful to show.
  final VoidCallback? onChanged;

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
          Text(
            entry.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (size.isNotEmpty)
            Text(
              size,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    fg?.withValues(alpha: 0.8) ??
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: [
        ...leadingActions,
        IconButton(
          icon: const Icon(LucideIcons.share2),
          tooltip: context.l10n.shareLinkButton,
          onPressed: () => openShareLinkSheet(context, entry, actions.client),
        ),
        IconButton(
          icon: const Icon(LucideIcons.moreVertical),
          tooltip: context.l10n.moreTooltip,
          onPressed:
              () =>
                  openPreviewMetaSheet(context, actions, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// Mints a one-time share link for [entry] and shows the app's [ShareSheet] —
/// the "Share" icon in every preview screen's chrome (mockup: tapping Share
/// opens the link/QR/active-shares sheet, not the OS share chooser). Distinct
/// from [PreviewActions.share], the raw "send the file bytes" share still
/// offered from inside the meta sheet.
Future<void> openShareLinkSheet(
  BuildContext context,
  Entry entry,
  AgentClient client,
) async {
  try {
    final link = await client.mintShareLink(entry.path);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => ShareSheet(client: client, link: link, fileName: entry.name),
    );
  } catch (e) {
    if (context.mounted) {
      showError(context, context.l10n.shareLinkFailed(humanizeError(e)));
    }
  }
}

/// The shared trailing 2-icon chrome (Share, "...") for a **standalone**
/// preview screen (the rare no-siblings path — [chromeless]:false, not
/// backed by [PreviewPager]/[PreviewTopBar]). [host] is optional because a
/// few call sites (mostly tests) construct these screens without one; the
/// meta-sheet icon simply doesn't render in that case (it needs a [Host]),
/// while Share (only needs [entry] + [client]) always does.
List<Widget> previewChromeActions({
  required BuildContext context,
  required Entry entry,
  required AgentClient client,
  Host? host,
}) => [
  IconButton(
    icon: const Icon(LucideIcons.share2),
    tooltip: context.l10n.shareLinkButton,
    onPressed: () => openShareLinkSheet(context, entry, client),
  ),
  if (host != null)
    IconButton(
      icon: const Icon(LucideIcons.moreVertical),
      tooltip: context.l10n.moreTooltip,
      onPressed:
          () => openPreviewMetaSheet(
            context,
            PreviewActions(entry: entry, host: host, client: client),
          ),
    ),
];

/// Opens the shared [MetaSheet] for [actions.entry] — the preview chrome's
/// "..." icon (mockup: 3 stacked dots). Reuses the explorer's existing meta
/// sheet (rename/download/delete/QR-handoff/etc.) instead of re-building a
/// second, smaller actions list — it already covers everything
/// [PreviewTopBar] used to offer directly (openWith/save/showInFolder/delete).
Future<void> openPreviewMetaSheet(
  BuildContext context,
  PreviewActions actions, {
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder:
        (_) => MetaSheet(
          entry: actions.entry,
          host: actions.host,
          client: actions.client,
          onChanged: () {
            actions.onDeleted?.call();
            if (onChanged != null) {
              onChanged();
            } else if (context.mounted) {
              Navigator.of(context).maybePop();
            }
          },
        ),
  );
}

/// Fallback MIME type lookup from file extension, used when the agent's
/// [Entry.mimeType] is null. Covers the common types users are likely to
/// open externally; anything unrecognised falls back to octet-stream so
/// Android still offers a chooser.
String _mimeFromExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'application/octet-stream';
  switch (fileName.substring(dot + 1).toLowerCase()) {
    // Images
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'heic':
    case 'heif':
      return 'image/heif';
    // Video
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'mkv':
      return 'video/x-matroska';
    case 'avi':
      return 'video/x-msvideo';
    case 'webm':
      return 'video/webm';
    // Audio
    case 'mp3':
      return 'audio/mpeg';
    case 'aac':
    case 'm4a':
      return 'audio/mp4';
    case 'wav':
      return 'audio/wav';
    case 'flac':
      return 'audio/flac';
    case 'ogg':
    case 'oga':
      return 'audio/ogg';
    // Documents
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    // Archives
    case 'zip':
      return 'application/zip';
    case 'gz':
    case 'tgz':
      return 'application/gzip';
    // Text
    case 'txt':
    case 'log':
    case 'md':
    case 'csv':
      return 'text/plain';
    case 'html':
    case 'htm':
      return 'text/html';
    case 'json':
      return 'application/json';
    case 'xml':
      return 'text/xml';
    // APK
    case 'apk':
      return 'application/vnd.android.package-archive';
    default:
      return 'application/octet-stream';
  }
}
