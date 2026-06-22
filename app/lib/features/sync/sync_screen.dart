import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/storage/sync_rules.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import 'sync_runner.dart';

/// Screen listing sync rules with add / delete / toggle / sync-now actions.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key, required this.hostId});
  final String hostId;

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  late SyncRuleStore _store;
  List<SyncRule> _rules = [];
  bool _loading = true;

  /// Tracks which rule ids are currently syncing.
  final Map<String, SyncProgress?> _syncing = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _store = SyncRuleStore(prefs);
    setState(() {
      _rules =
          _store.listRules().where((r) => r.hostId == widget.hostId).toList();
      _loading = false;
    });
  }

  void _reload() {
    setState(() {
      _rules =
          _store.listRules().where((r) => r.hostId == widget.hostId).toList();
    });
  }

  Future<void> _addRule() async {
    final remoteCtrl = TextEditingController();
    final localCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add Sync Rule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: remoteCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Remote Path',
                    hintText: '/photos',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: localCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Local Folder',
                    hintText: '/storage/emulated/0/Sync/photos',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add'),
              ),
            ],
          ),
    );
    if (result != true) return;
    final remote = remoteCtrl.text.trim();
    final local = localCtrl.text.trim();
    if (remote.isEmpty || local.isEmpty) return;

    final rule = SyncRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      hostId: widget.hostId,
      remotePath: remote,
      localPath: local,
    );
    await _store.saveRule(rule);
    _reload();
  }

  Future<void> _deleteRule(SyncRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Sync Rule'),
            content: const Text('Delete this sync rule?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _store.deleteRule(rule.id);
    _reload();
  }

  Future<void> _toggleEnabled(SyncRule rule) async {
    await _store.saveRule(rule.copyWith(enabled: !rule.enabled));
    _reload();
  }

  Future<void> _syncNow(SyncRule rule) async {
    if (_syncing.containsKey(rule.id)) return; // already running
    setState(() => _syncing[rule.id] = null);

    AgentClient? client;
    try {
      client = await buildClientForHost(ref.read, widget.hostId);
      final runner = SyncRunner();
      final count = await runner.run(
        client,
        rule,
        onProgress: (p) {
          if (mounted) setState(() => _syncing[rule.id] = p);
        },
      );
      await _store.saveRule(rule.copyWith(lastSync: DateTime.now()));
      _reload();
      if (mounted) {
        showSuccess(context, 'Synced $count files');
      }
    } catch (e) {
      if (mounted) showError(context, '$e');
    } finally {
      client?.close();
      if (mounted) setState(() => _syncing.remove(rule.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Rules')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        tooltip: 'Add Sync Rule',
        child: const Icon(Icons.add),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _rules.isEmpty
              ? const Center(child: Text('No sync rules yet'))
              : ListView.builder(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: _rules.length,
                itemBuilder: (context, index) {
                  final rule = _rules[index];
                  return _SyncRuleTile(
                    rule: rule,
                    progress: _syncing[rule.id],
                    isSyncing: _syncing.containsKey(rule.id),
                    onToggle: () => _toggleEnabled(rule),
                    onSync: () => _syncNow(rule),
                    onDelete: () => _deleteRule(rule),
                  );
                },
              ),
    );
  }
}

class _SyncRuleTile extends StatelessWidget {
  const _SyncRuleTile({
    required this.rule,
    required this.progress,
    required this.isSyncing,
    required this.onToggle,
    required this.onSync,
    required this.onDelete,
  });

  final SyncRule rule;
  final SyncProgress? progress;
  final bool isSyncing;
  final VoidCallback onToggle;
  final VoidCallback onSync;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastSyncText =
        rule.lastSync != null
            ? 'Last sync: ${formatDate(rule.lastSync!)}'
            : 'Never synced';
    final progressText =
        progress != null
            ? 'Syncing ${progress!.current}/${progress!.total}...'
            : null;

    return Dismissible(
      key: ValueKey(rule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Spacing.md),
        color: scheme.error,
        child: Icon(Icons.delete, color: scheme.onError),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // we handle deletion in the callback
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.remotePath,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rule.localPath,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: rule.enabled, onChanged: (_) => onToggle()),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Text(
                    progressText ?? lastSyncText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (isSyncing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: rule.enabled ? onSync : null,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync Now'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
