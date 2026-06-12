import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/storage/recent_searches.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/format.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_state.dart' show buildPathStack;
import 'search_logic.dart';

/// Selectable entry-type categories for the search filter chips, mapped to
/// the server's `types` query parameter values.
enum SearchCategory {
  folder('Folders', Icons.folder, 'folder'),
  image('Images', Icons.image, 'image'),
  video('Videos', Icons.movie, 'video'),
  audio('Audio', Icons.music_note, 'audio'),
  document('Docs', Icons.description, 'document'),
  archive('Archives', Icons.folder_zip, 'archive'),
  other('Other', Icons.insert_drive_file, 'other');

  const SearchCategory(this.label, this.icon, this.apiValue);

  final String label;
  final IconData icon;
  final String apiValue;
}

/// Minimum-size filter presets, mapped to the server's `minSize` (bytes).
enum SizePreset {
  any('Any size', null),
  mb1('> 1 MB', 1024 * 1024),
  mb10('> 10 MB', 10 * 1024 * 1024),
  mb100('> 100 MB', 100 * 1024 * 1024),
  gb1('> 1 GB', 1024 * 1024 * 1024);

  const SizePreset(this.label, this.minBytes);

  final String label;
  final int? minBytes;
}

/// Modified-date filter presets. [resolve] computes the `modifiedAfter`
/// timestamp at query time (relative to "now").
enum DatePreset {
  any('Any time', null),
  last24h('Last 24 hours', Duration(hours: 24)),
  last7d('Last 7 days', Duration(days: 7)),
  last30d('Last 30 days', Duration(days: 30)),
  thisYear('This year', null);

  const DatePreset(this.label, this.lookback);

  final String label;
  final Duration? lookback;

  /// Computes the `modifiedAfter` bound for this preset, or `null` for
  /// [DatePreset.any].
  DateTime? resolve(DateTime now) {
    if (this == DatePreset.any) return null;
    if (this == DatePreset.thisYear) return DateTime(now.year, 1, 1);
    return now.subtract(lookback!);
  }
}

/// Full-screen search UI for files and folders on [host].
///
/// Pop with the tapped [Entry]'s parent directory path to let the caller
/// navigate the explorer there (see [ExplorerSearchResult]).
class SearchScreen extends ConsumerStatefulWidget {
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
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancelToken;

  /// `true` = constrain search to [widget.currentPath]; `false` = search
  /// every allowed root on the agent.
  bool _searchFromHere = true;

  Set<SearchCategory> _selectedCategories = {};
  SizePreset _sizePreset = SizePreset.any;
  DatePreset _datePreset = DatePreset.any;

  String _query = '';
  bool _loading = false;
  String? _error;
  List<Entry> _results = const [];
  bool _truncated = false;
  bool _timeBudgetHit = false;

  bool get _isGlob => isGlobQuery(_query);

