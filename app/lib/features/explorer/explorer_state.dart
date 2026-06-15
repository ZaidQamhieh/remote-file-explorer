import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/listing_cache.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/storage/visibility_prefs.dart';

export '../../core/storage/view_prefs.dart' show SortField, SortOrder;

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
// Visibility helper
// ---------------------------------------------------------------------------

/// Returns the paths of [entries] that [prefs] would hide (see
/// [isEntryHidden]). Pure function so it can be memoized alongside
/// [_sortEntries] at state-construction time instead of being recomputed by
/// every `itemBuilder` call.
Set<String> _hiddenPaths(List<Entry> entries, VisibilityPrefs prefs) =>
    entries.where((e) => isEntryHidden(e, prefs)).map((e) => e.path).toSet();

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
    this.visibilityPrefs = const VisibilityPrefs(),
    this.showHidden = false,
  }) : sortedEntries = _sortEntries(entries, sort),
       hiddenPaths = _hiddenPaths(entries, visibilityPrefs);

  final List<String> pathStack;
  final List<Entry> entries;
  final bool loading;

  /// `true` while an additional page is being fetched (pagination).
  final bool loadingMore;
  final String? error;
  final SortOrder sort;
  final bool gridView;
  final Set<String> selected;
  final bool stale; // showing cached data, refresh in progress or failed
  final bool offline; // last live fetch failed; data is from cache only

  /// Opaque cursor for the next page of [entries]; null when the current
  /// directory has no more pages to load.
  final String? nextCursor;

  /// Mirrors the resolved per-host file-visibility prefs from the two-tier
  /// settings model (`settingsProvider.resolveVisibility(hostId)`) —
  /// hide-dotfiles/extensions/names, applied to [hiddenPaths]/[displayEntries].
  final VisibilityPrefs visibilityPrefs;

  /// Session-only "show hidden items" override for this explorer screen, set
  /// via [ExplorerNotifier.toggleShowHidden]. Not persisted: resets the next
  /// time this provider instance is recreated.
  final bool showHidden;

  /// [entries] partitioned (directories first) and sorted per [sort],
  /// computed once at construction time so list/grid `itemBuilder`s can do
  /// plain indexed access instead of re-sorting on every item.
  ///
  /// Deliberately the FULL sorted list — visibility filtering is NOT applied
  /// here. See [displayEntries] for why filtering happens at display time
  /// instead of before this sort.
  final List<Entry> sortedEntries;

  /// Paths within [sortedEntries] that [visibilityPrefs] would hide,
  /// computed once at construction time so `itemBuilder`s can do an O(1)
  /// lookup (for the 55%-opacity treatment) instead of recomputing the
  /// filter per item. Used by [displayEntries] to filter at display time and
  /// by `itemBuilder`s to dim entries that remain visible because
  /// [showHidden] is true.
  final Set<String> hiddenPaths;

  /// Number of [sortedEntries] currently hidden by [visibilityPrefs].
  int get hiddenCount => hiddenPaths.length;

  /// The entries to actually render: all of [sortedEntries] while
  /// [showHidden] is true (so hidden items can be shown at reduced opacity),
  /// or only the non-hidden ones otherwise.
  ///
  /// Filtering is applied HERE, at display time, rather than before
  /// [sortedEntries] is computed — this is intentional, not a "filter before
  /// sort" oversight. [sortedEntries] retains hidden entries in their sorted
  /// position precisely so that, when [showHidden] is true, this getter can
  /// return the full list and let revealed hidden entries render in place (at
  /// 55% opacity) instead of being appended/regrouped separately.
  ///
  /// The visible order is identical either way: filtering [sortedEntries]
  /// down to non-hidden paths here produces the same order as filtering
  /// [entries] first and then sorting, because [_sortEntries] is a stable
  /// directories-first partition + comparator that depends only on each
  /// entry's own fields (name/size/date/type), never on whether other entries
  /// are hidden — removing hidden entries from an already-sorted list can't
  /// reorder the survivors.
  List<Entry> get displayEntries =>
      showHidden
          ? sortedEntries
          : sortedEntries.where((e) => !hiddenPaths.contains(e.path)).toList();

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
    VisibilityPrefs? visibilityPrefs,
    bool? showHidden,
  }) => ExplorerState(
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
    visibilityPrefs: visibilityPrefs ?? this.visibilityPrefs,
    showHidden: showHidden ?? this.showHidden,
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

    // View settings (list/grid, sort order) are owned by the two-tier settings
    // model (`core/settings/`) and resolved per host (`deviceOverride ??
    // appDefault`), then mirrored into this state so `sortedEntries`/`gridView`
    // stay the single source widgets read from. `ref.listen` applies future
    // changes (e.g. from the view-options sheet or a per-device override); the
    // initial `ref.read` seeds this notifier's first state synchronously when
    // settings have already loaded (otherwise defaults apply until the listener
    // fires).
    // View settings AND file-visibility prefs are both owned by the two-tier
    // settings model (`core/settings/`) and resolved per host
    // (`deviceOverride ?? appDefault`), then mirrored into this state so
    // `sortedEntries`/`gridView`/`hiddenPaths`/`displayEntries` stay the single
    // source widgets read from. `ref.listen` applies future changes (the
    // view-options sheet, a per-device override, or an app-default visibility
    // edit); the initial `ref.read` seeds the first state synchronously when
    // settings have already loaded (otherwise defaults apply until the listener
    // fires).
    ref.listen(settingsProvider, (_, next) {
      final settings = next.valueOrNull;
      if (settings == null) return;
      final view = settings.resolveView(arg.hostId);
      state = state.copyWith(
        gridView: view.gridView,
        sort: view.sort,
        visibilityPrefs: settings.resolveVisibility(arg.hostId),
      );
    });
    final initialSettings = ref.read(settingsProvider).valueOrNull;
    final initialView = initialSettings?.resolveView(arg.hostId);
    final initialVisibilityPrefs = initialSettings?.resolveVisibility(
      arg.hostId,
    );

    // Schedule async load after construction.
    Future.microtask(_load);
    return ExplorerState(
      pathStack: [arg.rootPath],
      gridView: initialView?.gridView ?? false,
      sort: initialView?.sort ?? const SortOrder(),
      visibilityPrefs: initialVisibilityPrefs ?? const VisibilityPrefs(),
    );
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
        loading: true,
        error: null,
        selected: {},
        nextCursor: null,
      );
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

  /// Changes the **app-default** sort order (the owner's "one general setting"
  /// model — the quick controls in the view-options sheet set the global
  /// default; a per-host divergence is a deliberate override set elsewhere).
  /// The resulting state update is mirrored back here by the `ref.listen` in
  /// [build].
  void setSort(SortOrder sort) =>
      ref.read(settingsProvider.notifier).setAppSort(sort);

  /// Flips the **app-default** list/grid layout. Toggles against the current
  /// resolved value for this host, then writes the app default; hosts with an
  /// explicit override keep it. Mirrored back by the `ref.listen` in [build].
  void toggleView() =>
      ref.read(settingsProvider.notifier).setAppGridView(!state.gridView);

  /// Toggles the session-only "show hidden items" override (see
  /// [ExplorerState.showHidden]). Unlike [toggleView]/[setSort], this is
  /// local UI state for this explorer screen only — it is intentionally not
  /// persisted to the settings model's file-visibility prefs.
  void toggleShowHidden() =>
      state = state.copyWith(showHidden: !state.showHidden);

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

  /// Selects every currently-displayed entry ([ExplorerState.displayEntries]),
  /// so hidden entries the user can't see never get swept into a bulk
  /// delete/move/copy.
  void selectAll() {
    state = state.copyWith(
      selected: state.displayEntries.map((e) => e.path).toSet(),
    );
  }

  /// Flips the selection within the currently-displayed entries
  /// ([ExplorerState.displayEntries]): every currently-unselected displayed
  /// entry becomes selected and vice versa. Used by the selection app bar's
  /// "invert" action.
  void invertSelection() {
    final all = state.displayEntries.map((e) => e.path).toSet();
    state = state.copyWith(selected: all.difference(state.selected));
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

  /// Deletes the current selection. Reversible (to trash) by default; pass
  /// [permanent] `true` to hard-delete.
  Future<Map<String, dynamic>> deleteSelected({bool permanent = false}) async {
    final client = await _client();
    final res = await client.delete(
      state.selected.toList(),
      permanent: permanent,
    );
    await _load();
    return res;
  }

  Future<Map<String, dynamic>> moveSelected(
    String destDir, {
    List<String>? sources,
    bool duplicate = false,
    bool overwrite = false,
  }) async {
    final client = await _client();
    final res = await client.move(
      sources ?? state.selected.toList(),
      destDir,
      duplicate: duplicate,
      overwrite: overwrite,
    );
    await _load();
    return res;
  }

  Future<Map<String, dynamic>> copySelected(
    String destDir, {
    List<String>? sources,
    bool duplicate = false,
    bool overwrite = false,
  }) async {
    final client = await _client();
    final res = await client.copy(
      sources ?? state.selected.toList(),
      destDir,
      duplicate: duplicate,
      overwrite: overwrite,
    );
    await _load();
    return res;
  }

  /// Compresses [sources] (defaulting to the current selection) into a new
  /// zip at [dest], then reloads the listing so the archive appears. Returns
  /// the created archive's [Entry] (its `path`/`name` reflect any server-side
  /// auto-rename when [dest] already existed).
  Future<Entry> compressSelected(String dest, {List<String>? sources}) async {
    final client = await _client();
    final entry = await client.compress(
      sources ?? state.selected.toList(),
      dest,
    );
    await _load();
    return entry;
  }

  /// Extracts [archive] into [destDir] (defaulting to the current directory),
  /// then reloads the listing so the unpacked items appear. Returns the
  /// destination directory's [Entry].
  Future<Entry> extractArchive(String archive, {String? destDir}) async {
    final client = await _client();
    final entry = await client.extract(archive, destDir ?? state.currentPath);
    await _load();
    return entry;
  }

  /// Batch-renames entries. [renames] maps each existing absolute path to its
  /// new basename. Done in two phases (each source first to a unique temp name,
  /// then to its final name) so a new name colliding with another source in the
  /// same batch can't clobber it. Returns a `{results: [...]}` map compatible
  /// with `reportBatchResult`.
  Future<Map<String, dynamic>> batchRename(
    List<({String path, String newName})> renames,
  ) async {
    final client = await _client();
    final results = <Map<String, dynamic>>[];
    final pending = <String, String>{}; // finalPath -> tempPath

    Map<String, dynamic> fail(String path, Object e) => {
      'path': path,
      'ok': false,
      'error': {'code': 'RENAME_FAILED', 'message': e.toString()},
    };

    for (var i = 0; i < renames.length; i++) {
      final r = renames[i];
      final dst = renameDestination(r.path, r.newName);
      if (dst == r.path) {
        results.add({'path': r.path, 'ok': true});
        continue;
      }
      final tmp = renameDestination(r.path, '.rfe-rn-$i-${r.newName}');
      try {
        await client.rename(r.path, tmp);
        pending[dst] = tmp;
      } catch (e) {
        results.add(fail(r.path, e));
      }
    }
    for (final e in pending.entries) {
      try {
        await client.rename(e.value, e.key);
        results.add({'path': e.key, 'ok': true});
      } catch (err) {
        results.add(fail(e.value, err));
      }
    }
    await _load();
    return {'results': results};
  }

  /// Lists [destDir] and returns the basenames of [sourcePaths] that already
  /// exist there — used as a pre-flight collision check before a copy/move so
  /// the user can be offered Keep both / Overwrite / Skip *before* the
  /// operation is issued.
  ///
  /// Pages through the full listing of [destDir] (a directory can have more
  /// entries than one page) so collisions later in a large destination aren't
  /// missed.
  Future<Set<String>> collidingBasenames(
    String destDir,
    Iterable<String> sourcePaths,
  ) async {
    final client = await _client();
    final destNames = <String>{};
    String? cursor;
    do {
      final listing = await client.list(destDir, cursor: cursor);
      destNames.addAll(listing.entries.map((e) => e.name));
      cursor = listing.nextCursor;
    } while (cursor != null);

    return sourcePaths.map(basenameOf).where(destNames.contains).toSet();
  }
}

