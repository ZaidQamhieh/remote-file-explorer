import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBookmarksKey = 'bookmarks_v1';

/// A bookmarked file (or folder) on a specific host, with an optional tag.
class Bookmark {
  const Bookmark({
    required this.hostId,
    required this.remotePath,
    this.tag,
    this.color,
  });

  final String hostId;
  final String remotePath;

  /// Free-form label — e.g. "work", "download later". Nullable.
  final String? tag;

  /// Optional Material color value (e.g. Colors.blue.value). Nullable.
  final int? color;

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
    hostId: j['hostId'] as String,
    remotePath: j['remotePath'] as String,
    tag: j['tag'] as String?,
    color: j['color'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'hostId': hostId,
    'remotePath': remotePath,
    if (tag != null) 'tag': tag,
    if (color != null) 'color': color,
  };
}

class BookmarkNotifier extends AsyncNotifier<List<Bookmark>> {
  SharedPreferences? _prefs;

  @override
  Future<List<Bookmark>> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_kBookmarksKey) ?? [];
    return raw
        .map((s) => Bookmark.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  List<Bookmark> get _current => List<Bookmark>.from(state.valueOrNull ?? []);

  Future<void> _persist(List<Bookmark> items) async {
    await _prefs?.setStringList(
      _kBookmarksKey,
      items.map((b) => jsonEncode(b.toJson())).toList(),
    );
    state = AsyncData(items);
  }

  bool isBookmarked(String hostId, String remotePath) =>
      (state.valueOrNull ?? []).any(
        (b) => b.hostId == hostId && b.remotePath == remotePath,
      );

  /// All bookmarks for a single host.
  List<Bookmark> bookmarksForHost(String hostId) =>
      (state.valueOrNull ?? []).where((b) => b.hostId == hostId).toList();

  List<Bookmark> allBookmarks() => state.valueOrNull ?? [];

  /// Adds a bookmark; replaces any existing bookmark for the same path.
  Future<void> addBookmark(Bookmark bookmark) async {
    final items =
        _current..removeWhere(
          (b) =>
              b.hostId == bookmark.hostId &&
              b.remotePath == bookmark.remotePath,
        );
    items.add(bookmark);
    await _persist(items);
  }

  Future<void> removeBookmark(String hostId, String remotePath) async {
    final items =
        _current..removeWhere(
          (b) => b.hostId == hostId && b.remotePath == remotePath,
        );
    await _persist(items);
  }
}

final bookmarkStoreProvider =
    AsyncNotifierProvider<BookmarkNotifier, List<Bookmark>>(
      BookmarkNotifier.new,
    );
