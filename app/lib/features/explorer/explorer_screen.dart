import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/state_views.dart';
import '../search/search_screen.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_state.dart';
import 'explorer_state.dart';
import 'meta_sheet.dart';
import 'widgets/breadcrumb_bar.dart';
import 'widgets/create_menu.dart';
import 'widgets/entry_grid_cell.dart';
import 'widgets/entry_tile.dart';
import 'widgets/favorites_pin_row.dart';
import 'widgets/favorites_sheet.dart';
import 'widgets/selection_bar.dart';
import 'widgets/view_options_sheet.dart';

class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({
    super.key,
    required this.host,
    this.rootPath = '/',
    this.initialPath,
  });

  final Host host;

  /// Directory this explorer instance is rooted at — `/` for POSIX hosts, or
  /// a drive path (e.g. `C:\`) when opened from [DrivesView]. Determines
  /// [ExplorerState.atRoot], so popping at this directory exits the screen
  /// (back to the drive list, for Windows hosts).
  final String rootPath;

  /// If set, the explorer jumps straight to this path (e.g. a favorited
  /// folder on this drive) instead of showing [rootPath] itself.
  final String? initialPath;

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  ExplorerArg get _arg =>
      (hostId: widget.host.id, rootPath: widget.rootPath);

  ExplorerNotifier get _notifier =>
      ref.read(explorerProvider(_arg).notifier);

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialPath;
    if (initialPath != null && initialPath != widget.rootPath) {
      // Defer until after the provider's initial build/load is scheduled.
      Future.microtask(() => _notifier.jumpTo(initialPath));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientAsync = ref.watch(clientProvider(widget.host.id));
    final client = clientAsync.valueOrNull;
    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.host.label)),
        body: clientAsync.hasError
            ? Center(child: Text('Error: ${clientAsync.error}'))
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final state = ref.watch(explorerProvider(_arg));
    final favs = ref.watch(favoritesProvider).valueOrNull ?? const [];
    final isFav =
        favs.any((f) => f.hostId == widget.host.id && f.path == state.currentPath);

    return PopScope(
      canPop: state.atRoot && !state.multiSelect,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.multiSelect) {
          _notifier.clearSelection();
        } else {
          _notifier.popDirectory();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context, state, isFav, client),
        body: _buildBody(context, state, client),
        floatingActionButton:
            state.multiSelect ? null : _buildFab(context, state, client),
        bottomNavigationBar: state.multiSelect
            ? SelectionBar(
                state: state,
                notifier: _notifier,
                host: widget.host,
              )
            : null,
      ),
    );
  }

  /// App bar that morphs between the normal browsing bar and the selection
  /// contextual bar via a fadeThrough-style cross-fade (opacity + slight
  /// scale, [MotionDuration.medium], `easeOutCubic`) — Skia-safe, no blur.
  PreferredSizeWidget _buildAppBar(
      BuildContext context, ExplorerState state, bool isFav, AgentClient client) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 44),
      child: AnimatedSwitcher(
        duration: MotionDuration.medium,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: state.multiSelect
            ? _buildSelectionAppBar(context, state)
            : _buildBrowseAppBar(context, state, isFav, client),
      ),
    );
  }

  AppBar _buildBrowseAppBar(
      BuildContext context, ExplorerState state, bool isFav, AgentClient client) {
    return AppBar(
      key: const ValueKey('browse_app_bar'),
      leading: state.atRoot
          ? null
          : BackButton(onPressed: () => _notifier.popDirectory()),
      title: Text(
        folderLabel(state.currentPath),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Padding(
          padding: const EdgeInsets.only(left: Spacing.md, bottom: Spacing.xs),
          child: BreadcrumbBar(
            pathStack: state.pathStack,
            onNavigateTo: _notifier.navigateTo,
            onMoveInto: (dragged, dest) =>
                _moveInto(context, client, dragged, dest),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search',
          onPressed: () => _openSearch(context, state, client),
        ),
        IconButton(
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded),
          color: isFav ? Colors.amber : null,
          tooltip: isFav ? 'Remove favorite' : 'Favorite this folder',
          onPressed: () => _toggleFavorite(context, state, isFav),
        ),
        PopupMenuButton<_OverflowAction>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'More',
          onSelected: (action) => _onOverflowAction(context, state, action),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _OverflowAction.viewOptions,
              child: ListTile(
                leading: Icon(Icons.tune_rounded),
                title: Text('View options'),
              ),
            ),
            PopupMenuItem(
              value: _OverflowAction.favorites,
              child: ListTile(
                leading: Icon(Icons.bookmarks_outlined),
                title: Text('Favorites'),
              ),
            ),
            PopupMenuItem(
              value: _OverflowAction.transfers,
              child: ListTile(
                leading: Icon(Icons.file_upload_outlined),
                title: Text('Transfers'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Contextual action bar shown while one or more entries are selected:
  /// `✕  N selected   ⊞ select-all   ⋮ (invert)`.
  AppBar _buildSelectionAppBar(BuildContext context, ExplorerState state) {
    final allSelected = state.selected.length == state.entries.length &&
        state.entries.isNotEmpty;
    return AppBar(
      key: const ValueKey('selection_app_bar'),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Clear selection',
        onPressed: _notifier.clearSelection,
      ),
      title: Text(
        '${state.selected.length} selected',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      // Empty bottom matching the browse bar's breadcrumb row height, so the
      // fadeThrough cross-fade doesn't jump in size.
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(44),
        child: SizedBox.shrink(),
      ),
      actions: [
        IconButton(
          icon: Icon(allSelected
              ? Icons.deselect_rounded
              : Icons.select_all_rounded),
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed:
              allSelected ? _notifier.clearSelection : _notifier.selectAll,
        ),
        IconButton(
          icon: const Icon(Icons.flip_to_back_rounded),
          tooltip: 'Invert selection',
          onPressed: _notifier.invertSelection,
        ),
      ],
    );
  }

  void _onOverflowAction(
      BuildContext context, ExplorerState state, _OverflowAction action) {
    switch (action) {
      case _OverflowAction.viewOptions:
        ViewOptionsSheet.show(context, state: state, notifier: _notifier);
      case _OverflowAction.favorites:
        _showFavorites(context);
      case _OverflowAction.transfers:
        _showTransfers(context);
    }
  }

  void _toggleFavorite(
      BuildContext context, ExplorerState state, bool isFav) {
    ref.read(favoritesProvider.notifier).toggle(
          Favorite(
            hostId: widget.host.id,
            path: state.currentPath,
            label: folderLabel(state.currentPath),
          ),
        );
    if (isFav) {
      showInfo(context, 'Removed from favorites');
    } else {
      showSuccess(
          context, 'Added "${folderLabel(state.currentPath)}" to favorites');
    }
  }

  void _showFavorites(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FavoritesSheet(
        host: widget.host,
        onOpen: (path) {
          Navigator.pop(context);
          _notifier.jumpTo(path);
        },
      ),
    );
  }

  Future<void> _openSearch(
      BuildContext context, ExplorerState state, AgentClient client) async {
    final parentPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          host: widget.host,
          client: client,
          currentPath: state.currentPath,
        ),
      ),
    );
    if (parentPath != null) {
      _notifier.jumpTo(parentPath);
    }
  }

  void _showTransfers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TransferManagerSheet(),
    );
  }

  /// Pin row of favorited folders, shown above the listing only at the
  /// filesystem root (`state.atRoot`) when the host has favorites. Returns
  /// `null` (renders nothing) otherwise.
  Widget? _buildPinRow(BuildContext context, ExplorerState state) {
    if (!state.atRoot) return null;
    final favs = ref
        .watch(favoritesProvider)
        .valueOrNull
        ?.where((f) => f.hostId == widget.host.id)
        .toList();
    if (favs == null || favs.isEmpty) return null;
    return FavoritesPinRow(
      favorites: favs,
      onOpen: (fav) => _notifier.jumpTo(fav.path),
      onRemove: (fav) => _removeFavorite(context, fav),
    );
  }

  void _removeFavorite(BuildContext context, Favorite fav) {
    ref.read(favoritesProvider.notifier).remove(fav.hostId, fav.path);
    showInfo(context, 'Removed "${fav.label}" from favorites');
  }

  Widget _buildBody(
      BuildContext context, ExplorerState state, AgentClient client) {
    final pinRow = _buildPinRow(context, state);

    // First load with nothing cached yet → lightweight skeleton.
    if (state.loading && state.entries.isEmpty) {
      return Column(
        children: [
          if (pinRow != null) pinRow,
          const Expanded(child: ListingSkeleton()),
        ],
      );
    }
    // Hard error with no cached entries to fall back on → retry card.
    if (state.error != null && state.entries.isEmpty) {
      return Column(
        children: [
          if (pinRow != null) pinRow,
          Expanded(
            child: ErrorRetryCard(
                message: state.error!, onRetry: _notifier.refresh),
          ),
        ],
      );
    }
    // Empty (non-error) directory → friendly empty view.
    if (!state.loading && state.entries.isEmpty && state.error == null) {
      return Column(
        children: [
          if (pinRow != null) pinRow,
          Expanded(
            child: RefreshIndicator(
              onRefresh: _notifier.refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyFolderView(),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final density =
        ref.watch(viewPrefsProvider).valueOrNull?.density ??
            EntryDensity.comfortable;

    return Column(
      children: [
        if (pinRow != null) pinRow,
        if (state.offline) const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _notifier.refresh,
            child: state.gridView
                ? _buildGrid(context, state, client)
                : _buildList(context, state, client, density),
          ),
        ),
      ],
    );
  }

  /// Paths of this host's favorited folders, for the tile star badge.
  Set<String> _favoritePaths() => ref
      .watch(favoritesProvider)
      .valueOrNull
      ?.where((f) => f.hostId == widget.host.id)
      .map((f) => f.path)
      .toSet() ??
      const {};

  Widget _buildList(BuildContext context, ExplorerState state,
      AgentClient client, EntryDensity density) {
    final entries = state.displayEntries;
    final showLoadMore = state.hasMore;
    final showHiddenFooter = state.hiddenCount > 0;
    final itemCount =
        entries.length + (showLoadMore ? 1 : 0) + (showHiddenFooter ? 1 : 0);
    final favoritePaths = _favoritePaths();
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (i >= entries.length + (showLoadMore ? 1 : 0)) {
          return HiddenItemsFooter(
            count: state.hiddenCount,
            revealed: state.showHidden,
            onToggle: _notifier.toggleShowHidden,
          );
        }
        if (i >= entries.length) {
          _notifier.loadMore();
          return _LoadMoreIndicator(loading: state.loadingMore);
        }
        final entry = entries[i];
        final hidden = state.hiddenPaths.contains(entry.path);
        return AppearListItem(
          index: i,
          child: Opacity(
            opacity: hidden ? 0.55 : 1,
            child: EntryTile(
              entry: entry,
              selected: state.selected.contains(entry.path),
              multiSelect: state.multiSelect,
              density: density,
              isFavorite: favoritePaths.contains(entry.path),
              onTap: () => _onEntryTap(context, entry, client),
              onLongPress: () => _notifier.toggleSelect(entry.path),
              onSelect: () => _notifier.toggleSelect(entry.path),
              onMoveInto: (dragged, dest) =>
                  _moveInto(context, client, dragged, dest),
              onShowMeta: entry.isDir
                  ? () => _showMeta(context, entry, client)
                  : null,
            ),
          ),
        );
      },
    );
  }

  /// Moves a dragged [dragged] entry into the [destFolder] directory, then
  /// refreshes the listing and reports the outcome.
  Future<void> _moveInto(BuildContext context, AgentClient client,
      Entry dragged, String destFolder) async {
    try {
      await client.move([dragged.path], destFolder);
      await _notifier.refresh();
      if (context.mounted) showSuccess(context, 'Moved ${dragged.name}');
    } catch (e) {
      if (context.mounted) {
        showError(context, 'Move failed: $e',
            onRetry: () => _moveInto(context, client, dragged, destFolder));
      }
    }
  }

  Widget _buildGrid(
      BuildContext context, ExplorerState state, AgentClient client) {
    final entries = state.displayEntries;
    final showLoadMore = state.hasMore;
    final showHiddenFooter = state.hiddenCount > 0;
    final itemCount =
        entries.length + (showLoadMore ? 1 : 0) + (showHiddenFooter ? 1 : 0);
    final favoritePaths = _favoritePaths();
    return GridView.builder(
      padding: const EdgeInsets.all(Spacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 144,
        mainAxisExtent: 132,
        crossAxisSpacing: Spacing.md,
        mainAxisSpacing: Spacing.md,
      ),
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (i >= entries.length + (showLoadMore ? 1 : 0)) {
          return HiddenItemsFooter(
            count: state.hiddenCount,
            revealed: state.showHidden,
            onToggle: _notifier.toggleShowHidden,
            compact: true,
          );
        }
        if (i >= entries.length) {
          _notifier.loadMore();
          return _LoadMoreIndicator(loading: state.loadingMore);
        }
        final entry = entries[i];
        final hidden = state.hiddenPaths.contains(entry.path);
        return AppearListItem(
          index: i,
          child: Opacity(
            opacity: hidden ? 0.55 : 1,
            child: EntryGridCell(
              entry: entry,
              client: client,
              selected: state.selected.contains(entry.path),
              multiSelect: state.multiSelect,
              isFavorite: favoritePaths.contains(entry.path),
              onTap: () => _onEntryTap(context, entry, client),
              onLongPress: () => _notifier.toggleSelect(entry.path),
              onMoveInto: (dragged, dest) =>
                  _moveInto(context, client, dragged, dest),
            ),
          ),
        );
      },
    );
  }

  void _onEntryTap(
      BuildContext context, Entry entry, AgentClient client) {
    if (ref.read(explorerProvider(_arg)).multiSelect) {
      _notifier.toggleSelect(entry.path);
      return;
    }
    if (entry.isDir) {
      _notifier.navigate(entry.path);
    } else {
      _showMeta(context, entry, client);
    }
  }

  void _showMeta(BuildContext context, Entry entry, AgentClient client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MetaSheet(
        entry: entry,
        host: widget.host,
        client: client,
        onChanged: _notifier.refresh,
      ),
    );
  }

  Widget _buildFab(
      BuildContext context, ExplorerState state, AgentClient client) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'fab_upload',
          tooltip: 'Upload file',
          onPressed: () => _pickAndUpload(context, state),
          child: const Icon(Icons.upload_file),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'fab_new',
          onPressed: () => _showCreateMenu(context),
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ],
    );
  }

  Future<void> _pickAndUpload(
      BuildContext context, ExplorerState state) async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) return;

    final remotePath = '${state.currentPath}/${picked.name}';
    ref.read(transferQueueProvider.notifier).enqueue(
          TransferTask.upload(
            localPath: localPath,
            remotePath: remotePath,
            host: widget.host,
          ),
        );

    if (context.mounted) {
      showInfo(context, 'Uploading ${picked.name}…');
    }
  }

  void _showCreateMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => CreateMenu(notifier: _notifier),
    );
  }
}

