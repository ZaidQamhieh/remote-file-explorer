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

  /// Bumped on every [_search] call; a host's result is only applied if it's
  /// still the current generation when it arrives — otherwise a slow
  /// response for an old query could land after (and clobber) a newer
  /// query's results (PR-32).
  int _generation = 0;

  /// A host that hasn't answered within this long is treated as failed
  /// rather than blocking every other host's results from appearing
  /// (previously `Future.wait` waited for the single slowest host before
  /// showing anything).
  static const _perHostTimeout = Duration(seconds: 10);

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _generation++;
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
    final gen = ++_generation;
    setState(() {
      _searching = true;
      _results = [];
      _failedHosts.clear();
    });

    final perHost = widget.hosts.map((host) async {
      try {
        final client = await ref.read(clientProvider(host.id).future);
        final result = await client.search(q: query).timeout(_perHostTimeout);
        if (!mounted || gen != _generation) return;
        setState(() {
          _results.addAll(result.entries.map((e) => CrossHostResult(host, e)));
        });
      } catch (_) {
        if (!mounted || gen != _generation) return;
        setState(() => _failedHosts.add(host.id));
      }
    });

    // Each host already streamed its own results in above as it finished;
    // this just waits for all of them to know when to stop showing the
    // "searching" spinner.
    await Future.wait(perHost);
    if (mounted && gen == _generation) {
      setState(() => _searching = false);
    }
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
