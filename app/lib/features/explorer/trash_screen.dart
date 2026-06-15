import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/host.dart';
import '../../core/models/trash_entry.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
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
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _restore(TrashEntry item) async {
    try {
      await widget.client.restoreTrash([item.id]);
      _changed = true;
      if (mounted) showSuccess(context, 'Restored "${item.name}"');
      await _load();
    } catch (e) {
      if (mounted) showError(context, 'Restore failed: $e');
    }
  }

  Future<void> _deleteForever(TrashEntry item) async {
    final ok = await _confirm(
      title: 'Delete forever?',
      body: 'Permanently delete "${item.name}"? This cannot be undone.',
      action: 'Delete forever',
    );
    if (ok != true) return;
    try {
      await widget.client.emptyTrash(ids: [item.id]);
      if (mounted) showSuccess(context, 'Deleted "${item.name}" forever');
      await _load();
    } catch (e) {
      if (mounted) showError(context, 'Delete failed: $e');
    }
  }

  Future<void> _emptyAll() async {
    final ok = await _confirm(
      title: 'Empty trash?',
      body:
          'Permanently delete all ${_items?.length ?? 0} item(s)? '
          'This cannot be undone.',
      action: 'Empty trash',
    );
    if (ok != true) return;
    try {
      await widget.client.emptyTrash();
      if (mounted) showSuccess(context, 'Trash emptied');
      await _load();
    } catch (e) {
      if (mounted) showError(context, 'Empty failed: $e');
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
                child: const Text('Cancel'),
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
          title: const Text('Trash'),
          actions: [
            if (items != null && items.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Empty trash',
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _tile(context, items[i]),
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, size: 64, color: c.outline),
          const SizedBox(height: 12),
          Text(
            'Trash is empty',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Deleted items appear here and can be restored.',
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
      if (item.deletedAt != null) 'deleted ${formatRelative(item.deletedAt!)}',
      if (!item.isDir && item.size != null) formatSize(item.size),
    ].join(' · ');
    return ListTile(
      leading: Icon(
        item.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
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
            (_) => const [
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.restore_rounded),
                  title: Text('Restore'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_forever_outlined),
                  title: Text('Delete forever'),
                ),
              ),
            ],
      ),
      onTap: () => _restore(item),
    );
  }
}
