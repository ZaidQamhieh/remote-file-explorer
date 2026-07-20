import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/favorites.dart';
import '../../core/storage/pin_store.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/l10n_ext.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/state_views.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../preview/preview.dart';
import '../search/search_screen.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_state.dart';
import '../transfers/widgets/mini_transfer_bar.dart';
import 'clipboard_state.dart';
import 'command_palette.dart';
import 'explorer_state.dart';
import 'meta_sheet.dart';
import 'recent_screen.dart';
import 'trash_screen.dart';
import 'dup_finder_screen.dart';
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

  // Active bookmark tag filter; reset on directory navigation.
  String? _activeTag;

  // P2 keyboard shortcuts + type-ahead jump (entry-list scoped, see
  // `_buildBody`'s Actions/Shortcuts/Focus wrapper).
  final _listFocusNode = FocusNode(debugLabel: 'explorerEntryList');
  final _scrollController = ScrollController();
  String _typeAheadQuery = '';
  Timer? _typeAheadTimer;

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialPath;
    if (initialPath != null && initialPath != widget.rootPath) {
      Future.microtask(() => _notifier.jumpTo(initialPath));
    }
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _scrollController.dispose();
    _typeAheadTimer?.cancel();
    super.dispose();
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
                  isCurrentFolderPinned:
                      ref
                          .watch(pinStoreProvider)
                          .valueOrNull
                          ?.any(
                            (p) =>
                                p.hostId == widget.host.id &&
                                p.remotePath == state.currentPath,
                          ) ??
                      false,
                  onBack: _notifier.popDirectory,
                  onNavigateTo: _notifier.navigateTo,
                  onMoveInto:
                      (dragged, dest) async =>
                          _moveInto(context, client, dragged, dest),
                  onSearch: () => _openSearch(context, state, client),
                  onToggleFavorite:
                      () => _toggleFavorite(context, state, isFav),
                  onOpenBookmarks:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BookmarksScreen(),
                        ),
                      ),
                  onOverflow:
                      (action) => _onOverflowAction(context, state, action),
                  onJumpTo: _notifier.jumpTo,
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
        showError(context, context.l10n.renameFailed(humanizeError(e)));
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
      case OverflowAction.recent:
        _openRecent(context, state);
      case OverflowAction.storageByType:
        _openStorageByType(context, state);
      case OverflowAction.dupFinder:
        _openDupFinder(context, state);
      case OverflowAction.commandPalette:
        _showCommandPalette(context, state);
      case OverflowAction.pinOffline:
        _togglePin(state);
    }
  }

  Future<void> _togglePin(ExplorerState state) async {
    final path = state.currentPath;
    final hostId = widget.host.id;
    final pinStore = ref.read(pinStoreProvider.notifier);
    final pinned = pinStore.isPinned(hostId, path);
    if (pinned) {
      await pinStore.unpin(hostId, path);
      _notifier.setPinnedListing(path, false);
    } else {
      await pinStore.pin(hostId, path);
      _notifier.setPinnedListing(path, true);
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

  Future<void> _openRecent(BuildContext context, ExplorerState state) async {
    final client = await ref.read(clientProvider(widget.host.id).future);
    if (!context.mounted) return;
    final parentPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RecentScreen(host: widget.host, client: client),
      ),
    );
    if (parentPath != null) _notifier.jumpTo(parentPath);
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

  Future<void> _openDupFinder(BuildContext context, ExplorerState state) async {
    final client = await ref.read(clientProvider(widget.host.id).future);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => DupFinderScreen(
              hostId: widget.host.id,
              path: state.currentPath,
              client: client,
            ),
      ),
    );
  }

  Future<void> _showCommandPalette(
    BuildContext context,
    ExplorerState state,
  ) async {
    final client = await ref.read(clientProvider(widget.host.id).future);
    if (!context.mounted) return;
    await CommandPalette.show(
      context,
      actions: [
        PaletteAction(
          label: 'Search',
          icon: LucideIcons.search,
          onTap: () => _openSearch(context, state, client),
        ),
        PaletteAction(
          label: 'Refresh',
          icon: LucideIcons.refreshCw,
          onTap: () => _notifier.refresh(),
        ),
        PaletteAction(
          label: 'Toggle Grid/List',
          icon: LucideIcons.layoutGrid,
          onTap: () => _notifier.toggleView(),
        ),
        PaletteAction(
          label: 'View Options',
          icon: LucideIcons.slidersHorizontal,
          onTap: () => ViewOptionsSheet.show(context, notifier: _notifier),
        ),
        PaletteAction(
          label: 'Favorites',
          icon: LucideIcons.bookmark,
          onTap: () => _showFavorites(context),
        ),
        PaletteAction(
          label: 'Transfers',
          icon: LucideIcons.fileUp,
          onTap: () => _showTransfers(context),
        ),
        PaletteAction(
          label: 'Trash',
          icon: LucideIcons.trash2,
          onTap: () => _openTrash(context),
        ),
        PaletteAction(
          label: 'Recent',
          icon: LucideIcons.history,
          onTap: () => _openRecent(context, state),
        ),
        PaletteAction(
          label: 'Storage by Type',
          icon: LucideIcons.pieChart,
          onTap: () => _openStorageByType(context, state),
        ),
        PaletteAction(
          label: 'Find Duplicates',
          icon: LucideIcons.replace,
          onTap: () => _openDupFinder(context, state),
        ),
        PaletteAction(
          label: 'Navigate to Path',
          icon: LucideIcons.route,
          onTap: () => _showGoToPath(context),
        ),
      ],
    );
  }

  Future<void> _showGoToPath(BuildContext context) async {
    final path = await showShadDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return ShadDialog(
          title: const Text('Go to Path'),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Go'),
            ),
          ],
          child: ShadInput(
            controller: controller,
            placeholder: const Text('/path/to/folder'),
          ),
        );
      },
    );
    if (path != null && path.isNotEmpty) _notifier.jumpTo(path);
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

  // ---------------------------------------------------------------------------
  // Bookmarks
  // ---------------------------------------------------------------------------

  Future<void> _showBookmarkSheet(BuildContext context, Entry entry) async {
    final notifier = ref.read(bookmarkStoreProvider.notifier);
    final already = notifier.isBookmarked(widget.host.id, entry.path);

    if (already) {
      final ok = await showShadDialog<bool>(
        context: context,
        builder:
            (ctx) => ShadDialog.alert(
              title: const Text('Remove Bookmark'),
              description: Text('Remove bookmark for "${entry.name}"?'),
              actions: [
                ShadButton.outline(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ShadButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove'),
                ),
              ],
            ),
      );
      if (ok == true) notifier.removeBookmark(widget.host.id, entry.path);
    } else {
      final ctrl = TextEditingController();
      final ok = await showShadDialog<bool>(
        context: context,
        builder:
            (ctx) => ShadDialog(
              title: Text('Bookmark "${entry.name}"'),
              actions: [
                ShadButton.outline(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ShadButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
              child: ShadInput(
                controller: ctrl,
                placeholder: const Text('Tag (optional)'),
                autofocus: true,
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
            ),
      );
      final tag = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
      ctrl.dispose();
      if (ok == true) {
        notifier.addBookmark(
          Bookmark(hostId: widget.host.id, remotePath: entry.path, tag: tag),
        );
      }
    }
  }

  /// Chip row of distinct tags for bookmarks whose paths appear in the current
  /// directory listing. Returns null when there are no tagged bookmarks.
  Widget? _buildBookmarkChipRow(ExplorerState state) {
    final all = ref.watch(bookmarkStoreProvider).valueOrNull ?? [];
    final visiblePaths = state.displayEntries.map((e) => e.path).toSet();
    final tags =
        all
            .where(
              (b) =>
                  b.hostId == widget.host.id &&
                  b.tag != null &&
                  visiblePaths.contains(b.remotePath),
            )
            .map((b) => b.tag!)
            .toSet()
            .toList();
    if (tags.isEmpty) return null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          if (_activeTag != null) ...[
            ActionChip(
              label: const Text('All'),
              onPressed: () => setState(() => _activeTag = null),
            ),
            const SizedBox(width: Spacing.xs),
          ],
          for (final tag in tags) ...[
            FilterChip(
              label: Text(tag),
              selected: _activeTag == tag,
              onSelected:
                  (sel) => setState(() => _activeTag = sel ? tag : null),
            ),
            const SizedBox(width: Spacing.xs),
          ],
        ],
      ),
    );
  }

  /// Filters [entries] to only those bookmarked with [_activeTag].
  /// Returns [entries] unchanged when no tag filter is active.
  List<Entry> _filteredEntries(List<Entry> entries) {
    final tag = _activeTag;
    if (tag == null) return entries;
    final bookmarks = ref.read(bookmarkStoreProvider).valueOrNull ?? [];
    final tagged = {
      for (final b in bookmarks)
        if (b.hostId == widget.host.id && b.tag == tag) b.remotePath,
    };
    return entries.where((e) => tagged.contains(e.path)).toList();
  }

  Widget _buildBody(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
  ) {
    // Reset tag filter when the user navigates to a different directory.
    ref.listen(explorerProvider(_arg).select((s) => s.currentPath), (_, __) {
      if (_activeTag != null) setState(() => _activeTag = null);
    });

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

    final chipRow = _buildBookmarkChipRow(state);

    // Entries exist, but the bookmark-tag filter or hidden-items visibility
    // hides all of them — a different message than a genuinely empty folder.
    if (_filteredEntries(state.displayEntries).isEmpty) {
      final kind = resolveEmptyState(hasRawEntries: state.entries.isNotEmpty);
      return Column(
        children: [
          if (pinRow != null) pinRow,
          if (chipRow != null) chipRow,
          Expanded(
            child: RefreshIndicator(
              onRefresh: _notifier.refresh,
              child: ListView(
                children: [
                  const SizedBox(height: 120),
                  EmptyFolderView(kind: kind),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (pinRow != null) pinRow,
        if (chipRow != null) chipRow,
        if (state.offline) const OfflineBanner(),
        Expanded(
          child: Actions(
            actions: <Type, Action<Intent>>{
              VoidCallbackIntent: VoidCallbackAction(),
            },
            child: Shortcuts(
              shortcuts: _entryListShortcuts(context, state, client),
              child: Focus(
                focusNode: _listFocusNode,
                autofocus: true,
                onKeyEvent: (node, event) => _handleTypeAheadKey(event, state),
                child: RefreshIndicator(
                  onRefresh: _notifier.refresh,
                  child:
                      state.gridView
                          ? _buildGrid(context, state, client)
                          : _buildList(context, state, client, density),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // P2: external-keyboard shortcuts + type-ahead jump
  //
  // Scoped to the entry-list area only (see the Actions/Shortcuts/Focus
  // wrapper in `_buildBody` above) so typing in the rename dialog, the "Go to
  // Path" dialog, or the search screen is unaffected — those are separate
  // routes/overlays, not descendants of this Focus subtree.
  // ---------------------------------------------------------------------------

  /// Hardware-keyboard shortcuts, bound to the exact same notifier/clipboard
  /// methods the existing touch UI already calls (`SelectionBar`,
  /// `ExplorerSelectionAppBar`, the paste FAB, the search icon).
  Map<ShortcutActivator, Intent> _entryListShortcuts(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
  ) => {
    const SingleActivator(
      LogicalKeyboardKey.keyC,
      control: true,
    ): VoidCallbackIntent(() => _copySelection(context, state)),
    const SingleActivator(
      LogicalKeyboardKey.keyX,
      control: true,
    ): VoidCallbackIntent(() => _cutSelection(context, state)),
    const SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
    ): VoidCallbackIntent(() => _pasteFromShortcut(context, state)),
    const SingleActivator(LogicalKeyboardKey.delete): VoidCallbackIntent(
      () => _confirmDeleteSelection(context, state),
    ),
    const SingleActivator(
      LogicalKeyboardKey.keyF,
      control: true,
    ): VoidCallbackIntent(() => _openSearch(context, state, client)),
    const SingleActivator(
      LogicalKeyboardKey.keyA,
      control: true,
    ): VoidCallbackIntent(_notifier.selectAll),
    const SingleActivator(LogicalKeyboardKey.escape): VoidCallbackIntent(
      _notifier.clearSelection,
    ),
    const SingleActivator(LogicalKeyboardKey.backspace): VoidCallbackIntent(
      _notifier.popDirectory,
    ),
    const SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      alt: true,
    ): VoidCallbackIntent(_notifier.popDirectory),
  };

  /// Same effect as `SelectionBar._copySelected`: no-op when nothing's
  /// selected (don't toast "Copied 0 items").
  void _copySelection(BuildContext context, ExplorerState state) {
    if (state.selected.isEmpty) return;
    final paths = state.selected.toList();
    ref.read(clipboardProvider.notifier).copy(paths, widget.host.id);
    _notifier.clearSelection();
    showSuccess(context, context.l10n.clipboardCopiedHint(paths.length));
  }

  /// Same effect as `SelectionBar._cutSelected`.
  void _cutSelection(BuildContext context, ExplorerState state) {
    if (state.selected.isEmpty) return;
    final paths = state.selected.toList();
    ref.read(clipboardProvider.notifier).cut(paths, widget.host.id);
    _notifier.clearSelection();
    showSuccess(context, context.l10n.clipboardCutHint(paths.length));
  }

  /// Same effect as the paste FAB's `onPaste`: no-op on an empty clipboard.
  void _pasteFromShortcut(BuildContext context, ExplorerState state) {
    final clipboard = ref.read(clipboardProvider);
    if (clipboard == null) return;
    _paste(context, state, clipboard);
  }

  /// Mirrors `SelectionBar._confirmDelete` (same three-way dialog, same
  /// `deleteSelected` call) — duplicated rather than shared because
  /// `selection_bar.dart` isn't to be modified for this wave.
  Future<void> _confirmDeleteSelection(
    BuildContext context,
    ExplorerState state,
  ) async {
    if (state.selected.isEmpty) return;
    final count = state.selected.length;
    final permanent = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(ctx.l10n.deleteTitle),
            description: Text(
              '${ctx.l10n.moveNItemsToTrash(count)} '
              '${ctx.l10n.canRestoreFromTrash(count)}',
            ),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.deleteForeverButton),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.moveToTrashButton),
              ),
            ],
          ),
    );
    if (permanent == null) return;
    try {
      final res = await _notifier.deleteSelected(permanent: permanent);
      if (context.mounted) {
        await reportBatchResult(
          context,
          res,
          permanent
              ? context.l10n.deletedLabel
              : context.l10n.movedToTrashLabel,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.deleteFailed(humanizeError(e)));
      }
    }
  }

  /// Accumulates printable keystrokes into a buffer (reset ~1s after the last
  /// keystroke) and jumps the list to the first entry whose name starts with
  /// it. Returns `ignored` for non-printable keys / modifier combos so they
  /// fall through to `_entryListShortcuts` above.
  KeyEventResult _handleTypeAheadKey(KeyEvent event, ExplorerState state) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final char = event.character;
    if (char == null || char.isEmpty || char.codeUnitAt(0) < 0x20) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    _typeAheadTimer?.cancel();
    _typeAheadQuery += char;
    _typeAheadTimer = Timer(const Duration(seconds: 1), _resetTypeAhead);
    final entries = _filteredEntries(state.displayEntries);
    final index = firstMatchIndex(entries, _typeAheadQuery);
    if (index != null) _scrollToIndex(index, entries.length);
    return KeyEventResult.handled;
  }

  void _resetTypeAhead() {
    _typeAheadQuery = '';
    _typeAheadTimer = null;
  }

  // ponytail: proportional estimate (index / count), not pixel-exact —
  // entry rows have no fixed itemExtent (comfortable/compact density), so an
  // exact offset would need per-row measurement. Good enough to land the
  // viewport near the match; switch to an itemExtent-based calc if a reviewer
  // wants pixel precision.
  void _scrollToIndex(int index, int total) {
    if (!_scrollController.hasClients || total <= 1) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final fraction = (index / (total - 1)).clamp(0.0, 1.0);
    _scrollController.animateTo(
      maxExtent * fraction,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
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

  Set<String> _pinnedPaths() =>
      ref
          .watch(pinStoreProvider)
          .valueOrNull
          ?.where((p) => p.hostId == widget.host.id)
          .map((p) => p.remotePath)
          .toSet() ??
      const {};

  Widget _buildList(
    BuildContext context,
    ExplorerState state,
    AgentClient client,
    EntryDensity density,
  ) {
    final entries = _filteredEntries(state.displayEntries);
    final showLoadMore = state.hasMore && _activeTag == null;
    final showHiddenFooter = state.hiddenCount > 0 && _activeTag == null;
    final itemCount =
        entries.length + (showLoadMore ? 1 : 0) + (showHiddenFooter ? 1 : 0);
    final favoritePaths = _favoritePaths();
    final pinnedPaths = _pinnedPaths();
    return GroupedCard(
      padded: false,
      children: [
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            itemCount: itemCount,
            separatorBuilder:
                (ctx, i) =>
                    i < entries.length - 1
                        ? Divider(
                          height: 1,
                          indent: Spacing.md,
                          endIndent: Spacing.md,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        )
                        : const SizedBox.shrink(),
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
                    isPinned: pinnedPaths.contains(entry.path),
                    onTap: () => _onEntryTap(context, entry, client),
                    onLongPress: () => _notifier.toggleSelect(entry.path),
                    onSelect: () => _notifier.toggleSelect(entry.path),
                    onMoveInto:
                        (dragged, dest) =>
                            _moveInto(context, client, dragged, dest),
                    onShowMeta:
                        entry.isDir
                            ? () => _showMeta(context, entry, client)
                            : null,
                    onBookmark: () => _showBookmarkSheet(context, entry),
                    onPeek:
                        isPreviewable(entry)
                            ? () => openPreviewPeek(
                              context,
                              entry: entry,
                              host: widget.host,
                              client: client,
                            )
                            : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
            humanizeError(e),
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
          context.l10n.moveFailed(humanizeError(e)),
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
    final entries = _filteredEntries(state.displayEntries);
    final showLoadMore = state.hasMore && _activeTag == null;
    final showHiddenFooter = state.hiddenCount > 0 && _activeTag == null;
    final itemCount =
        entries.length + (showLoadMore ? 1 : 0) + (showHiddenFooter ? 1 : 0);
    final favoritePaths = _favoritePaths();
    final pinnedPaths = _pinnedPaths();
    return GroupedCard(
      padded: false,
      children: [
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
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
                    isPinned: pinnedPaths.contains(entry.path),
                    onTap: () => _onEntryTap(context, entry, client),
                    onLongPress: () => _notifier.toggleSelect(entry.path),
                    onMoveInto:
                        (dragged, dest) =>
                            _moveInto(context, client, dragged, dest),
                    onBookmark: () => _showBookmarkSheet(context, entry),
                    onPeek:
                        isPreviewable(entry)
                            ? () => openPreviewPeek(
                              context,
                              entry: entry,
                              host: widget.host,
                              client: client,
                            )
                            : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
      final siblings = ref.read(explorerProvider(_arg)).displayEntries;
      openPreview(
        context,
        entry: entry,
        host: widget.host,
        client: client,
        siblings: siblings,
        onChanged: _notifier.refresh,
      );
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
          context.l10n.couldNotCheckFolder(folderLabel(dest), humanizeError(e)),
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
            humanizeError(e),
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

/// Index of the first [entries] entry whose name starts with [typed]
/// (case-insensitive), or `null` if none match. Pure/testable core of the
/// type-ahead jump in `_ExplorerScreenState._handleTypeAheadKey`.
int? firstMatchIndex(List<Entry> entries, String typed) {
  if (typed.isEmpty) return null;
  final lower = typed.toLowerCase();
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].name.toLowerCase().startsWith(lower)) return i;
  }
  return null;
}
