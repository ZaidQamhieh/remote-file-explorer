import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_screen.dart';
import '../explorer/explorer_state.dart' show buildPathStack;
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A single search result tagged with the [Host] it came from.
class CrossHostResult {
  const CrossHostResult(this.host, this.entry);
  final Host host;
  final Entry entry;
}

/// Searches all paired [hosts] simultaneously and merges results with a
/// per-result host badge.
class CrossHostSearchScreen extends ConsumerStatefulWidget {
  const CrossHostSearchScreen({super.key, required this.hosts});
  final List<Host> hosts;

  @override
  ConsumerState<CrossHostSearchScreen> createState() =>
      _CrossHostSearchScreenState();
}

class _CrossHostSearchScreenState extends ConsumerState<CrossHostSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<CrossHostResult> _results = [];
  bool _searching = false;
  final Set<String> _failedHosts = {};
  int _searchGeneration = 0;

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _searchGeneration++;
      setState(() {
        _results = [];
        _searching = false;
        _failedHosts.clear();
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query.trim()),
    );
  }

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _results = [];
      _failedHosts.clear();
    });

    if (widget.hosts.isEmpty) {
      setState(() => _searching = false);
      return;
    }

    var remaining = widget.hosts.length;
    final futures = widget.hosts.map((host) async {
      try {
        final client = await ref.read(clientProvider(host.id).future);
        final result = await client
            .search(q: query)
            .timeout(const Duration(seconds: 10));
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _results.addAll(
            result.entries.map((entry) => CrossHostResult(host, entry)),
          );
        });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _failedHosts.add(host.id));
      } finally {
        if (mounted && generation == _searchGeneration) {
          remaining--;
          if (remaining == 0) setState(() => _searching = false);
        }
      }
    });
    await Future.wait(futures);
  }

  void _openResult(CrossHostResult result) {
    final entry = result.entry;
    final stack = buildPathStack(entry.path);
    final rootPath =
        entry.isDir
            ? entry.path
            : stack.length >= 2
            ? stack[stack.length - 2]
            : entry.path;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExplorerScreen(host: result.host, rootPath: rootPath),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.l10n.crossHostSearchHint,
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_searching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(context.l10n.crossHostSearching(widget.hosts.length)),
          ],
        ),
      );
    }

    if (_controller.text.trim().length < 2) {
      return Center(child: Text(context.l10n.crossHostTypeToSearch));
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyFolderView(kind: EmptyStateKind.noMatches),
            if (_failedHosts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_failedHosts.length} host${_failedHosts.length == 1 ? '' : 's'} unreachable',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_failedHosts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '${_failedHosts.length} host${_failedHosts.length == 1 ? '' : 's'} unreachable',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              GroupedCard(
                padded: false,
                children: [
                  for (int i = 0; i < _results.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: Spacing.md,
                        endIndent: Spacing.md,
                        color: scheme.outlineVariant,
                      ),
                    ListTile(
                      onTap: () => _openResult(_results[i]),
                      leading: Icon(
                        _results[i].entry.isDir
                            ? LucideIcons.folder
                            : LucideIcons.file,
                      ),
                      title: Text(_results[i].entry.name),
                      subtitle: Text(
                        '${_results[i].host.label} · ${_results[i].entry.path}',
                      ),
                      trailing:
                          _results[i].entry.size != null
                              ? Text(formatSize(_results[i].entry.size))
                              : null,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
