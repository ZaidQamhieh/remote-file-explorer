import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFavoritesKey = 'rfe_favorites_v1';

/// A bookmarked folder on a specific host.
class Favorite {
  const Favorite({
    required this.hostId,
    required this.path,
    required this.label,
  });

  final String hostId;
  final String path;
  final String label;

  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(
        hostId: j['hostId'] as String,
        path: j['path'] as String,
        label: j['label'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'hostId': hostId, 'path': path, 'label': label};
}

/// Reactive store of favorites, persisted in SharedPreferences.
class FavoritesNotifier extends AsyncNotifier<List<Favorite>> {
  SharedPreferences? _prefs;

  @override
  Future<List<Favorite>> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_kFavoritesKey) ?? [];
    return raw
        .map((s) => Favorite.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  List<Favorite> get _current => List<Favorite>.from(state.valueOrNull ?? []);

  Future<void> _persist(List<Favorite> favs) async {
    await _prefs?.setStringList(
      _kFavoritesKey,
      favs.map((f) => jsonEncode(f.toJson())).toList(),
    );
    state = AsyncData(favs);
  }

  bool isFavorite(String hostId, String path) =>
      (state.valueOrNull ?? [])
          .any((f) => f.hostId == hostId && f.path == path);

  /// Favorites for a single host, in saved order.
  List<Favorite> forHost(String hostId) =>
      (state.valueOrNull ?? []).where((f) => f.hostId == hostId).toList();

  Future<void> add(Favorite fav) async {
    final favs = _current;
    if (favs.any((f) => f.hostId == fav.hostId && f.path == fav.path)) return;
    favs.add(fav);
    await _persist(favs);
  }

  Future<void> remove(String hostId, String path) async {
    final favs = _current
      ..removeWhere((f) => f.hostId == hostId && f.path == path);
    await _persist(favs);
  }

  Future<void> toggle(Favorite fav) async {
    if (isFavorite(fav.hostId, fav.path)) {
      await remove(fav.hostId, fav.path);
    } else {
      await add(fav);
    }
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(
  FavoritesNotifier.new,
);
