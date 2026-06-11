import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kRecentSearchesKey = 'rfe_recent_searches_v1';

/// Maximum number of distinct recent search queries retained.
const kMaxRecentSearches = 10;

/// Reactive store of recently-submitted search queries, persisted in
/// SharedPreferences. Most-recent first, deduplicated by exact text.
class RecentSearchesNotifier extends AsyncNotifier<List<String>> {
  SharedPreferences? _prefs;

  @override
  Future<List<String>> build() async {
    _prefs = await SharedPreferences.getInstance();
    return _prefs!.getStringList(_kRecentSearchesKey) ?? [];
  }

  Future<void> _persist(List<String> queries) async {
    await _prefs?.setStringList(_kRecentSearchesKey, queries);
    state = AsyncData(queries);
  }

  /// Records [query] as the most recent search, moving it to the front if
  /// already present and trimming the list to [kMaxRecentSearches] entries.
  ///
  /// No-op for empty/whitespace-only queries.
  Future<void> record(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final current = List<String>.from(state.valueOrNull ?? []);
    current.removeWhere((s) => s == q);
    current.insert(0, q);
    if (current.length > kMaxRecentSearches) {
      current.removeRange(kMaxRecentSearches, current.length);
    }
    await _persist(current);
  }

  /// Removes a single recent query.
  Future<void> remove(String query) async {
    final current = List<String>.from(state.valueOrNull ?? [])
      ..removeWhere((s) => s == query);
    await _persist(current);
  }

  /// Clears all recent searches.
  Future<void> clear() async {
    await _persist(const []);
  }
}

final recentSearchesProvider =
    AsyncNotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);