// ---------------------------------------------------------------------------
// Provider family
// ---------------------------------------------------------------------------

final explorerProvider = NotifierProvider.autoDispose
    .family<ExplorerNotifier, ExplorerState, ExplorerArg>(ExplorerNotifier.new);

/// Basename (final path component) of [path] — works for both POSIX (`/`)
/// and Windows (`\`) separators, matching the splitting used elsewhere
/// (`folderLabel`, `breadcrumb_bar.dart`, `selection_bar.dart`).
String basenameOf(String path) =>
    path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;

/// Returns a name derived from [name] that isn't in [existingNames], by
/// inserting " (1)", " (2)", … before the extension (or at the end, for an
/// extensionless name) and incrementing until free.
///
/// Used by the upload "Keep both" resolution to pick a free name in the
/// current directory, e.g. `photo.jpg` -> `photo (1).jpg` -> `photo (2).jpg`.
String dedupedName(String name, Set<String> existingNames) {
  if (!existingNames.contains(name)) return name;

  final dot = name.lastIndexOf('.');
  // No "extension" for a dotfile (`.bashrc`) or a name with no `.` at all —
  // append the suffix to the whole name in that case.
  final hasExt = dot > 0 && dot < name.length - 1;
  final base = hasExt ? name.substring(0, dot) : name;
  final ext = hasExt ? name.substring(dot) : '';

  var n = 1;
  String candidate;
  do {
    candidate = '$base ($n)$ext';
    n++;
  } while (existingNames.contains(candidate));
  return candidate;
}

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
    final parts =
        path
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
