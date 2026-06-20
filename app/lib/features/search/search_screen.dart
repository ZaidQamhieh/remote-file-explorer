import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/recent_searches.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_state.dart' show buildPathStack;
import 'search_logic.dart';
import 'search_types.dart';
import 'widgets/category_chips_row.dart';
import 'widgets/centered_message.dart';
import 'widgets/filter_button.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/glob_indicator.dart';
import 'widgets/recent_searches_view.dart';
import 'widgets/search_result_tile.dart';
import 'widgets/truncation_banner.dart';

export 'search_types.dart';

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

  /// `true` = include entries that file-visibility prefs would otherwise
  /// hide (`core/storage/visibility_prefs.dart`); `false` (default) =
  /// filter them out of results, same as the explorer listing.
  bool _includeHidden = false;

  String _query = '';
  bool _loading = false;
  String? _error;

  /// Raw results from the last search, before [_filterAndSort] is applied.
  List<Entry> _rawResults = const [];
  bool _truncated = false;
  bool _timeBudgetHit = false;

  bool get _isGlob => isGlobQuery(_query);

  /// [_rawResults] sorted by relevance and (unless [_includeHidden])
  /// filtered through the same file-visibility prefs as the explorer
  /// listing.
  List<Entry> get _results {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final prefs = settings.resolveVisibility(widget.host.id);
    return filterSearchResults(
      _rawResults,
      prefs,
      includeHidden: _includeHidden,
    );
  }

  /// Number of active (non-default) filters, shown as a badge on the tune
  /// icon. The scope toggle is intentionally excluded — it's always visible.
  int get _activeFilterCount =>
      _selectedCategories.length +
      (_sizePreset != SizePreset.any ? 1 : 0) +
      (_datePreset != DatePreset.any ? 1 : 0) +
      (_includeHidden ? 1 : 0);

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _runSearch(value),
    );
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

    _cancelToken?.cancel();

    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _rawResults = const [];
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
        types:
            _selectedCategories.isEmpty
                ? null
                : _selectedCategories.map((c) => c.apiValue).toList(),
        minSize: _sizePreset.minBytes,
        modifiedAfter: _datePreset.resolve(DateTime.now()),
        cancelToken: token,
      );
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _rawResults = sortByRelevance(result.entries, q);
        _truncated = result.truncated;
        _timeBudgetHit = result.timeBudgetHit;
      });
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
    required bool includeHidden,
  }) {
    setState(() {
      _sizePreset = sizePreset;
      _datePreset = datePreset;
      _searchFromHere = searchFromHere;
      _includeHidden = includeHidden;
    });
    if (_query.isNotEmpty) _runSearch(_query);
  }

  Future<void> _openFiltersSheet() async {
    final result = await showModalBottomSheet<FilterSheetResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => FilterSheet(
            sizePreset: _sizePreset,
            datePreset: _datePreset,
            searchFromHere: _searchFromHere,
            includeHidden: _includeHidden,
            currentPath: widget.currentPath,
          ),
    );
    if (result == null) return;
    _applyFilters(
      sizePreset: result.sizePreset,
      datePreset: result.datePreset,
      searchFromHere: result.searchFromHere,
      includeHidden: result.includeHidden,
    );
  }

  void _selectRecent(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _onSubmitted(query);
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
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.l10n.searchHint,
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: context.l10n.clearTooltip,
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
          FilterButton(
            activeCount: _activeFilterCount,
            onPressed: _openFiltersSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          CategoryChipsRow(
            selected: _selectedCategories,
            onToggle: _toggleCategory,
          ),
          if (_isGlob) const GlobIndicator(),
          if (_truncated || _timeBudgetHit)
            TruncationBanner(
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
      return RecentSearchesView(onSelect: _selectRecent);
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
        message: context.l10n.searchFailed(_error!),
        onRetry: () => _runSearch(_query),
      );
    }
    if (_results.isEmpty) {
      return CenteredMessage(
        icon: Icons.search_off,
        message: context.l10n.noResultsFor(_query),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final entry = _results[i];
        return SearchResultTile(
          entry: entry,
          query: _query,
          highlight: !_isGlob,
          onTap: () => _openResult(entry),
        );
      },
    );
  }
}
