import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import '../../core/ui/pressable.dart';
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
    final scheme = Theme.of(context).colorScheme;
    // The mockup's `.appbar`: back iconbtn + h2, then a `.searchbar` pill
    // below it — not a Material `AppBar`.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        LucideIcons.arrowLeft,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.l10n.crossHostSearchTitle,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.01,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: Radii.stadiumR,
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.search,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: context.l10n.crossHostSearchHint,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  context.l10n.crossHostUnreachableCount(_failedHosts.length),
                  style: TextStyle(fontSize: 12.5, color: scheme.error),
                ),
              ),
          ],
        ),
      );
    }

    final byHost = <Host, List<Entry>>{};
    for (final r in _results) {
      (byHost[r.host] ??= []).add(r.entry);
    }
    final failedHostObjs =
        widget.hosts.where((h) => _failedHosts.contains(h.id)).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Brand.seed.withValues(alpha: 0.14),
                borderRadius: Radii.stadiumR,
              ),
              child: Text(
                context.l10n.crossHostSearchingCount(byHost.length),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Brand.seed,
                ),
              ),
            ),
          ),
        ),
        for (final host in byHost.keys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Text(
              host.label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.09,
              ),
            ),
          ),
          for (final entry in byHost[host]!)
            _ResultRow(host: host, entry: entry),
        ],
        if (failedHostObjs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Column(
              children: [
                for (final host in failedHostObjs)
                  Opacity(
                    opacity: 0.6,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: Radii.lgR,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.monitor,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.l10n.crossHostOffline(host.label),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The mockup's `.row`: 38x38 tinted `.row-icon`, 14px/500 title, 11.5px
/// faint monospace subtitle (host label + path).
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.host, required this.entry});

  final Host host;
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDir = entry.isDir;
    final color = isDir ? Brand.amber : Brand.seed;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 18),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: Radii.smR,
            ),
            alignment: Alignment.center,
            child: Icon(
              isDir ? LucideIcons.folder : LucideIcons.file,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'JetBrains Mono',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entry.size != null) ...[
            const SizedBox(width: Spacing.sm),
            Text(
              formatSize(entry.size),
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
