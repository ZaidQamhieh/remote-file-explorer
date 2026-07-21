import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/models/trash_entry.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';

/// Browser for the agent's trash: lists deleted items (newest first), restores
/// them to their original location, deletes individual items forever, or empties
/// the whole trash.
///
/// Pops `true` when anything was restored, so the caller (the explorer screen)
/// can refresh its listing — a restored item may reappear in the current folder.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key, required this.host, required this.client});

  final Host host;
  final AgentClient client;

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TrashEntry>? _items;
  String? _error;
  bool _loading = true;
  bool _changed = false; // a restore happened → caller should refresh

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.client.listTrash();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = humanizeError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _restore(TrashEntry item) async {
    try {
      await widget.client.restoreTrash([item.id]);
      _changed = true;
      if (mounted) showSuccess(context, context.l10n.restoredItem(item.name));
      await _load();
    } catch (e) {
      if (mounted) {
        showError(context, context.l10n.restoreFailed(humanizeError(e)));
      }
    }
  }

  Future<void> _deleteForever(TrashEntry item) async {
    final ok = await _confirm(
      title: context.l10n.deleteForeverTitle,
      body: context.l10n.deleteForeverConfirm(item.name),
      action: context.l10n.deleteForeverButton,
    );
    if (ok != true) return;
    try {
      await widget.client.emptyTrash(ids: [item.id]);
      if (mounted) showSuccess(context, context.l10n.deletedForever(item.name));
      await _load();
    } catch (e) {
      if (mounted) {
        showError(context, context.l10n.deleteFailed(humanizeError(e)));
      }
    }
  }

  Future<void> _emptyAll() async {
    final ok = await _confirm(
      title: context.l10n.emptyTrashTitle,
      body: context.l10n.emptyTrashBody(_items?.length ?? 0),
      action: context.l10n.emptyTrashTooltip,
    );
    if (ok != true) return;
    try {
      await widget.client.emptyTrash();
      if (mounted) showSuccess(context, context.l10n.trashEmptied);
      await _load();
    } catch (e) {
      if (mounted) {
        showError(context, context.l10n.emptyFailed(humanizeError(e)));
      }
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(title),
            description: Text(body),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(action),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: ScreenHeader(context.l10n.trashTitle),
          actions: [
            if (items != null && items.isNotEmpty)
              IconButton(
                icon: const Icon(LucideIcons.trash2),
                tooltip: context.l10n.emptyTrashTooltip,
                onPressed: _emptyAll,
              ),
          ],
        ),
        body: _buildBody(context, items),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TrashEntry>? items) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorRetryCard(message: _error!, onRetry: _load);
    }
    if (items == null || items.isEmpty) {
      return _emptyView(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          // Mockup's info card: trash isn't auto-purged, matching this
          // screen's actual retention (there's no TTL/auto-empty anywhere in
          // the agent's trash API — items sit here until acted on).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Container(
              padding: const EdgeInsets.all(Spacing.md2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: Radii.cardR,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      "Items stay here until you delete them yourself — "
                      "RFE doesn't auto-purge trash.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: Spacing.md,
                color: scheme.outlineVariant,
              ),
            AppearListItem(index: i, child: _tile(context, items[i])),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.sm,
            ),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _emptyAll,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: Text(context.l10n.emptyTrashTooltip),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GradientBlobHero(icon: LucideIcons.trash2, size: 120),
          const SizedBox(height: 12),
          Text(
            context.l10n.trashIsEmpty,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.trashEmptySubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, TrashEntry item) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = <String>[
      item.originalPath,
      if (item.deletedAt != null)
        context.l10n.deletedRelative(formatRelative(item.deletedAt!)),
      if (!item.isDir && item.size != null) formatSize(item.size),
    ].join(' · ');
    // Mockup fades every trashed row to the same neutral, un-tinted icon
    // (folder or file) regardless of type — a deleted item reads as inert,
    // not "still this category of file".
    return Opacity(
      opacity: 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: InkWell(
          onTap: () => _restore(item),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Radii.smR,
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.isDir ? LucideIcons.folder : LucideIcons.file,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, overflow: TextOverflow.ellipsis),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.archiveRestore),
                tooltip: context.l10n.restoreButton,
                onPressed: () => _restore(item),
              ),
              IconButton(
                icon: Icon(LucideIcons.trash2, color: scheme.error),
                tooltip: context.l10n.deleteForeverButton,
                onPressed: () => _deleteForever(item),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
