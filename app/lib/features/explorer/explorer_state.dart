import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/storage/listing_cache.dart';

// ---------------------------------------------------------------------------
// Sort order
// ---------------------------------------------------------------------------

enum SortField { name, size, date, type }

class SortOrder {
  const SortOrder({this.field = SortField.name, this.ascending = true});
  final SortField field;
  final bool ascending;
  SortOrder copyWith({SortField? field, bool? ascending}) =>
      SortOrder(
          field: field ?? this.field,
          ascending: ascending ?? this.ascending);
}

// ---------------------------------------------------------------------------
// Sorting helper
// ---------------------------------------------------------------------------

/// Partitions [entries] into directories-first then files, each sorted by
/// [sort]. Pure function so it can be memoized at state-construction time
/// instead of being recomputed by every `itemBuilder` call.
List<Entry> _sortEntries(List<Entry> entries, SortOrder sort) {
  final dirs = entries.where((e) => e.isDir).toList();
  final files = entries.where((e) => !e.isDir).toList();
  int cmp(Entry a, Entry b) {
    int r;
    switch (sort.field) {
      case SortField.name:
        r = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SortField.size:
        r = (a.size ?? 0).compareTo(b.size ?? 0);
      case SortField.date:
        r = (a.modified ?? DateTime(0)).compareTo(b.modified ?? DateTime(0));
      case SortField.type:
        r = (a.mimeType ?? '').compareTo(b.mimeType ?? '');
    }
    return sort.ascending ? r : -r;
  }

  dirs.sort(cmp);
  files.sort(cmp);
  return [...dirs, ...files];
}

// ---------------------------------------------------------------------------
// Explorer state
// ---------------------------------------------------------------------------

class ExplorerState {
  ExplorerState({
    required this.pathStack,
    this.entries = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.sort = const SortOrder(),
    this.gridView = false,
    this.selected = const {},
    this.stale = false,
    this.offline = false,
    this.nextCursor,
  }) : sortedEntries = _sortEntries(entries, sort);

  final List<String> pathStack;
  final List<Entry> entries;
  final bool loading;

  /// `true` while an additional page is being fetched (pagination).
  final bool loadingMore;
  final String? error;
  final SortOrder sort;
  final bool gridView;
  final Set<String> selected;
  final bool stale;   // showing cached data, refresh in progress or failed
  final bool offline; // last live fetch failed; data is from cache only

  /// Opaque cursor for the next page of [entries]; null when the current
  /// directory has no more pages to load.
  final String? nextCursor;

  /// [entries] partitioned (directories first) and sorted per [sort],
  /// computed once at construction time so list/grid `itemBuilder`s can do
  /// plain indexed access instead of re-sorting on every item.
  final List<Entry> sortedEntries;

  String get currentPath => pathStack.last;
  bool get atRoot => pathStack.length == 1;
  bool get multiSelect => selected.isNotEmpty;
  bool get hasMore => nextCursor != null;

  ExplorerState copyWith({
    List<String>? pathStack,
    List<Entry>? entries,
    bool? loading,
    bool? loadingMore,
    Object? error = _sentinel,
    SortOrder? sort,
    bool? gridView,
    Set<String>? selected,
    bool? stale,
    bool? offline,
    Object? nextCursor = _sentinel,
  }) =>
      ExplorerState(
        pathStack: pathStack ?? this.pathStack,
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error == _sentinel ? this.error : error as String?,
        sort: sort ?? this.sort,
        gridView: gridView ?? this.gridView,
        selected: selected ?? this.selected,
        stale: stale ?? this.stale,
        offline: offline ?? this.offline,
        nextCursor:
            nextCursor == _sentinel ? this.nextCursor : nextCursor as String?,
      );
}

const _sentinel = Object();

// ---------------------------------------------------------------------------
// Arg type for the explorer family provider
// ---------------------------------------------------------------------------

