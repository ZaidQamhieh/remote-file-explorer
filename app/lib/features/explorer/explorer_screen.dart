import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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
import 'thumbnail_image.dart';

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
            ? _MultiSelectBar(
                state: state,
                notifier: _notifier,
                client: client,
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
      title: _BreadcrumbBar(
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
        _SortButton(sort: state.sort, onSort: _notifier.setSort),
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
            label: _folderLabel(state.currentPath),
          ),
        );
    if (isFav) {
      showInfo(context, 'Removed from favorites');
    } else {
      showSuccess(
          context, 'Added "${_folderLabel(state.currentPath)}" to favorites');
    }
  }

  void _showFavorites(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FavoritesSheet(
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
          child: _EntryListTile(
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
          child: _EntryGridCell(
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
      builder: (ctx) => _CreateMenu(notifier: _notifier),
    );
  }
}

// ---------------------------------------------------------------------------
// Breadcrumb bar
// ---------------------------------------------------------------------------

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.state,
    required this.notifier,
    this.onMoveInto,
  });
  final ExplorerState state;
  final ExplorerNotifier notifier;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final stack = state.pathStack;
    final scheme = Theme.of(context).colorScheme;
    final lastIndex = stack.length - 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(stack.length, (i) {
            final label =
                i == 0 ? '/' : stack[i].split(RegExp(r'[/\\]')).last;
            final isCurrent = i == lastIndex;

            final chip = Material(
              color: isCurrent
                  ? scheme.primaryContainer
                  : scheme.secondaryContainer.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(borderRadius: Radii.chipR),
              child: InkWell(
                borderRadius: Radii.chipR,
                onTap: () => notifier.navigateTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isCurrent
                              ? scheme.onPrimaryContainer
                              : scheme.onSecondaryContainer,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            );

            final crumb = onMoveInto != null
                ? DragTarget<Entry>(
                    onWillAcceptWithDetails: (d) => d.data.path != stack[i],
                    onAcceptWithDetails: (d) =>
                        onMoveInto!(d.data, stack[i]),
                    builder: (ctx, cand, rej) => AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: Radii.chipR,
                        border: cand.isNotEmpty
                            ? Border.all(color: scheme.primary, width: 2)
                            : Border.all(color: Colors.transparent, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: Radii.chipR,
                        child: chip,
                      ),
                    ),
                  )
                : ClipRRect(borderRadius: Radii.chipR, child: chip);

            return Padding(
              padding: const EdgeInsets.only(right: Spacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Spacing.xs),
                      child: Icon(Icons.chevron_right,
                          size: 18, color: scheme.outline),
                    ),
                  crumb,
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort button
// ---------------------------------------------------------------------------

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSort});
  final SortOrder sort;
  final void Function(SortOrder) onSort;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort',
      onSelected: (field) {
        if (sort.field == field) {
          onSort(sort.copyWith(ascending: !sort.ascending));
        } else {
          onSort(SortOrder(field: field));
        }
      },
      itemBuilder: (_) => SortField.values
          .map((f) => PopupMenuItem(
                value: f,
                child: Row(
                  children: [
                    if (sort.field == f)
                      Icon(
                          sort.ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(f.name[0].toUpperCase() + f.name.substring(1)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry list tile
// ---------------------------------------------------------------------------

class _EntryListTile extends StatelessWidget {
  const _EntryListTile({
    required this.entry,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onLongPress,
    required this.onSelect,
    this.onMoveInto,
  });

  final Entry entry;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = entry.isDir
        ? null
        : _formatSize(entry.size) +
            (entry.modified != null
                ? '  ·  ${_formatDate(entry.modified!)}'
                : '');

    Widget leading = multiSelect
        ? Checkbox(value: selected, onChanged: (_) => onSelect())
        : _IconTile(entry: entry);

    Widget tile = Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.55) : Colors.transparent,
      borderRadius: Radii.cardR,
      child: InkWell(
        borderRadius: Radii.cardR,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.isDir)
                Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
    return _wrapDraggable(
      context: context,
      entry: entry,
      multiSelect: multiSelect,
      onMoveInto: onMoveInto,
      child: tile,
    );
  }
}

/// File-type icon presented inside a tonal rounded square — the roomier,
/// "distinctive modern" leading element for list rows.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.entry});

  static const double _size = 44;

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.chipR,
      ),
      alignment: Alignment.center,
      child: _EntryIcon(entry: entry, size: _size * 0.5),
    );
  }
}

/// Wraps an entry [child] so it can be long-press dragged and (for folders)
/// act as a drop target that moves the dropped entry into itself. In
/// multi-select mode dragging is disabled to avoid clashing with tap-to-toggle.
Widget _wrapDraggable({
  required BuildContext context,
  required Entry entry,
  required bool multiSelect,
  required Future<void> Function(Entry dragged, String destFolder)? onMoveInto,
  required Widget child,
}) {
  Widget tile = child;
  if (multiSelect || onMoveInto == null) {
    // Selection mode (or no move handler): keep tap-to-toggle, skip drag.
    if (entry.isDir && onMoveInto != null) {
      return _folderDropTarget(context, entry, onMoveInto, tile);
    }
    return tile;
  }
  tile = LongPressDraggable<Entry>(
    data: entry,
    onDragStarted: HapticFeedback.mediumImpact,
    feedback: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.drag_indicator),
          const SizedBox(width: 4),
          Text(entry.name),
        ]),
      ),
    ),
    childWhenDragging: Opacity(opacity: 0.4, child: tile),
    child: tile,
  );
  if (entry.isDir) {
    tile = _folderDropTarget(context, entry, onMoveInto, tile);
  }
  return tile;
}

