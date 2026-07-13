import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_state.dart' show buildPathStack;
import '../search/widgets/search_result_tile.dart';
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
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.md,
              ),
              children: [
                GroupedCard(
                  padded: false,
                  children: [
                    for (int i = 0; i < entries.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      SearchResultTile(
                        entry: entries[i],
                        query: '',
                        highlight: false,
                        onTap: () => _openResult(entries[i]),
                      ),
                    ],
                  ],
                ),
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