/// Key for [explorerProvider]. Value type (record) so two pushes of the same
/// host/path reuse the same provider entry instead of leaking a new one —
/// unlike the previous key which embedded [Host]/[AgentClient] objects (no
/// `==`, so identity-keyed and never reused).
typedef ExplorerArg = ({String hostId, String rootPath});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ExplorerNotifier
    extends AutoDisposeFamilyNotifier<ExplorerState, ExplorerArg> {
  @override
  ExplorerState build(ExplorerArg arg) {
    // Keep the underlying client provider alive for as long as this notifier
    // is alive, without rebuilding (and re-running `_load`/resetting
    // navigation state) every time `clientProvider`'s async value changes
    // (e.g. loading -> data on first resolve). `ref.listen` registers a
    // subscription — enough to keep an autoDispose provider alive — but only
    // invokes the callback, it doesn't trigger a rebuild of this notifier.
    ref.listen(clientProvider(arg.hostId), (_, _) {});

    // Schedule async load after construction.
    Future.microtask(_load);
    return ExplorerState(pathStack: [arg.rootPath]);
  }

  final ListingCache _cache = ListingCache();

  Future<AgentClient> _client() => ref.read(clientProvider(arg.hostId).future);

  Future<void> _load() async {
    final path = state.currentPath;

    // 1. Paint cached entries instantly (if any) while we fetch live.
    final cached = await _cache.get(arg.hostId, path);
    if (state.currentPath != path) return;
    if (cached != null) {
      state = state.copyWith(
        entries: cached.entries,
        loading: false,
        stale: true,
        offline: false,
        error: null,
        selected: {},
        nextCursor: null,
      );
    } else {
      state = state.copyWith(
          loading: true, error: null, selected: {}, nextCursor: null);
    }

    // 2. Fetch live; on success replace + cache; on failure fall back to cache.
    try {
      final client = await _client();
      if (state.currentPath != path) return;
      final listing = await client.list(path);
      if (state.currentPath != path) return;
      await _cache.put(arg.hostId, path, listing.entries);
      if (state.currentPath != path) return;
      state = state.copyWith(
        loading: false,
        entries: listing.entries,
        stale: false,
        offline: false,
        error: null,
        nextCursor: listing.nextCursor,
      );
    } catch (e) {
      if (state.currentPath != path) return;
      if (cached != null) {
        // Keep cached entries; mark offline rather than erroring out.
        state = state.copyWith(loading: false, stale: true, offline: true);
      } else {
        state = state.copyWith(loading: false, error: e.toString());
      }
    }
  }

  /// Loads the next page of entries for the current directory and appends
  /// them to [ExplorerState.entries]. No-op if a load is already in flight or
  /// there is no further page ([ExplorerState.hasMore] is false).
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;

    final path = state.currentPath;
    state = state.copyWith(loadingMore: true);
    try {
      final client = await _client();
      if (state.currentPath != path) return;
      final listing = await client.list(path, cursor: cursor);
      if (state.currentPath != path) return;
      final merged = [...state.entries, ...listing.entries];
      await _cache.put(arg.hostId, path, merged);
      if (state.currentPath != path) return;
      state = state.copyWith(
        entries: merged,
        loadingMore: false,
        nextCursor: listing.nextCursor,
      );
    } catch (e) {
      if (state.currentPath != path) return;
      // Leave existing entries as-is; just stop the spinner so the user can
      // retry by scrolling again.
      state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> refresh() => _load();

  void navigate(String path) {
    state = state.copyWith(pathStack: [...state.pathStack, path]);
    _load();
  }

  /// Returns `true` if navigation happened, `false` if already at root.
  bool popDirectory() {
    if (state.atRoot) return false;
    final stack = List<String>.from(state.pathStack)..removeLast();
    state = state.copyWith(pathStack: stack);
    _load();
    return true;
  }

  void navigateTo(int stackIndex) {
    if (stackIndex >= state.pathStack.length) return;
    final stack = state.pathStack.sublist(0, stackIndex + 1);
    state = state.copyWith(pathStack: stack);
    _load();
  }

  /// Jump directly to an absolute [path] (e.g. a favorite), rebuilding the
  /// breadcrumb stack from the root so back/breadcrumb navigation still works.
  void jumpTo(String path) {
    state = state.copyWith(pathStack: buildPathStack(path));
    _load();
  }

  void setSort(SortOrder sort) => state = state.copyWith(sort: sort);

  void toggleView() => state = state.copyWith(gridView: !state.gridView);

  void toggleSelect(String path) {
    final sel = Set<String>.from(state.selected);
    if (sel.contains(path)) {
      sel.remove(path);
    } else {
      sel.add(path);
    }
    state = state.copyWith(selected: sel);
  }

  void clearSelection() => state = state.copyWith(selected: {});

  void selectAll() {
    state = state.copyWith(
      selected: state.entries.map((e) => e.path).toSet(),
    );
  }

  Future<void> createFolder(String name) async {
    final client = await _client();
    final path = '${state.currentPath}/$name';
    await client.createFolder(path);
    await _load();
  }

  Future<void> createFile(String name) async {
    final client = await _client();
    final path = '${state.currentPath}/$name';
    await client.createFile(path);
    await _load();
  }

  Future<void> rename(String oldPath, String newName) async {
    final client = await _client();
    final dst = renameDestination(oldPath, newName);
    await client.rename(oldPath, dst);
    await _load();
  }

  Future<Map<String, dynamic>> deleteSelected() async {
    final client = await _client();
    final res = await client.delete(state.selected.toList());
    await _load();
    return res;
  }

  Future<Map<String, dynamic>> moveSelected(String destDir) async {
    final client = await _client();
    final res = await client.move(state.selected.toList(), destDir);
    await _load();
    return res;
  }

  Future<Map<String, dynamic>> copySelected(String destDir) async {
    final client = await _client();
    final res = await client.copy(state.selected.toList(), destDir);
    await _load();
    return res;
  }
}

// ---------------------------------------------------------------------------
// Provider family
// ---------------------------------------------------------------------------

final explorerProvider = NotifierProvider.autoDispose
    .family<ExplorerNotifier, ExplorerState, ExplorerArg>(
  ExplorerNotifier.new,
);

/// Display name for a folder path (basename), or "Root" for the filesystem root.
String folderLabel(String path) {
  if (path == '/' || RegExp(r'^[A-Za-z]:\\?$').hasMatch(path)) return 'Root';
  final name = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
  return name.isEmpty ? path : name;
}

/// Builds the destination path for renaming the entry at [oldPath] to
/// [newName], preserving whichever path separator [oldPath] uses — `/` for
/// POSIX hosts, `\` for Windows hosts (so `C:\dir\file` renames to
/// `C:\dir\newName`, not `C:\dir/newName`).
String renameDestination(String oldPath, String newName) {
  final sep = oldPath.contains('\\') ? r'\' : '/';
  final idx = oldPath.lastIndexOf(sep);
  final parent = idx <= 0 ? sep : oldPath.substring(0, idx);
  if (parent == sep) return '$sep$newName';
  return '$parent$sep$newName';
}

/// Expands an absolute path into the cumulative stack of ancestor paths,
/// starting at the filesystem root. Handles both POSIX (`/a/b`) and Windows
/// (`C:\a\b`) layouts.
///
/// `/home/x/Storage` -> ['/', '/home', '/home/x', '/home/x/Storage']
List<String> buildPathStack(String path) {
  // Windows drive path, e.g. C:\Users\x
  final winDrive = RegExp(r'^[A-Za-z]:').firstMatch(path);
  if (winDrive != null) {
    final parts = path
        .replaceAll('/', r'\')
        .split(r'\')
        .where((s) => s.isNotEmpty)
        .toList();
    final stack = <String>['${parts.first}\\']; // "C:\"
    var cur = parts.first;
    for (final p in parts.skip(1)) {
      cur = '$cur\\$p';
      stack.add(cur);
    }
    return stack;
  }

  // POSIX
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  final stack = <String>['/'];
  var cur = '';
  for (final p in parts) {
    cur = '$cur/$p';
    stack.add(cur);
  }
  return stack;
}
