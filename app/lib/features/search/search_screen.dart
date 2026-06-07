import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_state.dart' show buildPathStack;

/// Full-screen search UI for files and folders on [host].
///
/// Pop with the tapped [Entry]'s parent directory path to let the caller
/// navigate the explorer there (see [ExplorerSearchResult]).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.host,
    required this.client,
    required this.currentPath,
  });

  final Host host;
  final AgentClient client;

  /// The explorer's current directory — used as the default search root
  /// when "search from here" is enabled.
  final String currentPath;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  /// `true` = constrain search to [widget.currentPath]; `false` = search
  /// every allowed root on the agent.
  bool _searchFromHere = true;

  String _query = '';
  bool _loading = false;
  String? _error;
  List<Entry> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(value));
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    _runSearch(value);
  }

  Future<void> _runSearch(String value) async {
    final q = value.trim();
    setState(() {
      _query = q;
      _error = null;
    });
    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await widget.client.search(
        q: q,
        root: _searchFromHere ? widget.currentPath : null,
      );
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _results = results;
      });
    } catch (e) {
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _toggleScope(bool fromHere) {
    setState(() => _searchFromHere = fromHere);
    if (_query.isNotEmpty) _runSearch(_query);
  }

  void _openResult(Entry entry) {
    final stack = buildPathStack(entry.path);
    // Parent directory: second-to-last element of the path stack, or the
    // entry's own path if it's already a top-level item.
    final parent = stack.length >= 2 ? stack[stack.length - 2] : entry.path;
    Navigator.of(context).pop(parent);
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
            hintText: 'Search files and folders…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _ScopeToggle(
            fromHere: _searchFromHere,
            currentPath: widget.currentPath,
            onChanged: _toggleScope,
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.search,
        message: 'Type to search for files and folders by name.',
      );
    }
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (_error != null) {
      return ErrorRetryCard(
        message: 'Search failed: $_error',
        onRetry: () => _runSearch(_query),
      );
    }
    if (_results.isEmpty) {
      return _CenteredMessage(
        icon: Icons.search_off,
        message: 'No results for "$_query".',
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final entry = _results[i];
        return _SearchResultTile(entry: entry, onTap: () => _openResult(entry));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Scope toggle ("search from here" vs "search everywhere")
// ---------------------------------------------------------------------------

class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({
    required this.fromHere,
    required this.currentPath,
    required this.onChanged,
  });

  final bool fromHere;
  final String currentPath;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              fromHere ? 'Searching in: $currentPath' : 'Searching everywhere',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          const Text('From here'),
          Switch(
            value: !fromHere,
            onChanged: (everywhere) => onChanged(!everywhere),
          ),
          const Text('Everywhere'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result tile — mirrors the look of the explorer's entry list tiles
// (icon, name, size/date subtitle), plus the full path for context.
// ---------------------------------------------------------------------------

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.entry, required this.onTap});

  final Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      entry.path,
      if (!entry.isDir) _formatSize(entry.size),
      if (entry.modified != null) _formatDate(entry.modified!),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      leading: _resultIcon(entry),
      title: Text(
        entry.name,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: Text(
        subtitleParts.where((s) => s.isNotEmpty).join('  ·  '),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: entry.isDir ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}

Icon _resultIcon(Entry entry) {
  if (entry.isDir) {
    return const Icon(Icons.folder, color: Colors.amber);
  }
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('image/')) {
    return const Icon(Icons.image, color: Colors.blue);
  }
  if (mime.startsWith('video/')) {
    return const Icon(Icons.movie, color: Colors.purple);
  }
  if (mime.startsWith('audio/')) {
    return const Icon(Icons.music_note, color: Colors.green);
  }
  if (mime.contains('pdf')) {
    return const Icon(Icons.picture_as_pdf, color: Colors.red);
  }
  if (mime.contains('zip') || mime.contains('archive')) {
    return const Icon(Icons.folder_zip, color: Colors.orange);
  }
  if (mime.startsWith('text/') || mime.contains('json')) {
    return const Icon(Icons.description, color: Colors.teal);
  }
  return const Icon(Icons.insert_drive_file);
}

// ---------------------------------------------------------------------------
// Empty / error / hint state
// ---------------------------------------------------------------------------

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: Spacing.sm + Spacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers (mirrors explorer_screen's private helpers)
// ---------------------------------------------------------------------------

String _formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';