/// A [DragTarget] that accepts an [Entry] dragged onto the folder [entry] and
/// moves it in, highlighting while a candidate hovers.
Widget _folderDropTarget(
  BuildContext context,
  Entry entry,
  Future<void> Function(Entry dragged, String destFolder) onMoveInto,
  Widget child,
) {
  return DragTarget<Entry>(
    onWillAcceptWithDetails: (d) => d.data.path != entry.path,
    onAcceptWithDetails: (d) => onMoveInto(d.data, entry.path),
    builder: (ctx, cand, rej) => Container(
      decoration: cand.isNotEmpty
          ? BoxDecoration(
              color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Entry grid cell
// ---------------------------------------------------------------------------

class _EntryGridCell extends StatelessWidget {
  const _EntryGridCell({
    required this.entry,
    required this.client,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onLongPress,
    this.onMoveInto,
  });

  final Entry entry;
  final AgentClient client;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mime = entry.mimeType ?? '';
    final isImage = !entry.isDir && mime.startsWith('image/');

    final cell = Material(
      color: selected
          ? scheme.secondaryContainer.withValues(alpha: 0.65)
          : scheme.surfaceContainerLow,
      borderRadius: Radii.cardR,
      child: InkWell(
        borderRadius: Radii.cardR,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.cardR,
            border: Border.all(
              color: selected ? Brand.accent : scheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(Spacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isImage)
                ClipRRect(
                  borderRadius: Radii.chipR,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: ThumbnailImage(
                      entry: entry,
                      client: client,
                      fallback:
                          Center(child: _EntryIcon(entry: entry, size: 40)),
                    ),
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: Radii.chipR,
                  ),
                  alignment: Alignment.center,
                  child: _EntryIcon(entry: entry, size: 32),
                ),
              const SizedBox(height: Spacing.sm),
              Text(
                entry.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );

    return _wrapDraggable(
      context: context,
      entry: entry,
      multiSelect: multiSelect,
      onMoveInto: onMoveInto,
      child: cell,
    );
  }
}

// ---------------------------------------------------------------------------
// Entry icon
// ---------------------------------------------------------------------------

class _EntryIcon extends StatelessWidget {
  const _EntryIcon({required this.entry, this.size = 24});
  final Entry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color? color;
    if (entry.isDir) {
      icon = Icons.folder;
      color = Colors.amber;
    } else {
      final mime = entry.mimeType ?? '';
      if (mime.startsWith('image/')) {
        icon = Icons.image;
        color = Colors.blue;
      } else if (mime.startsWith('video/')) {
        icon = Icons.movie;
        color = Colors.purple;
      } else if (mime.startsWith('audio/')) {
        icon = Icons.music_note;
        color = Colors.green;
      } else if (mime.contains('pdf')) {
        icon = Icons.picture_as_pdf;
        color = Colors.red;
      } else if (mime.contains('zip') || mime.contains('archive')) {
        icon = Icons.folder_zip;
        color = Colors.orange;
      } else if (mime.startsWith('text/') || mime.contains('json')) {
        icon = Icons.description;
        color = Colors.teal;
      } else {
        icon = Icons.insert_drive_file;
      }
    }
    return Icon(icon, size: size, color: color);
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

// ---------------------------------------------------------------------------
// Multi-select bottom bar
// ---------------------------------------------------------------------------

/// A labelled icon action used in the multi-select bar — tonal icon button
/// over a small caption, for tidier iconography than bare [IconButton]s.
class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: Radii.chipR,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (color ?? scheme.primary).withValues(alpha: 0.12),
                borderRadius: Radii.chipR,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: fg),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectBar extends ConsumerWidget {
  const _MultiSelectBar({
    required this.state,
    required this.notifier,
    required this.client,
    required this.host,
  });

  final ExplorerState state;
  final ExplorerNotifier notifier;
  final AgentClient client;
  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final allSelected = state.selected.length == state.entries.length &&
        state.entries.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            Spacing.md, 0, Spacing.md, Spacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.cardR,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Deselect all',
                  onPressed: notifier.clearSelection,
                ),
                Expanded(
                  child: Text(
                    '${state.selected.length} selected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      allSelected ? notifier.clearSelection : notifier.selectAll,
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                  label: Text(allSelected ? 'Clear' : 'Select all'),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BarAction(
                  icon: Icons.copy_outlined,
                  label: 'Copy',
                  onPressed: () => _showDestPicker(context, 'copy'),
                ),
                _BarAction(
                  icon: Icons.drive_file_move_outline,
                  label: 'Move',
                  onPressed: () => _showDestPicker(context, 'move'),
                ),
                _BarAction(
                  icon: Icons.download_outlined,
                  label: 'Download',
                  onPressed: () => _downloadSelected(context, ref),
                ),
                _BarAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: scheme.error,
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDestPicker(BuildContext context, String action) async {
    final dest = await showDialog<String>(
      context: context,
      builder: (ctx) => const _DestinationDialog(hint: 'Destination path'),
    );
    if (dest == null || !context.mounted) return;
    try {
      final res = action == 'copy'
          ? await notifier.copySelected(dest)
          : await notifier.moveSelected(dest);
      if (context.mounted) {
        await _reportBatch(
            context, res, action == 'copy' ? 'Copied' : 'Moved');
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, '${action == 'copy' ? 'Copy' : 'Move'} failed: $e',
            onRetry: () => _showDestPicker(context, action));
      }
    }
  }

  /// Inspects a batch operation [res] for per-item failures and either shows a
  /// success snackbar or a dialog listing the failed items.
  Future<void> _reportBatch(BuildContext context, Map<String, dynamic> res,
      String successVerb) async {
    final results = (res['results'] as List?) ?? const [];
    final failed = results
        .whereType<Map>()
        .where((r) => r['ok'] == false)
        .toList();
    if (!context.mounted) return;
    if (failed.isEmpty) {
      final n = results.length;
      showSuccess(context, '$successVerb $n item${n == 1 ? '' : 's'}');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$successVerb with ${failed.length} error(s)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: failed.map((f) {
              final err = f['error'];
              final msg = err is Map
                  ? (err['message'] ?? err['code'] ?? 'failed')
                  : 'failed';
              return ListTile(
                dense: true,
                title: Text('${f['path'] ?? '?'}'),
                subtitle: Text('$msg'),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _downloadSelected(
      BuildContext context, WidgetRef ref) async {
    final downloadsDir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    for (final path in state.selected) {
      final name = path.split(RegExp(r'[/\\]')).last;
      ref.read(transferQueueProvider.notifier).enqueue(
            TransferTask.download(
              remotePath: path,
              localPath: '${downloadsDir.path}/$name',
              host: host,
            ),
          );
    }
    final count = state.selected.length;
    notifier.clearSelection();
    if (context.mounted) {
      showSuccess(context, 'Queued $count download${count == 1 ? '' : 's'}');
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
            'Permanently delete ${state.selected.length} item(s)? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final res = await notifier.deleteSelected();
        if (context.mounted) {
          await _reportBatch(context, res, 'Deleted');
        }
      } catch (e) {
        if (context.mounted) showError(context, 'Delete failed: $e');
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Create menu
// ---------------------------------------------------------------------------

class _CreateMenu extends StatelessWidget {
  const _CreateMenu({required this.notifier});
  final ExplorerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder'),
            onTap: () {
              Navigator.pop(context);
              _showNameDialog(context, 'New folder', isFolder: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('New file'),
            onTap: () {
              Navigator.pop(context);
              _showNameDialog(context, 'New file', isFolder: false);
            },
          ),
        ],
      ),
    );
  }

  void _showNameDialog(BuildContext context, String title,
      {required bool isFolder}) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                if (isFolder) {
                  await notifier.createFolder(name);
                } else {
                  await notifier.createFile(name);
                }
                if (context.mounted) showSuccess(context, 'Created $name');
              } catch (e) {
                if (context.mounted) {
                  showError(context, 'Couldn\'t create $name: $e');
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Destination dialog
// ---------------------------------------------------------------------------

class _DestinationDialog extends StatelessWidget {
  const _DestinationDialog({required this.hint});
  final String hint;

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    return AlertDialog(
      title: const Text('Destination'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites sheet
// ---------------------------------------------------------------------------

class _FavoritesSheet extends ConsumerWidget {
  const _FavoritesSheet({required this.host, required this.onOpen});

  final Host host;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref
        .watch(favoritesProvider)
        .valueOrNull
        ?.where((f) => f.hostId == host.id)
        .toList() ??
        const [];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.bookmarks_outlined),
                SizedBox(width: 8),
                Text('Favorites', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
          if (favs.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                'No favorites yet. Open a folder and tap the ☆ star to bookmark it.',
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: favs.length,
                itemBuilder: (ctx, i) {
                  final f = favs[i];
                  return ListTile(
                    leading: const Icon(Icons.folder_special, color: Colors.amber),
                    title: Text(f.label),
                    subtitle: Text(f.path, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.star, color: Colors.amber),
                      tooltip: 'Remove',
                      onPressed: () => ref
                          .read(favoritesProvider.notifier)
                          .remove(f.hostId, f.path),
                    ),
                    onTap: () => onOpen(f.path),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Display name for a folder path (basename), or "Root" for the filesystem root.
String _folderLabel(String path) {
  if (path == '/' || RegExp(r'^[A-Za-z]:\\?$').hasMatch(path)) return 'Root';
  final name = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
  return name.isEmpty ? path : name;
}

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