/// Actions available from the browse app bar's overflow (⋮) menu.
enum _OverflowAction { viewOptions, favorites, transfers }

// ---------------------------------------------------------------------------
// Pagination "load more" trailing item
// ---------------------------------------------------------------------------

/// Trailing tile shown at the end of the list/grid when a directory has more
/// pages. Becoming visible triggers [ExplorerNotifier.loadMore]; this just
/// renders the resulting spinner (or a quiet placeholder while the request
/// is still being kicked off).
class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.square(dimension: 24),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hidden-items reveal footer
// ---------------------------------------------------------------------------

/// Trailing tile shown at the end of the list/grid when [count] of the
/// current listing's entries are filtered by file-visibility prefs
/// (`core/storage/visibility_prefs.dart`). Tapping it flips the
/// per-screen [ExplorerState.showHidden] session override via [onToggle] —
/// this is the listing's primary "never make files silently unreachable"
/// affordance (see also the eye toggle in [ViewOptionsSheet]).
///
/// In [compact] mode (used inside [GridView] cells, which are fixed-size),
/// the label wraps onto two lines instead of a full-width row.
class HiddenItemsFooter extends StatelessWidget {
  const HiddenItemsFooter({
    super.key,
    required this.count,
    required this.revealed,
    required this.onToggle,
    this.compact = false,
  });

  /// Number of entries in the current listing hidden by visibility prefs.
  final int count;

  /// Whether hidden entries are currently revealed (at reduced opacity) for
  /// this session.
  final bool revealed;

  final VoidCallback onToggle;

  /// `true` when rendered as a [GridView] trailing cell instead of a
  /// full-width list row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = '$count hidden';
    final action = revealed ? 'Hide' : 'Show';
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final actionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        );

    if (compact) {
      return Center(
        child: InkWell(
          borderRadius: Radii.smR,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: Spacing.xs),
                Text(label, style: style, textAlign: TextAlign.center),
                Text(action, style: actionStyle, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Spacing.sm),
            Text('$label · ', style: style),
            Text(action, style: actionStyle),
          ],
        ),
      ),
    );
  }
}
