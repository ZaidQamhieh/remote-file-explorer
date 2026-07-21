import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/recent_searches.dart';
import '../../core/storage/saved_searches.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/state_views.dart';
import '../explorer/explorer_state.dart' show buildPathStack, folderLabel;
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

  SearchMode _searchMode = SearchMode.substring;

  String _query = '';
  bool _loading = false;
  String? _error;

  /// Raw results from the last search, before [_filterAndSort] is applied.
  List<Entry> _rawResults = const [];
  bool _truncated = false;
  bool _timeBudgetHit = false;

  bool get _isGlob =>
      _searchMode == SearchMode.glob ||
      _searchMode == SearchMode.regex ||
      isGlobQuery(_query);

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
        q: queryForMode(q, _searchMode),
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
        _error = humanizeError(e);
      });
    } catch (e) {
      if (!mounted || _query != q) return;
      setState(() {
        _loading = false;
        _error = humanizeError(e);
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
            searchMode: _searchMode,
          ),
    );
    if (result == null) return;
    setState(() => _searchMode = result.searchMode);
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
    final scheme = Theme.of(context).colorScheme;
    // The mockup's `.appbar`: back iconbtn, a flex-1 `.searchbar` pill, and a
    // filter iconbtn — a plain padded row, not a Material `AppBar`.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  _IconBtn(
                    icon: LucideIcons.arrowLeft,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
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
                                hintText: context.l10n.searchHint,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: _onChanged,
                              onSubmitted: _onSubmitted,
                            ),
                          ),
                          if (_controller.text.isNotEmpty) ...[
                            Pressable(
                              onTap: () => _saveCurrentSearch(context),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  LucideIcons.bookmarkPlus,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Pressable(
                              onTap: () {
                                _controller.clear();
                                _onChanged('');
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  LucideIcons.x,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilterButton(
                    activeCount: _activeFilterCount,
                    onPressed: _openFiltersSheet,
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.md),
                  child: _ScopePill(
                    searchFromHere: _searchFromHere,
                    currentPath: widget.currentPath,
                    onTap: _openFiltersSheet,
                  ),
                ),
                Expanded(
                  child: CategoryChipsRow(
                    selected: _selectedCategories,
                    onToggle: _toggleCategory,
                  ),
                ),
              ],
            ),
            if (_isGlob) const GlobIndicator(),
            if (_truncated || _timeBudgetHit)
              TruncationBanner(
                truncated: _truncated,
                timeBudgetHit: _timeBudgetHit,
                limit: _results.length,
              ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCurrentSearch(BuildContext context) async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final nameCtl = TextEditingController(text: q);
    final name = await showShadDialog<String>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(ctx.l10n.saveSearch),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx, nameCtl.text.trim()),
                child: Text(ctx.l10n.saveButton),
              ),
            ],
            child: ShadInput(
              controller: nameCtl,
              placeholder: Text(ctx.l10n.savedSearchName),
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(savedSearchesProvider.notifier)
        .add(SavedSearch(name: name, query: q));
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) {
      return _RecentAndSavedSearches(
        onSelectRecent: _selectRecent,
        onSelectSaved: _selectRecent,
      );
    }
    if (_loading) {
      return const _SearchSkeletonList();
    }
    if (_error != null) {
      return ErrorRetryCard(
        message: context.l10n.searchFailed(_error!),
        onRetry: () => _runSearch(_query),
      );
    }
    if (_results.isEmpty) {
      return CenteredMessage(
        icon: LucideIcons.searchX,
        message: context.l10n.noResultsFor(_query),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(
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
              SearchResultTile(
                entry: _results[i],
                query: _query,
                highlight: !_isGlob,
                onTap: () => _openResult(_results[i]),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Tappable pill showing the active search scope (opens the filter sheet) —
/// keeps the "where am I actually searching" cost visible up front instead
/// of buried in the filter sheet, since an unnoticed wide scope was the main
/// driver behind "search feels slow".
class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.searchFromHere,
    required this.currentPath,
    required this.onTap,
  });

  final bool searchFromHere;
  final String currentPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        searchFromHere
            ? folderLabel(currentPath)
            : context.l10n.searchingEverywhere;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Brand.seed, Brand.accent],
          ),
          boxShadow: [
            BoxShadow(
              color: Brand.seed.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searchFromHere ? LucideIcons.folder : LucideIcons.globe,
              size: 15,
              color: Colors.white,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder rows shown while a search is in flight, replacing a bare
/// centered spinner — the screen keeps its list shape instead of going
/// blank, which reads as "working" rather than "frozen" on a slow search.
class _SearchSkeletonList extends StatefulWidget {
  const _SearchSkeletonList();

  @override
  State<_SearchSkeletonList> createState() => _SearchSkeletonListState();
}

class _SearchSkeletonListState extends State<_SearchSkeletonList> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8,
      itemBuilder:
          (context, i) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                const _ShimmerBox(width: 40, height: 40),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(height: 12, width: i.isEven ? 180 : 130),
                      const SizedBox(height: Spacing.xs),
                      const _ShimmerBox(height: 10, width: 90),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

/// A single placeholder block with a moving highlight sweep — the standard
/// skeleton-loading treatment (LinkedIn/YouTube-style), which reads as
/// "actively working" far more than a static gray block or opacity pulse.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerHigh;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shift = _controller.value * 3 - 1.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment(-1 + shift, 0),
              end: Alignment(1 + shift, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

class _RecentAndSavedSearches extends ConsumerWidget {
  const _RecentAndSavedSearches({
    required this.onSelectRecent,
    required this.onSelectSaved,
  });

  final ValueChanged<String> onSelectRecent;
  final ValueChanged<String> onSelectSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedSearchesProvider).valueOrNull ?? const [];
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        if (saved.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              context.l10n.savedSearches,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.09,
              ),
            ),
          ),
          for (final s in saved)
            Pressable(
              onTap: () => onSelectSaved(s.query),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: Spacing.md,
                ),
                child: Row(
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
                        LucideIcons.bookmark,
                        size: 19,
                        color: Brand.seed,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.query,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Pressable(
                      onTap:
                          () => ref
                              .read(savedSearchesProvider.notifier)
                              .remove(s.name),
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.xs),
                        child: Icon(
                          LucideIcons.x,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
        ],
        RecentSearchesView(onSelect: onSelectRecent),
      ],
    );
  }
}

/// The mockup's `.iconbtn`: 34x34, 19px svg, no background until pressed.
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
