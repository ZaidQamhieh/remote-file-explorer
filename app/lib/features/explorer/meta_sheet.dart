import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/entry_leading.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../handoff/qr_generate_screen.dart';
import '../preview/preview.dart';
import '../preview/preview_actions.dart';
import '../share/share_sheet.dart';
import '../transfers/transfer_state.dart';
import 'explorer_state.dart' show folderLabel, renameDestination;
import 'widgets/chmod_dialog.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder:
          (_, controller) => Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: Radii.sheetTopR,
            ),
            child: CustomScrollView(
              controller: controller,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.md,
                      Spacing.lg,
                      Spacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildGrabber(context),
                        const SizedBox(height: Spacing.md),
                        _buildHeader(context),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.xl,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildMetaSection(context),
                      const SizedBox(height: Spacing.lg),
                      _buildActions(context),
                    ]),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildGrabber(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: badgeBg, borderRadius: Radii.cardR),
          alignment: Alignment.center,
          child: EntryLeading(entry: _entry, size: 30),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _entry.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
        ),
      ],
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
    final scheme = Theme.of(context).colorScheme;
    final isFav =
        _entry.isDir &&
        (ref
                .watch(favoritesProvider)
                .valueOrNull
                ?.any(
                  (f) => f.hostId == widget.host.id && f.path == _entry.path,
                ) ??
            false);

    // 3-column icon grid, matching the Figma FileActionSheet mockup. Same
    // per-entry-type gating as before (dirs only get Favorite/Rename/
    // Duplicate; extract is archive-only) — just laid out as grid cells
    // instead of a chip row + overflow menu.
    final cells = <_ActionCell>[
      if (_entry.isDir)
        _ActionCell(
          icon: LucideIcons.star,
          label:
              isFav
                  ? context.l10n.unfavoriteButton
                  : context.l10n.favoriteButton,
          tint: isFav ? Colors.amber : null,
          onTap: () => _toggleFavorite(context, isFav),
        ),
      if (!_entry.isDir && isPreviewable(_entry))
        _ActionCell(
          icon: LucideIcons.eye,
          label: context.l10n.previewButton,
          onTap: () => _preview(context),
        ),
      if (!_entry.isDir)
        _ActionCell(
          icon: LucideIcons.download,
          label: context.l10n.downloadButton,
          onTap: () => _download(context),
        ),
      if (!_entry.isDir)
        _ActionCell(
          icon: LucideIcons.share,
          label: context.l10n.shareTooltip,
          onTap: () => _share(context),
        ),
      if (!_entry.isDir)
        _ActionCell(
          icon: LucideIcons.externalLink,
          label: context.l10n.openWithButton,
          onTap: () => _openWith(context),
        ),
      if (!_entry.isDir)
        _ActionCell(
          icon: LucideIcons.link,
          label: context.l10n.shareLinkButton,
          onTap: () => _shareLink(context),
        ),
      if (!_entry.isDir)
        _ActionCell(
          icon: LucideIcons.qrCode,
          label: context.l10n.sendViaQrButton,
          onTap: () => _sendViaQr(context),
        ),
      if (!_entry.isDir && isExtractableArchive(_entry.name))
        _ActionCell(
          icon: LucideIcons.archive,
          label: context.l10n.extractHereButton,
          onTap: () => _extract(context),
        ),
      _ActionCell(
        icon: LucideIcons.filePen,
        label: context.l10n.renameButton,
        onTap: () => _rename(context),
      ),
      _ActionCell(
        icon: LucideIcons.copy,
        label: context.l10n.duplicateButton,
        onTap: () => _duplicate(context),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            borderRadius: Radii.cardR,
          ),
          child: ClipRRect(
            borderRadius: Radii.cardR,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
              childAspectRatio: 1.1,
              children: [for (final c in cells) _buildActionCell(context, c)],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Material(
          color: scheme.errorContainer.withValues(alpha: 0.5),
          borderRadius: Radii.cardR,
          child: InkWell(
            borderRadius: Radii.cardR,
            onTap: () => _delete(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.trash2, color: scheme.error, size: 20),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    context.l10n.deleteButton,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCell(BuildContext context, _ActionCell cell) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: cell.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs,
            vertical: Spacing.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(cell.icon, color: cell.tint ?? scheme.onSurfaceVariant),
              const SizedBox(height: Spacing.xs),
              Text(
                cell.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
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
      if (mounted) showError(context, 'Checksum failed: $e');
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
        showError(context, context.l10n.shareLinkFailed(e.toString()));
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
    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.renameButton),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: ctx.l10n.newNameLabel),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(ctx.l10n.renameButton),
              ),
            ],
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
        showError(context, context.l10n.renameFailed(e.toString()));
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
        showError(context, context.l10n.duplicateFailed(e.toString()));
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
        showError(context, context.l10n.extractFailed(e.toString()));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    // null = cancel, false = trash (default), true = permanent.
    final permanent = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.deleteTitle),
            content: Text(ctx.l10n.moveToTrashConfirm(_entry.name)),
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
        showError(context, context.l10n.deleteFailed(e.toString()));
      }
    }
  }
}

/// A single cell in the action grid built by [_MetaSheetState._buildActions].
class _ActionCell {
  const _ActionCell({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
}

/// Whether [name] looks like an archive the agent can extract — matches the
/// formats `/fs/extract` supports (`.zip`, `.tar.gz`, `.tgz`). Case-insensitive.
bool isExtractableArchive(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.zip') ||
      lower.endsWith('.tar.gz') ||
      lower.endsWith('.tgz');
}
