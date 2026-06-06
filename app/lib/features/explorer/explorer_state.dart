import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/models/host.dart';

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
// Explorer state
// ---------------------------------------------------------------------------

class ExplorerState {
  const ExplorerState({
    required this.host,
    required this.pathStack,
    this.entries = const [],
    this.loading = false,
    this.error,
    this.sort = const SortOrder(),
    this.gridView = false,
    this.selected = const {},
  });

  final Host host;
  final List<String> pathStack;
  final List<Entry> entries;
  final bool loading;
  final String? error;
  final SortOrder sort;
  final bool gridView;
  final Set<String> selected;

  String get currentPath => pathStack.last;
  bool get atRoot => pathStack.length == 1;
  bool get multiSelect => selected.isNotEmpty;

  List<Entry> get sortedEntries {
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
          r = (a.modified ?? DateTime(0))
              .compareTo(b.modified ?? DateTime(0));
        case SortField.type:
          r = (a.mimeType ?? '').compareTo(b.mimeType ?? '');
      }
      return sort.ascending ? r : -r;
    }

    dirs.sort(cmp);
    files.sort(cmp);
    return [...dirs, ...files];
  }

  ExplorerState copyWith({
    List<String>? pathStack,
    List<Entry>? entries,
    bool? loading,
    Object? error = _sentinel,
    SortOrder? sort,
    bool? gridView,
    Set<String>? selected,
  }) =>
      ExplorerState(
        host: host,
        pathStack: pathStack ?? this.pathStack,
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        error: error == _sentinel ? this.error : error as String?,
        sort: sort ?? this.sort,
        gridView: gridView ?? this.gridView,
        selected: selected ?? this.selected,
      );
}

const _sentinel = Object();

// ---------------------------------------------------------------------------
// Arg type for the explorer family provider
// ---------------------------------------------------------------------------

typedef ExplorerArg = ({Host host, String rootPath, AgentClient client});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ExplorerNotifier extends FamilyNotifier<ExplorerState, ExplorerArg> {
  @override
  ExplorerState build(ExplorerArg arg) {
    // Schedule async load after construction.
    Future.microtask(_load);
    return ExplorerState(host: arg.host, pathStack: [arg.rootPath]);
  }

  Future<void> _load() async {
    state = state.copyWith(loading: true, error: null, selected: {});
    try {
      final listing = await arg.client.list(state.currentPath);
      state = state.copyWith(loading: false, entries: listing.entries);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
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
    final path = '${state.currentPath}/$name';
    await arg.client.createFolder(path);
    await _load();
  }

  Future<void> createFile(String name) async {
    final path = '${state.currentPath}/$name';
    await arg.client.createFile(path);
    await _load();
  }

  Future<void> rename(String oldPath, String newName) async {
    final sep = oldPath.contains('/') ? '/' : r'\';
    final idx = oldPath.lastIndexOf(sep);
    final parent = idx <= 0 ? sep : oldPath.substring(0, idx);
    final dst = '$parent/$newName';
    await arg.client.rename(oldPath, dst);
    await _load();
  }

  Future<void> deleteSelected({bool permanent = false}) async {
    await arg.client.delete(state.selected.toList(), permanent: permanent);
    await _load();
  }

  Future<void> moveSelected(String destDir) async {
    await arg.client.move(state.selected.toList(), destDir);
    await _load();
  }

  Future<void> copySelected(String destDir) async {
    await arg.client.copy(state.selected.toList(), destDir);
    await _load();
  }
}

// ---------------------------------------------------------------------------
// Provider family
// ---------------------------------------------------------------------------

final explorerProvider =
    NotifierProvider.family<ExplorerNotifier, ExplorerState, ExplorerArg>(
  ExplorerNotifier.new,
);
