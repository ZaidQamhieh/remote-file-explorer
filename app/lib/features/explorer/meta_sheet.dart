import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/entry_leading.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/sheet_chrome.dart';
import '../handoff/qr_generate_screen.dart';
import '../preview/preview.dart';
import '../preview/preview_actions.dart';
import '../share/share_sheet.dart';
import '../transfers/transfer_state.dart';
import 'explorer_state.dart' show folderLabel, renameDestination;
import 'widgets/chmod_dialog.dart';

/// Bottom sheet showing detailed metadata for a single file, with rename,
/// delete, and download actions.
class MetaSheet extends ConsumerStatefulWidget {
  const MetaSheet({
    super.key,
    required this.entry,
    required this.host,
    required this.client,
    this.onChanged,
    this.siblings,
  });

  final Entry entry;
  final Host host;
  final AgentClient client;

  /// The visible listing this entry belongs to (the explorer's
  /// `displayEntries`). When provided, the in-app preview becomes swipeable
  /// between previewable siblings. Null for callers without a listing (the
  /// single-entry preview behaviour is preserved).
  final List<Entry>? siblings;

  /// Called after a successful rename or delete so the caller (the explorer
  /// screen) can refresh its listing — otherwise the listing + its cache
  /// keep showing stale data until the user manually refreshes.
  final VoidCallback? onChanged;

  @override
  ConsumerState<MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends ConsumerState<MetaSheet> {
  late Entry _entry;
  String? _checksum;
  bool _checksumLoading = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _refreshMeta();
  }

