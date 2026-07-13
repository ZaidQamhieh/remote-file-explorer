import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/models/trash_entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
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
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        children: [
          GroupedCard(
            padded: false,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: Spacing.md,
                    endIndent: Spacing.md,
                    color: scheme.outlineVariant,
                  ),
                _tile(context, items[i]),
              ],
            ],
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
          Icon(LucideIcons.trash2, size: 64, color: c.outline),
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
    return ListTile(
      leading: Icon(
        item.isDir ? LucideIcons.folder : LucideIcons.file,
        color: item.isDir ? Colors.amber : scheme.onSurfaceVariant,
      ),
      title: Text(item.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'restore') _restore(item);
          if (v == 'delete') _deleteForever(item);
        },
        itemBuilder:
            (ctx) => [
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: const Icon(LucideIcons.archiveRestore),
                  title: Text(ctx.l10n.restoreButton),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const Icon(LucideIcons.trash2),
                  title: Text(ctx.l10n.deleteForeverButton),
                ),
              ),
            ],
      ),
      onTap: () => _restore(item),
    );
  }
}
