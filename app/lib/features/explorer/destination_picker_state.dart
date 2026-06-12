/// State + notifier for the folder-browser destination picker sheet used by
/// the Move/Copy actions (see `widgets/destination_picker_sheet.dart`).
///
/// This is intentionally a small, independent notifier rather than reusing
/// [ExplorerNotifier] directly: it only ever shows directories (filtered from
/// the same `list` response), never tracks selection/sort/grid state, and its
/// lifetime is scoped to the picker sheet (`autoDispose`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/models/entry.dart';
import 'explorer_state.dart' show buildPathStack;

/// State for the destination picker: navigation stack + the current
/// directory's folder listing.
class DestinationPickerState {
  const DestinationPickerState({
    required this.pathStack,
    this.folders = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.nextCursor,
  });

  final List<String> pathStack;

  /// Directory-only entries for [currentPath], in server order (not
  /// re-sorted — the picker doesn't expose sort options).
  final List<Entry> folders;

  final bool loading;

  /// `true` while an additional page is being fetched (pagination).
  final bool loadingMore;

  final String? error;

  /// Opaque cursor for the next page of the current directory's listing;
  /// null when there are no more pages.
  final String? nextCursor;

  String get currentPath => pathStack.last;
  bool get hasMore => nextCursor != null;

  DestinationPickerState copyWith({
    List<String>? pathStack,
    List<Entry>? folders,
    bool? loading,
    bool? loadingMore,
    Object? error = _sentinel,
    Object? nextCursor = _sentinel,
  }) =>
      DestinationPickerState(
        pathStack: pathStack ?? this.pathStack,
        folders: folders ?? this.folders,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error == _sentinel ? this.error : error as String?,
        nextCursor:
            nextCursor == _sentinel ? this.nextCursor : nextCursor as String?,
      );
}

const _sentinel = Object();

/// Key for [destinationPickerProvider]: which host to browse and the
/// directory the picker should start in (the explorer's current directory).
typedef DestinationPickerArg = ({String hostId, String startPath});

class DestinationPickerNotifier extends AutoDisposeFamilyNotifier<
    DestinationPickerState, DestinationPickerArg> {
  @override
  DestinationPickerState build(DestinationPickerArg arg) {
    // Keep the underlying client provider alive for this notifier's lifetime
    // without rebuilding on every async-value change — same pattern as
    // ExplorerNotifier.build.
    ref.listen(clientProvider(arg.hostId), (_, _) {});

    Future.microtask(_load);
    return DestinationPickerState(pathStack: buildPathStack(arg.startPath));
  }

  Future<void> _load() async {
    final path = state.currentPath;
    state = state.copyWith(loading: true, error: null, nextCursor: null);
    try {
      final client = await ref.read(clientProvider(arg.hostId).future);
      if (state.currentPath != path) return;
      final listing = await client.list(path);
      if (state.currentPath != path) return;
      state = state.copyWith(
        loading: false,
        folders: listing.entries.where((e) => e.isDir).toList(),
        error: null,
        nextCursor: listing.nextCursor,
      );
    } catch (e) {
      if (state.currentPath != path) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Loads the next page of the current directory and appends its folders.
  /// No-op if a load is already in flight or there is no further page.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;

    final path = state.currentPath;
    state = state.copyWith(loadingMore: true);
    try {
      final client = await ref.read(clientProvider(arg.hostId).future);
      if (state.currentPath != path) return;
      final listing = await client.list(path, cursor: cursor);
      if (state.currentPath != path) return;
      final merged = [
        ...state.folders,
        ...listing.entries.where((e) => e.isDir),
      ];
      state = state.copyWith(
        folders: merged,
        loadingMore: false,
        nextCursor: listing.nextCursor,
      );
    } catch (_) {
      if (state.currentPath != path) return;
      // Leave existing folders as-is; stop the spinner so the user can retry
      // by scrolling again.
      state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> refresh() => _load();

  /// Navigates into [path] (a folder shown in the current listing).
  void navigate(String path) {
    state = state.copyWith(pathStack: [...state.pathStack, path]);
    _load();
  }

  /// Jumps to the path-stack entry at [index] (breadcrumb tap).
  void navigateTo(int index) {
    if (index >= state.pathStack.length) return;
    final stack = state.pathStack.sublist(0, index + 1);
    state = state.copyWith(pathStack: stack);
    _load();
  }

  /// Creates a folder named [name] inside the current directory, then
  /// refreshes the listing so it appears immediately.
  Future<void> createFolder(String name) async {
    final client = await ref.read(clientProvider(arg.hostId).future);
    final sep = state.currentPath.contains('\\') ? r'\' : '/';
    final base = state.currentPath;
    final path = base.endsWith(sep) ? '$base$name' : '$base$sep$name';
    await client.createFolder(path);
    await _load();
  }
}

final destinationPickerProvider = NotifierProvider.autoDispose
    .family<DestinationPickerNotifier, DestinationPickerState,
        DestinationPickerArg>(
  DestinationPickerNotifier.new,
);