  Future<void> _refreshMeta() async {
    try {
      final fresh = await widget.client.meta(widget.entry.path);
      if (mounted) setState(() => _entry = fresh);
    } catch (_) {
      // Use cached entry on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Sized to content, not a fixed screen fraction — the old
    // DraggableScrollableSheet always claimed 55-90% of the screen even
    // though the action list is short, which is what made the sheet feel
    // oversized. Metadata now lives behind "Details" (see _showDetails), so
    // this sheet is just header + actions and naturally stays compact.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroTint = isDark ? figmaIconBg(_entry) : scheme.primary;
    final badgeBg =
        isDark
            ? figmaIconBg(_entry)
            : _entry.isDir
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.surfaceContainerHighest;
    final subtitle = [
      if (_entry.size != null) formatSize(_entry.size),
      if (_entry.modified != null) formatDate(_entry.modified!.toLocal()),
    ].join(' · ');
    return SafeArea(
      child: SingleChildScrollView(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: Radii.sheetTopR,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHero(
                badge: EntryLeading(entry: _entry, size: 30),
                badgeColor: badgeBg,
                tint: heroTint,
                title: _entry.name,
                subtitle: subtitle,
                onClose: () => Navigator.pop(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.xl,
                ),
                child: _buildActions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final rows = <Widget>[
      _row(context, LucideIcons.route, l.metaPath, _entry.path),
      if (_entry.size != null)
        _row(context, LucideIcons.ruler, l.metaSize, formatSize(_entry.size)),
      if (_entry.mimeType != null)
        _row(context, LucideIcons.tag, l.metaType, _entry.mimeType!),
      if (_entry.mode != null)
        InkWell(
          onTap: () async {
            final updated = await ChmodDialog.show(
              context,
              entry: _entry,
              client: widget.client,
            );
            if (updated != null && mounted) {
              setState(() => _entry = updated);
              widget.onChanged?.call();
            }
          },
          child: _row(
            context,
            LucideIcons.lock,
            l.metaPermissions,
            _entry.mode!,
          ),
        ),
      if (_entry.modified != null)
        _row(
          context,
          LucideIcons.calendarClock,
          l.metaModified,
          _entry.modified!.toLocal().toString(),
        ),
      if (_entry.created != null)
        _row(
          context,
          LucideIcons.calendar,
          l.metaCreated,
          _entry.created!.toLocal().toString(),
        ),
      _row(
        context,
        LucideIcons.link,
        l.metaSymlink,
        _entry.isSymlink ? (_entry.symlinkTarget ?? l.yesLabel) : l.noLabel,
      ),
      if (!_entry.isDir) _checksumRow(context),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String? value,
  ) {
    if (value == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isFav =
        _entry.isDir &&
        (ref
                .watch(favoritesProvider)
                .valueOrNull
                ?.any(
                  (f) => f.hostId == widget.host.id && f.path == _entry.path,
                ) ??
            false);

    // Quick-action circle row (the 4 most common taps) + a plain list below
    // for everything else — the Google Photos/WhatsApp file-sheet shape.
    // Metadata isn't in here at all; it's behind the "Details" row.
    final previewable = !_entry.isDir && isPreviewable(_entry);
    final quick = <GradientActionCircle>[
      if (_entry.isDir)
        GradientActionCircle(
          icon: LucideIcons.star,
          label:
              isFav
                  ? context.l10n.unfavoriteButton
                  : context.l10n.favoriteButton,
          gradient: const [Colors.amber, Color(0xFFB8860B)],
          onTap: () => _toggleFavorite(context, isFav),
        )
      else if (previewable)
        GradientActionCircle(
          icon: LucideIcons.eye,
          label: context.l10n.previewButton,
          gradient: [Colors.blue.shade400, Colors.blue.shade800],
          onTap: () => _preview(context),
        )
      else if (!_entry.isDir)
        GradientActionCircle(
          icon: LucideIcons.externalLink,
          label: context.l10n.openWithButton,
          gradient: [Colors.blue.shade400, Colors.blue.shade800],
          onTap: () => _openWith(context),
        ),
      if (_entry.isDir)
        GradientActionCircle(
          icon: LucideIcons.filePen,
          label: context.l10n.renameButton,
          gradient: [Colors.blue.shade400, Colors.blue.shade800],
          onTap: () => _rename(context),
        )
      else
        GradientActionCircle(
          icon: LucideIcons.download,
          label: context.l10n.downloadButton,
          gradient: [Colors.green.shade400, Colors.green.shade800],
          onTap: () => _download(context),
        ),
      if (_entry.isDir)
        GradientActionCircle(
          icon: LucideIcons.copy,
          label: context.l10n.duplicateButton,
          gradient: [Colors.purple.shade300, Colors.purple.shade700],
          onTap: () => _duplicate(context),
        )
      else
        GradientActionCircle(
          icon: LucideIcons.share,
          label: context.l10n.shareTooltip,
          gradient: [Colors.purple.shade300, Colors.purple.shade700],
          onTap: () => _share(context),
        ),
      GradientActionCircle(
        icon: LucideIcons.trash2,
        label: context.l10n.deleteButton,
        gradient: [Colors.red.shade400, Colors.red.shade800],
        onTap: () => _delete(context),
      ),
    ];

    final more = <ActionListTile>[
      if (previewable)
        ActionListTile(
          icon: LucideIcons.externalLink,
          label: context.l10n.openWithButton,
          onTap: () => _openWith(context),
        ),
      if (!_entry.isDir)
        ActionListTile(
          icon: LucideIcons.link,
          label: context.l10n.shareLinkButton,
          onTap: () => _shareLink(context),
        ),
      if (!_entry.isDir)
        ActionListTile(
          icon: LucideIcons.qrCode,
          label: context.l10n.sendViaQrButton,
          onTap: () => _sendViaQr(context),
        ),
      if (!_entry.isDir && isExtractableArchive(_entry.name))
        ActionListTile(
          icon: LucideIcons.archive,
          label: context.l10n.extractHereButton,
          onTap: () => _extract(context),
        ),
      if (!_entry.isDir)
        ActionListTile(
          icon: LucideIcons.filePen,
          label: context.l10n.renameButton,
          onTap: () => _rename(context),
        ),
      if (!_entry.isDir)
        ActionListTile(
          icon: LucideIcons.copy,
          label: context.l10n.duplicateButton,
          onTap: () => _duplicate(context),
        ),
      ActionListTile(
        icon: LucideIcons.info,
        label: context.l10n.detailsButton,
        onTap: () => _showDetails(context),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuickActionRow(actions: quick),
        const SizedBox(height: Spacing.md),
        ActionListCard(children: more),
      ],
    );
  }

  /// Metadata is a secondary destination, not part of the primary action
  /// sheet — matches Google Drive/Files' "File info" pattern so the main
  /// sheet never needs scrolling to reach Preview/Download/etc.
  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => SafeArea(
            child: SingleChildScrollView(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.surfaceContainerLow,
                  borderRadius: Radii.sheetTopR,
                ),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: SheetGrabber()),
                    const SizedBox(height: Spacing.md),
                    Text(
                      context.l10n.detailsButton,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: Spacing.md),
                    _buildMetaSection(sheetContext),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _checksumRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_checksum != null) {
      return _row(context, LucideIcons.tag, 'SHA-256', _checksum);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        children: [
          Icon(LucideIcons.tag, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 100,
            child: Text(
              'SHA-256',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_checksumLoading)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: _computeChecksum,
              child: Text(
                'Compute',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _computeChecksum() async {
    setState(() => _checksumLoading = true);
    try {
      final sum = await widget.client.checksum(_entry.path);
      if (mounted) setState(() => _checksum = sum);
    } catch (e) {
      if (mounted) showError(context, 'Checksum failed: ${humanizeError(e)}');
    } finally {
      if (mounted) setState(() => _checksumLoading = false);
    }
  }

  void _toggleFavorite(BuildContext context, bool wasFavorite) {
    ref
        .read(favoritesProvider.notifier)
        .toggle(
          Favorite(
            hostId: widget.host.id,
            path: _entry.path,
            label: folderLabel(_entry.path),
          ),
        );
    if (wasFavorite) {
      showInfo(context, context.l10n.removedFavorite(_entry.name));
    } else {
      showSuccess(context, context.l10n.addedFavorite(_entry.name));
    }
  }

  Future<void> _preview(BuildContext context) async {
    await openPreview(
      context,
      entry: _entry,
      host: widget.host,
      client: widget.client,
      siblings: widget.siblings,
      onChanged: widget.onChanged,
    );
  }

  Future<void> _download(BuildContext context) async {
    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/${_entry.name}';
    ref
        .read(transferQueueProvider.notifier)
        .enqueue(
          TransferTask.download(
            remotePath: _entry.path,
            localPath: localPath,
            host: widget.host,
          ),
        );
    if (context.mounted) {
      Navigator.pop(context);
      showInfo(context, context.l10n.downloadingFile(_entry.name));
    }
  }

  Future<void> _openWith(BuildContext context) async {
    final actions = PreviewActions(
      entry: _entry,
      host: widget.host,
      client: widget.client,
    );
    await actions.openWith(context);
  }

  Future<void> _share(BuildContext context) async {
    final actions = PreviewActions(
      entry: _entry,
      host: widget.host,
      client: widget.client,
    );
    await actions.share(context);
  }

  /// Mints a one-time share link and opens [ShareLinkSheet] to show it.
  ///
  /// Deliberately not gated on a client-side "is sharing enabled" check —
  /// the agent's `allowSharing` setting is the single source of truth. If
  /// it's off, the mint call 403s and that's surfaced as a normal error.
  Future<void> _shareLink(BuildContext context) async {
    try {
      final link = await widget.client.mintShareLink(_entry.path);
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ShareSheet(client: widget.client, link: link),
      );
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.shareLinkFailed(humanizeError(e)));
      }
    }
  }

  /// Shows a QR code another phone (already paired to this same agent) can
  /// scan to fetch this file directly with its own credentials — see
  /// `qr_scan_screen.dart` for the receiving side.
  Future<void> _sendViaQr(BuildContext context) async {
    final fp = widget.host.certFingerprint;
    if (fp == null) {
      showError(context, context.l10n.qrHandoffNoFingerprint);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => QrGenerateSheet(
            certFingerprint: fp,
            path: _entry.path,
            name: _entry.name,
          ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: _entry.name);
    final newName = await showShadDialog<String>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(ctx.l10n.renameButton),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(ctx.l10n.renameButton),
              ),
            ],
            child: ShadInput(
              controller: ctrl,
              autofocus: true,
              placeholder: Text(ctx.l10n.newNameLabel),
            ),
          ),
    );
    if (newName == null || newName == _entry.name || !context.mounted) return;
    try {
      final dst = renameDestination(_entry.path, newName);
      final updated = await widget.client.rename(_entry.path, dst);
      if (mounted) setState(() => _entry = updated);
      widget.onChanged?.call();
      if (context.mounted) {
        showSuccess(context, context.l10n.renamedTo(newName));
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.renameFailed(humanizeError(e)));
      }
    }
  }

  Future<void> _duplicate(BuildContext context) async {
    try {
      final path = _entry.path;
      // Parent directory of the entry, preserving the path's separator style.
      final sep = path.contains('\\') ? '\\' : '/';
      final idx = path.lastIndexOf(sep);
      final parentDir = idx <= 0 ? sep : path.substring(0, idx);
      // duplicate:true makes an auto-renamed sibling ("name (1).ext"), so this
      // never collides with the original.
      final res = await widget.client.copy([path], parentDir, duplicate: true);
      final ok = res.results.isNotEmpty && res.results.first.ok;
      if (!ok) {
        if (context.mounted) {
          showError(context, context.l10n.couldNotDuplicate(_entry.name));
        }
        return;
      }
      widget.onChanged?.call();
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSuccess(context, context.l10n.duplicatedFile(_entry.name));
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.duplicateFailed(humanizeError(e)));
      }
    }
  }

