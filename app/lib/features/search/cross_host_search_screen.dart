import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/ui/format.dart';
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

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
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
    setState(() {
      _searching = true;
      _results = [];
      _failedHosts.clear();
    });

    final futures = widget.hosts.map((host) async {
      try {
        final client = await ref.read(clientProvider(host.id).future);
        final result = await client.search(q: query);
        return result.entries.map((e) => CrossHostResult(host, e)).toList();
      } catch (_) {
        _failedHosts.add(host.id);
        return <CrossHostResult>[];
      }
    });

    final allResults = await Future.wait(futures);
    if (mounted) {
      setState(() {
        _results = allResults.expand((r) => r).toList();
        _searching = false;
      });
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
          decoration: const InputDecoration(
            hintText: 'Search all hosts...',
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
            Text('Searching ${widget.hosts.length} hosts...'),
          ],
        ),
      );
    }

    if (_controller.text.trim().length < 2) {
      return const Center(child: Text('Type to search across all hosts'));
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No results'),
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
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (ctx, i) {
              final r = _results[i];
              return ListTile(
                leading: Icon(
                  r.entry.isDir ? LucideIcons.folder : LucideIcons.file,
                ),
                title: Text(r.entry.name),
                subtitle: Text('${r.host.label} · ${r.entry.path}'),
                trailing:
                    r.entry.size != null
                        ? Text(formatSize(r.entry.size))
                        : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
