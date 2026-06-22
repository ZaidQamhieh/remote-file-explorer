import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/favorites.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/l10n_ext.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/state_views.dart';
import '../search/search_screen.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_state.dart';
import '../transfers/widgets/mini_transfer_bar.dart';
import 'clipboard_state.dart';
import 'explorer_state.dart';
import 'meta_sheet.dart';
import 'trash_screen.dart';
import 'type_treemap_screen.dart';
import 'widgets/batch_rename_sheet.dart';
import 'widgets/batch_report.dart';
import 'widgets/browse_app_bar.dart';
import 'widgets/conflict_resolution_dialog.dart';
import 'widgets/create_menu.dart';
import 'widgets/entry_grid_cell.dart';
import 'widgets/entry_tile.dart';
import 'widgets/explorer_fab.dart';
import 'widgets/explorer_selection_app_bar.dart';
import 'widgets/favorites_pin_row.dart';
import 'widgets/favorites_sheet.dart';
import 'widgets/hidden_items_footer.dart';
import 'widgets/load_more_indicator.dart';
import 'widgets/selection_bar.dart';
import 'widgets/view_options_sheet.dart';

export 'widgets/hidden_items_footer.dart';

class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({
    super.key,
    required this.host,
    this.rootPath = '/',
    this.initialPath,
  });

  final Host host;
  final String rootPath;
  final String? initialPath;

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  ExplorerArg get _arg => (hostId: widget.host.id, rootPath: widget.rootPath);

  ExplorerNotifier get _notifier => ref.read(explorerProvider(_arg).notifier);

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialPath;
    if (initialPath != null && initialPath != widget.rootPath) {
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
        body:
            clientAsync.hasError
                ? Center(
                  child: Text(
                    context.l10n.errorLabel(clientAsync.error.toString()),
                  ),
                )
                : const Center(child: CircularProgressIndicator()),
      );
    }

    final state = ref.watch(explorerProvider(_arg));
    final favs = ref.watch(favoritesProvider).valueOrNull ?? const [];
    final isFav = favs.any(
      (f) => f.hostId == widget.host.id && f.path == state.currentPath,
    );

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
        body: Column(
          children: [
            Expanded(child: _buildBody(context, state, client)),
            const MiniTransferBar(),
          ],
        ),
        floatingActionButton:
            state.multiSelect
                ? null
                : ExplorerFab(
                  clipboard: ref.watch(clipboardProvider),
                  hostId: widget.host.id,
                  multiSelect: state.multiSelect,
                  onPaste:
                      () =>
                          _paste(context, state, ref.read(clipboardProvider)!),
                  onUpload: () => _pickAndUpload(context, state),
                  onNew: () => _showCreateMenu(context),
                ),
        bottomNavigationBar:
            state.multiSelect
                ? SelectionBar(
                  state: state,
                  notifier: _notifier,
                  host: widget.host,
                )
                : null,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ExplorerState state,
    bool isFav,
    AgentClient client,
  ) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 44),
      child: AnimatedSwitcher(
        duration: MotionDuration.medium,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder:
            (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                child: child,
              ),
            ),
        child:
            state.multiSelect
                ? ExplorerSelectionAppBar(
                  state: state,
                  onClose: _notifier.clearSelection,
                  onBatchRename: () => _batchRename(context, state),
                  onSelectAll: _notifier.selectAll,
                  onClearSelection: _notifier.clearSelection,
                  onInvertSelection: _notifier.invertSelection,
                )
                : BrowseAppBar(
                  state: state,
                  isFav: isFav,
                  sseConnected: state.sseConnected,
                  onBack: _notifier.popDirectory,
                  onNavigateTo: _notifier.navigateTo,
                  onMoveInto:
                      (dragged, dest) async =>
                          _moveInto(context, client, dragged, dest),
                  onSearch: () => _openSearch(context, state, client),
                  onToggleFavorite:
                      () => _toggleFavorite(context, state, isFav),
                  onOverflow:
                      (action) => _onOverflowAction(context, state, action),
                ),
      ),
    );
  }

  Future<void> _batchRename(BuildContext context, ExplorerState state) async {
    final paths = state.selected.toList();
    if (paths.isEmpty) return;
    final names = paths.map(basenameOf).toList();
    final newNames = await BatchRenameSheet.show(context, names);
    if (newNames == null || !context.mounted) return;
    final renames = [
      for (var i = 0; i < paths.length; i++)
        (path: paths[i], newName: newNames[i]),
    ];
    try {
      final res = await _notifier.batchRename(renames);
      _notifier.clearSelection();
      if (context.mounted) {
        await reportBatchResult(context, res, context.l10n.renamedLabel);
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.renameFailed(e.toString()));
      }
    }
  }

  void _onOverflowAction(
    BuildContext context,
    ExplorerState state,
    OverflowAction action,
  ) {
    switch (action) {
      case OverflowAction.viewOptions:
        ViewOptionsSheet.show(context, notifier: _notifier);
      case OverflowAction.favorites:
        _showFavorites(context);
      case OverflowAction.transfers:
        _showTransfers(context);
      case OverflowAction.trash:
        _openTrash(context);
      case OverflowAction.storageByType:
        _openStorageByType(context, state);
    }
  }

  Future<void> _openTrash(BuildContext context) async {
    final client = await ref.read(clientProvider(widget.host.id).future);
    if (!context.mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TrashScreen(host: widget.host, client: client),
      ),
    );
    if (changed == true) _notifier.refresh();
  }

  Future<void> _openStorageByType(
    BuildContext context,
    ExplorerState state,
  ) async {
    final client = await ref.read(clientProvider(widget.host.id).future);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => TypeTreemapScreen(
              hostId: widget.host.id,
              path: state.currentPath,
              client: client,
            ),
      ),
    );
  }

  void _toggleFavorite(BuildContext context, ExplorerState state, bool isFav) {
    ref
        .read(favoritesProvider.notifier)
        .toggle(
          Favorite(
            hostId: widget.host.id,
            path: state.currentPath,
            label: folderLabel(state.currentPath),
          ),
        );
    if (isFav) {
      showInfo(
        context,
        context.l10n.removedFavorite(folderLabel(state.currentPath)),
      );
    } else {
      showSuccess(
        context,
        context.l10n.addedFavorite(folderLabel(state.currentPath)),
      );
    }
  }

  void _showFavorites(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => FavoritesSheet(
            host: widget.host,
            onOpen: (path) {
              Navigator.pop(context);
              _notifier.jumpTo(path);
            },
          ),
    );
  }

  Future<void> _openSearch(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
  ) async {
    final parentPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => SearchScreen(
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

  Widget? _buildPinRow(BuildContext context, ExplorerState state) {
    if (!state.atRoot) return null;
    final favs =
        ref
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
    showInfo(context, context.l10n.removedFavorite(fav.label));
  }

  Widget _buildBody(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
  ) {
    final pinRow = _buildPinRow(context, state);

    if (state.loading && state.entries.isEmpty) {
      return Column(
        children: [
          if (pinRow != null) pinRow,
          const Expanded(child: ListingSkeleton()),
        ],
      );
    }
    if (state.error != null && state.entries.isEmpty) {
      return Column(
        children: [
          if (pinRow != null) pinRow,
          Expanded(
            child: ErrorRetryCard(
              message: state.error!,
              onRetry: _notifier.refresh,
            ),
          ),
        ],
      );
    }
    if (!state.loading && state.entries.isEmpty && state.error == null) {
      return Column(
        children: [
          if (pinRow != null) pinRow,
          Expanded(
            child: RefreshIndicator(
              onRefresh: _notifier.refresh,
              child: ListView(
                children: const [SizedBox(height: 120), EmptyFolderView()],
              ),
            ),
          ),
        ],
      );
    }

    final density =
        ref
            .watch(settingsProvider)
            .valueOrNull
            ?.resolveView(_arg.hostId)
            .density ??
        EntryDensity.comfortable;

    return Column(
      children: [
        if (pinRow != null) pinRow,
        if (state.offline) const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _notifier.refresh,
            child:
                state.gridView
                    ? _buildGrid(context, state, client)
                    : _buildList(context, state, client, density),
          ),
        ),
      ],
    );
  }

  Set<String> _favoritePaths() =>
      ref
          .watch(favoritesProvider)
          .valueOrNull
          ?.where((f) => f.hostId == widget.host.id)
          .map((f) => f.path)
          .toSet() ??
      const {};

  Widget _buildList(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
    EntryDensity density,
  ) {
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
          return LoadMoreIndicator(loading: state.loadingMore);
        }
        final entry = entries[i];
        final hidden = state.hiddenPaths.contains(entry.path);
        return AppearListItem(
          index: i,
          child: Opacity(
            opacity: hidden ? 0.55 : 1,
            child: EntryTile(
              entry: entry,
              client: client,
              selected: state.selected.contains(entry.path),
              multiSelect: state.multiSelect,
              density: density,
              isFavorite: favoritePaths.contains(entry.path),
              onTap: () => _onEntryTap(context, entry, client),
              onLongPress: () => _notifier.toggleSelect(entry.path),
              onSelect: () => _notifier.toggleSelect(entry.path),
              onMoveInto:
                  (dragged, dest) => _moveInto(context, client, dragged, dest),
              onShowMeta:
                  entry.isDir ? () => _showMeta(context, entry, client) : null,
            ),
          ),
        );
      },
    );
  }

  Future<void> _moveInto(
    BuildContext context,
    AgentClient client,
    Entry dragged,
    String destFolder,
  ) async {
    var duplicate = false;
    var overwrite = false;
    try {
      final colliding = await _notifier.collidingBasenames(destFolder, [
        dragged.path,
      ]);
      if (colliding.isNotEmpty) {
        if (!context.mounted) return;
        final resolution = await showConflictResolutionDialog(
          context,
          collidingCount: 1,
          totalCount: 1,
          destLabel: folderLabel(destFolder),
        );
        switch (resolution) {
          case ConflictResolution.cancel:
            return;
          case ConflictResolution.skip:
            if (context.mounted) {
              showInfo(
                context,
                context.l10n.itemExistsInFolder(
                  dragged.name,
                  folderLabel(destFolder),
                ),
              );
            }
            return;
          case ConflictResolution.keepBoth:
            duplicate = true;
          case ConflictResolution.overwrite:
            overwrite = true;
        }
      }
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          context.l10n.couldNotCheckFolder(
            folderLabel(destFolder),
            e.toString(),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    try {
      await client.move(
        [dragged.path],
        destFolder,
        duplicate: duplicate,
        overwrite: overwrite,
      );
      await _notifier.refresh();
      if (context.mounted) {
        showSuccess(context, context.l10n.movedFile(dragged.name));
      }
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          context.l10n.moveFailed(e.toString()),
          onRetry: () => _moveInto(context, client, dragged, destFolder),
        );
      }
    }
  }

  Widget _buildGrid(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
  ) {
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
          return LoadMoreIndicator(loading: state.loadingMore);
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
              hostId: widget.host.id,
              selected: state.selected.contains(entry.path),
              multiSelect: state.multiSelect,
              isFavorite: favoritePaths.contains(entry.path),
              onTap: () => _onEntryTap(context, entry, client),
              onLongPress: () => _notifier.toggleSelect(entry.path),
              onMoveInto:
                  (dragged, dest) => _moveInto(context, client, dragged, dest),
            ),
          ),
        );
      },
    );
  }

  void _onEntryTap(BuildContext context, Entry entry, AgentClient client) {
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
    final siblings = ref.read(explorerProvider(_arg)).displayEntries;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => MetaSheet(
            entry: entry,
            host: widget.host,
            client: client,
            onChanged: _notifier.refresh,
            siblings: siblings,
          ),
    );
  }

  Future<void> _paste(
    BuildContext context,
    ExplorerState state,
    FileClipboard clipboard,
  ) async {
    final dest = state.currentPath;
    final sources = clipboard.paths;
    final isCut = clipboard.mode == ClipboardMode.cut;

    if (isCut && sources.every((p) => _parentDirOf(p) == dest)) {
      showInfo(context, context.l10n.alreadyInThisFolder);
      return;
    }

    var duplicate = false;
    var overwrite = false;
    var effectiveSources = sources;

    try {
      final colliding = await _notifier.collidingBasenames(dest, sources);
      if (colliding.isNotEmpty) {
        if (!context.mounted) return;
        final resolution = await showConflictResolutionDialog(
          context,
          collidingCount: colliding.length,
          totalCount: sources.length,
          destLabel: folderLabel(dest),
        );
        switch (resolution) {
          case ConflictResolution.cancel:
            return;
          case ConflictResolution.keepBoth:
            duplicate = true;
          case ConflictResolution.overwrite:
            overwrite = true;
          case ConflictResolution.skip:
            effectiveSources =
                sources
                    .where((p) => !colliding.contains(basenameOf(p)))
                    .toList();
            if (effectiveSources.isEmpty) {
              if (context.mounted) {
                showInfo(
                  context,
                  context.l10n.clipboardAllExistNothing(
                    folderLabel(dest),
                    isCut ? context.l10n.moveLabel : context.l10n.copyLabel,
                  ),
                );
              }
              return;
            }
        }
      }
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          context.l10n.couldNotCheckFolder(folderLabel(dest), e.toString()),
          onRetry: () => _paste(context, state, clipboard),
        );
      }
      return;
    }

    if (!context.mounted) return;
    try {
      final res =
          isCut
              ? await _notifier.moveSelected(
                dest,
                sources: effectiveSources,
                duplicate: duplicate,
                overwrite: overwrite,
              )
              : await _notifier.copySelected(
                dest,
                sources: effectiveSources,
                duplicate: duplicate,
                overwrite: overwrite,
              );
      if (isCut) {
        ref.read(clipboardProvider.notifier).clear();
      }
      if (context.mounted) {
        await reportBatchResult(
          context,
          res,
          isCut ? context.l10n.movedLabel : context.l10n.copiedLabel,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          context.l10n.operationFailed(
            isCut ? context.l10n.moveLabel : context.l10n.copyLabel,
            e.toString(),
          ),
          onRetry: () => _paste(context, state, clipboard),
        );
      }
    }
  }

  Future<void> _pickAndUpload(BuildContext context, ExplorerState state) async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) return;

    final existingNames = state.entries.map((e) => e.name).toSet();
    var name = picked.name;
    var overwrite = false;

    if (existingNames.contains(name)) {
      if (!context.mounted) return;
      final resolution = await showConflictResolutionDialog(
        context,
        collidingCount: 1,
        totalCount: 1,
        destLabel: folderLabel(state.currentPath),
      );
      switch (resolution) {
        case ConflictResolution.cancel:
          return;
        case ConflictResolution.skip:
          if (context.mounted) {
            showInfo(context, context.l10n.alreadyExistsSkipped(name));
          }
          return;
        case ConflictResolution.overwrite:
          overwrite = true;
        case ConflictResolution.keepBoth:
          name = dedupedName(name, existingNames);
      }
    }

    final remotePath = '${state.currentPath}/$name';
    ref
        .read(transferQueueProvider.notifier)
        .enqueue(
          TransferTask.upload(
            localPath: localPath,
            remotePath: remotePath,
            host: widget.host,
            overwrite: overwrite,
          ),
        );

    if (context.mounted) {
      showInfo(context, context.l10n.uploadingFile(name));
    }
  }

  void _showCreateMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => CreateMenu(notifier: _notifier),
    );
  }
}

String _parentDirOf(String path) {
  final sep = path.contains('\\') ? r'\' : '/';
  final idx = path.lastIndexOf(sep);
  return idx <= 0 ? sep : path.substring(0, idx);
}
