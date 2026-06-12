import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
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
import 'widgets/favorites_sheet.dart';
import 'widgets/selection_bar.dart';
import 'widgets/sort_button.dart';

class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({super.key, required this.host});

  final Host host;

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  ExplorerArg get _arg => (hostId: widget.host.id, rootPath: '/');

  ExplorerNotifier get _notifier =>
      ref.read(explorerProvider(_arg).notifier);

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
      canPop: state.atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _notifier.popDirectory();
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

  AppBar _buildAppBar(
      BuildContext context, ExplorerState state, bool isFav, AgentClient client) {
    return AppBar(
      leading: state.atRoot
          ? null
          : BackButton(onPressed: () => _notifier.popDirectory()),
      title: BreadcrumbBar(
        state: state,
        notifier: _notifier,
        onMoveInto: (dragged, dest) =>
            _moveInto(context, client, dragged, dest),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => _openSearch(context, state, client),
        ),
        IconButton(
          icon: Icon(isFav ? Icons.star : Icons.star_border),
          color: isFav ? Colors.amber : null,
          tooltip: isFav ? 'Remove favorite' : 'Favorite this folder',
          onPressed: () => _toggleFavorite(context, state, isFav),
        ),
        IconButton(
          icon: const Icon(Icons.bookmarks_outlined),
          tooltip: 'Favorites',
          onPressed: () => _showFavorites(context),
        ),
        IconButton(
          icon: Icon(state.gridView ? Icons.list : Icons.grid_view),
          tooltip: state.gridView ? 'List view' : 'Grid view',
          onPressed: _notifier.toggleView,
        ),
        SortButton(sort: state.sort, onSort: _notifier.setSort),
        IconButton(
          icon: const Icon(Icons.file_upload_outlined),
          tooltip: 'Transfers',
          onPressed: () => _showTransfers(context),
        ),
      ],
    );
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

  Widget _buildBody(
      BuildContext context, ExplorerState state, AgentClient client) {
    // First load with nothing cached yet → lightweight skeleton.
    if (state.loading && state.entries.isEmpty) {
      return const ListingSkeleton();
    }
    // Hard error with no cached entries to fall back on → retry card.
    if (state.error != null && state.entries.isEmpty) {
      return ErrorRetryCard(message: state.error!, onRetry: _notifier.refresh);
    }
    // Empty (non-error) directory → friendly empty view.
    if (!state.loading && state.entries.isEmpty && state.error == null) {
      return RefreshIndicator(
        onRefresh: _notifier.refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            EmptyFolderView(),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (state.offline) const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _notifier.refresh,
            child: state.gridView
                ? _buildGrid(context, state, client)
                : _buildList(context, state, client),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
      BuildContext context, ExplorerState state, AgentClient client) {
    final entries = state.sortedEntries;
    final showLoadMore = state.hasMore;
    final itemCount = entries.length + (showLoadMore ? 1 : 0);
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (i >= entries.length) {
          _notifier.loadMore();
          return _LoadMoreIndicator(loading: state.loadingMore);
        }
        final entry = entries[i];
        return AppearListItem(
          index: i,
          child: EntryTile(
            entry: entry,
            selected: state.selected.contains(entry.path),
            multiSelect: state.multiSelect,
            onTap: () => _onEntryTap(context, entry, client),
            onLongPress: () => _notifier.toggleSelect(entry.path),
            onSelect: () => _notifier.toggleSelect(entry.path),
            onMoveInto: (dragged, dest) =>
                _moveInto(context, client, dragged, dest),
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
    final entries = state.sortedEntries;
    final showLoadMore = state.hasMore;
    final itemCount = entries.length + (showLoadMore ? 1 : 0);
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
        if (i >= entries.length) {
          _notifier.loadMore();
          return _LoadMoreIndicator(loading: state.loadingMore);
        }
        final entry = entries[i];
        return AppearListItem(
          index: i,
          child: EntryGridCell(
            entry: entry,
            client: client,
            selected: state.selected.contains(entry.path),
            multiSelect: state.multiSelect,
            onTap: () => _onEntryTap(context, entry, client),
            onLongPress: () => _notifier.toggleSelect(entry.path),
            onMoveInto: (dragged, dest) =>
                _moveInto(context, client, dragged, dest),
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
