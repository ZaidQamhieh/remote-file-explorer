import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';
import '../../core/storage/favorites.dart';
import '../../core/storage/host_store.dart';
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
  AgentClient? _client;

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    final store = await ref.read(hostStoreProvider.future);
    final token = await store.getToken(widget.host.id);
    if (mounted) {
      setState(() {
        _client = AgentClient(widget.host, deviceToken: token);
      });
    }
  }

  ExplorerArg get _arg => (
        host: widget.host,
        rootPath: '/',
        client: _client!,
      );

  ExplorerNotifier get _notifier =>
      ref.read(explorerProvider(_arg).notifier);

  @override
  Widget build(BuildContext context) {
    final client = _client;
    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.host.label)),
        body: const Center(child: CircularProgressIndicator()),
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
        appBar: _buildAppBar(context, state, isFav),
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

  AppBar _buildAppBar(BuildContext context, ExplorerState state, bool isFav) {
    return AppBar(
      leading: state.atRoot
          ? null
          : BackButton(onPressed: () => _notifier.popDirectory()),
      title: _BreadcrumbBar(state: state, notifier: _notifier),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => _openSearch(context, state),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFav
            ? 'Removed from favorites'
            : 'Added "${_folderLabel(state.currentPath)}" to favorites'),
        duration: const Duration(seconds: 1),
      ),
    );
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

  Future<void> _openSearch(BuildContext context, ExplorerState state) async {
    final client = _client;
    if (client == null) return;
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
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(state.error!),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _notifier.refresh, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (state.sortedEntries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _notifier.refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('This folder is empty.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _notifier.refresh,
      child: state.gridView
          ? _buildGrid(context, state, client)
          : _buildList(context, state, client),
    );
  }

  Widget _buildList(
      BuildContext context, ExplorerState state, AgentClient client) {
    return ListView.builder(
      itemCount: state.sortedEntries.length,
      itemBuilder: (ctx, i) {
        final entry = state.sortedEntries[i];
        return _EntryListTile(
          entry: entry,
          selected: state.selected.contains(entry.path),
          multiSelect: state.multiSelect,
          onTap: () => _onEntryTap(context, entry, client),
          onLongPress: () => _notifier.toggleSelect(entry.path),
          onSelect: () => _notifier.toggleSelect(entry.path),
        );
      },
    );
  }

  Widget _buildGrid(
      BuildContext context, ExplorerState state, AgentClient client) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisExtent: 120,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: state.sortedEntries.length,
      itemBuilder: (ctx, i) {
        final entry = state.sortedEntries[i];
        return _EntryGridCell(
          entry: entry,
          client: client,
          selected: state.selected.contains(entry.path),
          multiSelect: state.multiSelect,
          onTap: () => _onEntryTap(context, entry, client),
          onLongPress: () => _notifier.toggleSelect(entry.path),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploading ${picked.name}...')),
      );
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
  const _BreadcrumbBar({required this.state, required this.notifier});
  final ExplorerState state;
  final ExplorerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final stack = state.pathStack;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(stack.length, (i) {
          final label =
              i == 0 ? '/' : stack[i].split(RegExp(r'[/\\]')).last;
          return Row(
            children: [
              if (i > 0) const Icon(Icons.chevron_right, size: 16),
              GestureDetector(
                onTap: () => notifier.navigateTo(i),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: i == stack.length - 1
                        ? FontWeight.bold
                        : FontWeight.normal,
                    decoration: i < stack.length - 1
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ],
          );
        }),
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
  });

  final Entry entry;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: multiSelect
          ? Checkbox(value: selected, onChanged: (_) => onSelect())
          : _EntryIcon(entry: entry),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: entry.isDir
          ? null
          : Text(_formatSize(entry.size) +
              (entry.modified != null
                  ? '  ·  ${_formatDate(entry.modified!)}'
                  : '')),
      trailing: entry.isDir ? const Icon(Icons.chevron_right) : null,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
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
  });

  final Entry entry;
  final AgentClient client;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final mime = entry.mimeType ?? '';
    final isImage = !entry.isDir && mime.startsWith('image/');

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isImage)
              SizedBox(
                width: 56,
                height: 56,
                child: ThumbnailImage(
                  entry: entry,
                  client: client,
                  fallback: Center(child: _EntryIcon(entry: entry, size: 40)),
                ),
              )
            else
              _EntryIcon(entry: entry, size: 40),
            const SizedBox(height: 8),
            Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
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
// Multi-select bottom bar
// ---------------------------------------------------------------------------

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
    return SafeArea(
      child: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Deselect all',
              onPressed: notifier.clearSelection,
            ),
            Text('${state.selected.length} selected'),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () => _showDestPicker(context, 'copy'),
            ),
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              tooltip: 'Move',
              onPressed: () => _showDestPicker(context, 'move'),
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download',
              onPressed: () => _downloadSelected(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(context),
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
      if (action == 'copy') {
        await notifier.copySelected(dest);
      } else {
        await notifier.moveSelected(dest);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${action == 'copy' ? 'Copied' : 'Moved'} successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
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
    notifier.clearSelection();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Queued ${state.selected.length} download(s)')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete items?'),
        content: Text(
            'Delete ${state.selected.length} item(s)? This cannot be undone.'),
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
        await notifier.deleteSelected();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deleted')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
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
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created $name')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
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
