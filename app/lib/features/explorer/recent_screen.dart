import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/entry_leading.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart' show SectionLabel;
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_state.dart' show buildPathStack;
import '../search/widgets/truncation_banner.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Lists the most recently modified files across [host], newest first.
///
/// Pops with the tapped [Entry]'s parent directory path so the caller (the
/// explorer screen) can navigate there — same convention as [SearchScreen].
class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key, required this.host, required this.client});

  final Host host;
  final AgentClient client;

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  List<Entry>? _entries;
  bool _timeBudgetHit = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await widget.client.recent();
      if (mounted) {
        setState(() {
          _entries = result.entries;
          _timeBudgetHit = result.timeBudgetHit;
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

  void _openResult(Entry entry) {
    final stack = buildPathStack(entry.path);
    final parent = stack.length >= 2 ? stack[stack.length - 2] : entry.path;
    Navigator.of(context).pop(parent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: ScreenHeader(context.l10n.recentTitle),
      ),
      body: _buildBody(context, _entries),
    );
  }

  Widget _buildBody(BuildContext context, List<Entry>? entries) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorRetryCard(message: _error!, onRetry: _load);
    }
    if (entries == null || entries.isEmpty) {
      return _emptyView(context);
    }
    // Mockup groups Recent by "Today"/"Yesterday" section labels — bucket by
    // calendar day vs. now. Anything older falls into "Earlier" (the mockup
    // only illustrates the two most-recent buckets).
    final buckets = <String, List<Entry>>{};
    final now = DateTime.now();
    for (final e in entries) {
      final modified = e.modified?.toLocal();
      final String bucket;
      if (modified == null) {
        bucket = 'Earlier';
      } else {
        final today = DateTime(now.year, now.month, now.day);
        final modifiedDay = DateTime(
          modified.year,
          modified.month,
          modified.day,
        );
        final days = today.difference(modifiedDay).inDays;
        if (days <= 0) {
          bucket = 'Today';
        } else if (days == 1) {
          bucket = 'Yesterday';
        } else {
          bucket = 'Earlier';
        }
      }
      (buckets[bucket] ??= []).add(e);
    }

    return Column(
      children: [
        if (_timeBudgetHit)
          TruncationBanner(
            truncated: false,
            timeBudgetHit: true,
            limit: entries.length,
            message: context.l10n.recentTimedOut,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              children: [
                for (final label in ['Today', 'Yesterday', 'Earlier'])
                  if (buckets[label] case final bucketEntries?) ...[
                    SectionLabel(label),
                    for (final (i, entry) in bucketEntries.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: Spacing.md),
                      AppearListItem(
                        index: i,
                        child: _RecentRow(
                          entry: entry,
                          hostLabel: widget.host.label,
                          onTap: () => _openResult(entry),
                        ),
                      ),
                    ],
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.history, size: 64, color: c.outline),
          const SizedBox(height: 12),
          Text(
            context.l10n.recentIsEmpty,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.recentEmptySubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A single Recent row — mockup's flat `.row` (category-tinted icon, title,
/// "{host} · modified &lt;relative&gt;" subtitle). Says "modified" rather than the
/// mockup's "opened": the agent has no access log (see repo `CLAUDE.md`,
/// "there is no audit log"), so this list is really "recently modified", not
/// "recently opened" — the subtitle is worded to match what the data
/// actually is instead of implying a feature that doesn't exist.
class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.entry,
    required this.hostLabel,
    required this.onTap,
  });

  final Entry entry;
  final String hostLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modified = entry.modified;
    final subtitle =
        modified != null
            ? '$hostLabel  ·  modified ${formatRelative(modified.toLocal())}'
            : hostLabel;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: figmaIconBg(entry),
                borderRadius: Radii.smR,
              ),
              alignment: Alignment.center,
              child: EntryLeading(entry: entry, size: 18),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