  /// Extracts this archive into its own parent directory, then refreshes the
  /// listing so the unpacked items appear alongside it.
  Future<void> _extract(BuildContext context) async {
    try {
      final path = _entry.path;
      final sep = path.contains('\\') ? '\\' : '/';
      final idx = path.lastIndexOf(sep);
      final parentDir = idx <= 0 ? sep : path.substring(0, idx);
      await widget.client.extract(path, parentDir);
      widget.onChanged?.call();
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSuccess(context, context.l10n.extractedFile(_entry.name));
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.extractFailed(humanizeError(e)));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    // null = cancel, false = trash (default), true = permanent.
    final permanent = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(ctx.l10n.deleteTitle),
            description: Text(ctx.l10n.moveToTrashConfirm(_entry.name)),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.deleteForeverButton),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.moveToTrashButton),
              ),
            ],
          ),
    );
    if (permanent == null || !context.mounted) return;
    try {
      final name = _entry.name;
      await widget.client.delete([_entry.path], permanent: permanent);
      widget.onChanged?.call();
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSuccess(
          context,
          permanent
              ? context.l10n.deletedName(name)
              : context.l10n.movedToTrashName(name),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.deleteFailed(humanizeError(e)));
      }
    }
  }
}

/// Whether [name] looks like an archive the agent can extract — matches the
/// formats `/fs/extract` supports (`.zip`, `.tar.gz`, `.tgz`). Case-insensitive.
bool isExtractableArchive(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.zip') ||
      lower.endsWith('.tar.gz') ||
      lower.endsWith('.tgz');
}