  /// Number of active (non-default) filters, shown as a badge on the tune
  /// icon. The scope toggle is intentionally excluded — it's always visible.
  int get _activeFilterCount =>
      _selectedCategories.length +
      (_sizePreset != SizePreset.any ? 1 : 0) +
      (_datePreset != DatePreset.any ? 1 : 0);

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(value));
    // Refresh recent-searches visibility immediately when the field becomes
    // empty/non-empty.
    setState(() {});
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

    // Cancel any in-flight request before starting a new one.
    _cancelToken?.cancel();

    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
        _truncated = false;
        _timeBudgetHit = false;
      });
      return;
    }

    final token = CancelToken();
    _cancelToken = token;

    setState(() => _loading = true);
    try {
      final result = await widget.client.search(
        q: q,
        root: _searchFromHere ? widget.currentPath : null,
        types: _selectedCategories.isEmpty
            ? null
            : _selectedCategories.map((c) => c.apiValue).toList(),
        minSize: _sizePreset.minBytes,
        modifiedAfter: _datePreset.resolve(DateTime.now()),
        cancelToken: token,
      );
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _results = sortByRelevance(result.entries, q);
        _truncated = result.truncated;
        _timeBudgetHit = result.timeBudgetHit;
      });
      // Only record searches that actually ran with a non-empty query.
      unawaited(ref.read(recentSearchesProvider.notifier).record(q));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } catch (e) {
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _toggleCategory(SearchCategory category, bool selected) {
    setState(() {
      if (selected) {
        _selectedCategories = {..._selectedCategories, category};
      } else {
        _selectedCategories = {..._selectedCategories}..remove(category);
      }
    });
    if (_query.isNotEmpty) _runSearch(_query);
  }

  void _applyFilters({
    required SizePreset sizePreset,
    required DatePreset datePreset,
    required bool searchFromHere,
  }) {
    setState(() {
      _sizePreset = sizePreset;
      _datePreset = datePreset;
      _searchFromHere = searchFromHere;
    });
    if (_query.isNotEmpty) _runSearch(_query);
  }

  Future<void> _openFiltersSheet() async {
    final result = await showModalBottomSheet<_FilterSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        sizePreset: _sizePreset,
        datePreset: _datePreset,
        searchFromHere: _searchFromHere,
        currentPath: widget.currentPath,
      ),
    );
    if (result == null) return;
    _applyFilters(
      sizePreset: result.sizePreset,
      datePreset: result.datePreset,
      searchFromHere: result.searchFromHere,
    );
  }

  void _selectRecent(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _onSubmitted(query);
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
          _FilterButton(
            activeCount: _activeFilterCount,
            onPressed: _openFiltersSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _CategoryChipsRow(
            selected: _selectedCategories,
            onToggle: _toggleCategory,
          ),
          if (_isGlob) const _GlobIndicator(),
          if (_truncated || _timeBudgetHit) _TruncationBanner(
            truncated: _truncated,
            timeBudgetHit: _timeBudgetHit,
            limit: _results.length,
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) {
      return _RecentSearchesView(onSelect: _selectRecent);
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
        return _SearchResultTile(
          entry: entry,
          query: _query,
          highlight: !_isGlob,
          onTap: () => _openResult(entry),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Filter button (tune icon + active-filter count badge)
// ---------------------------------------------------------------------------

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(Icons.tune);
    return IconButton(
      tooltip: 'Search filters',
      onPressed: onPressed,
      icon: activeCount > 0
          ? Badge(label: Text('$activeCount'), child: icon)
          : icon,
    );
  }
}

// ---------------------------------------------------------------------------
// Category chips row (multi-select, maps to `types`)
// ---------------------------------------------------------------------------

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({required this.selected, required this.onToggle});

  final Set<SearchCategory> selected;
  final void Function(SearchCategory category, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        itemCount: SearchCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: Spacing.xs),
        itemBuilder: (context, i) {
          final category = SearchCategory.values[i];
          final isSelected = selected.contains(category);
          return FilterChip(
            label: Text(category.label),
            avatar: Icon(category.icon, size: 18),
            selected: isSelected,
            onSelected: (value) => onToggle(category, value),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glob-mode indicator chip
// ---------------------------------------------------------------------------

class _GlobIndicator extends StatelessWidget {
  const _GlobIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: const Icon(Icons.pattern, size: 18),
          label: const Text('Glob pattern'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Truncation banner
// ---------------------------------------------------------------------------

class _TruncationBanner extends StatelessWidget {
  const _TruncationBanner({
    required this.truncated,
    required this.timeBudgetHit,
    required this.limit,
  });

  final bool truncated;
  final bool timeBudgetHit;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final message = truncated
        ? 'Showing first $limit results — refine your search.'
        : 'Search timed out — showing partial results.';
    return Material(
      color: c.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: c.onTertiaryContainer),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: c.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent searches (shown when the query field is empty)
// ---------------------------------------------------------------------------

class _RecentSearchesView extends ConsumerWidget {
  const _RecentSearchesView({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider).valueOrNull ?? const [];

    if (recent.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.search,
        message: 'Type to search for files and folders by name.',
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.md, Spacing.sm, Spacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        for (final query in recent)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(query),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove',
              onPressed: () =>
                  ref.read(recentSearchesProvider.notifier).remove(query),
            ),
            onTap: () => onSelect(query),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filters bottom sheet
// ---------------------------------------------------------------------------

class _FilterSheetResult {
  const _FilterSheetResult({
    required this.sizePreset,
    required this.datePreset,
    required this.searchFromHere,
  });

  final SizePreset sizePreset;
  final DatePreset datePreset;
  final bool searchFromHere;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.sizePreset,
    required this.datePreset,
    required this.searchFromHere,
    required this.currentPath,
  });

  final SizePreset sizePreset;
  final DatePreset datePreset;
  final bool searchFromHere;
  final String currentPath;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SizePreset _sizePreset = widget.sizePreset;
  late DatePreset _datePreset = widget.datePreset;
  late bool _searchFromHere = widget.searchFromHere;

  void _apply() {
    Navigator.of(context).pop(_FilterSheetResult(
      sizePreset: _sizePreset,
      datePreset: _datePreset,
      searchFromHere: _searchFromHere,
    ));
  }

  void _reset() {
    setState(() {
      _sizePreset = SizePreset.any;
      _datePreset = DatePreset.any;
      _searchFromHere = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Search filters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text('File size', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.xs,
              children: [
                for (final preset in SizePreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _sizePreset == preset,
                    onSelected: (_) => setState(() => _sizePreset = preset),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text('Date modified', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.xs,
              children: [
                for (final preset in DatePreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _datePreset == preset,
                    onSelected: (_) => setState(() => _datePreset = preset),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text('Search scope', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _searchFromHere
                        ? 'Searching in: ${widget.currentPath}'
                        : 'Searching everywhere',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                const Text('From here'),
                Switch(
                  value: !_searchFromHere,
                  onChanged: (everywhere) =>
                      setState(() => _searchFromHere = !everywhere),
                ),
                const Text('Everywhere'),
              ],
            ),
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result tile — mirrors the look of the explorer's entry list tiles
// (icon, name, size/date subtitle), plus the parent path for context, with
// the matched substring highlighted in the name.
// ---------------------------------------------------------------------------

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.entry,
    required this.query,
    required this.highlight,
    required this.onTap,
  });

  final Entry entry;
  final String query;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      entry.path,
      if (!entry.isDir) formatSize(entry.size),
      if (entry.modified != null) formatDate(entry.modified!),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      leading: _resultIcon(entry),
      title: _highlightedName(context),
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

  Widget _highlightedName(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final range = highlight ? highlightRange(entry.name, query) : null;
    if (range == null) {
      return Text(
        entry.name,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    final highlightStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.bold,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: entry.name.substring(0, range.start)),
          TextSpan(
            text: entry.name.substring(range.start, range.end),
            style: highlightStyle,
          ),
          TextSpan(text: entry.name.substring(range.end)),
        ],
      ),
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
