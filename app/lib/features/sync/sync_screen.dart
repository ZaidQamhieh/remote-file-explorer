import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/storage/sync_rules.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
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
    final result = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: const Text('Add Sync Rule'),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Remote Path'),
                const SizedBox(height: Spacing.xs),
                ShadInput(
                  controller: remoteCtrl,
                  autofocus: true,
                  placeholder: const Text('/photos'),
                ),
                const SizedBox(height: Spacing.sm),
                const Text('Local Folder'),
                const SizedBox(height: Spacing.xs),
                ShadInput(
                  controller: localCtrl,
                  placeholder: const Text('/storage/emulated/0/Sync/photos'),
                ),
              ],
            ),
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
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: const Text('Delete Sync Rule'),
            description: const Text('Delete this sync rule?'),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ShadButton.destructive(
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
      if (mounted) showError(context, humanizeError(e));
    } finally {
      client?.close();
      if (mounted) setState(() => _syncing.remove(rule.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Sync')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  // The mockup's info card explaining what a sync pair does —
                  // `.card` with `--primary-tint` bg and no border.
                  Container(
                    padding: const EdgeInsets.all(Spacing.md2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: Radii.cardR,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.refreshCw,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Keeps a phone folder and a host path identical, '
                            'both directions, whenever both are online.',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  const SectionLabel('Sync pairs'),
                  if (_rules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                      child: Text(
                        'No sync pairs yet',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    GroupedCard(
                      padded: false,
                      children: [
                        for (int i = 0; i < _rules.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: Spacing.md,
                              endIndent: Spacing.md,
                              color: scheme.outlineVariant,
                            ),
                          _SyncRuleTile(
                            rule: _rules[i],
                            progress: _syncing[_rules[i].id],
                            isSyncing: _syncing.containsKey(_rules[i].id),
                            onToggle: () => _toggleEnabled(_rules[i]),
                            onSync: () => _syncNow(_rules[i]),
                            onDelete: () => _deleteRule(_rules[i]),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: Spacing.md),
                  _GhostBlockButton(
                    label: 'Add sync pair',
                    icon: LucideIcons.plus,
                    onTap: _addRule,
                  ),
                ],
              ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block`: full-width, `surface-2`
/// background, 1px border, text then a trailing icon.
class _GhostBlockButton extends StatelessWidget {
  const _GhostBlockButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: Radii.smR,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, size: 16, color: scheme.onSurface),
          ],
        ),
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
        child: Icon(LucideIcons.trash2, color: scheme.onError),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // we handle deletion in the callback
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Brand.seed.withValues(alpha: 0.14),
                borderRadius: Radii.smR,
              ),
              alignment: Alignment.center,
              child: const Icon(
                LucideIcons.refreshCw,
                size: 18,
                color: Brand.seed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.remotePath,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    rule.localPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'JetBrains Mono',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          progressText ?? lastSyncText,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSyncing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Pressable(
                          onTap: rule.enabled ? onSync : null,
                          child: Opacity(
                            opacity: rule.enabled ? 1 : 0.4,
                            child: Icon(
                              LucideIcons.refreshCw,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Pressable(onTap: onToggle, child: _SyncSwitch(value: rule.enabled)),
          ],
        ),
      ),
    );
  }
}

/// The mockup's `.switch`: 42x25 pill track, 19x19 thumb — the tap is wired
/// by the enclosing [Pressable].
class _SyncSwitch extends StatelessWidget {
  const _SyncSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 25,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
        border: Border.all(
          color: value ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
