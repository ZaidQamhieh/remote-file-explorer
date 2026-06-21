import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSavedSearchesKey = 'rfe_saved_searches_v1';

/// A named, persisted search configuration.
class SavedSearch {
  const SavedSearch({required this.name, required this.query});

  final String name;
  final String query;

  Map<String, dynamic> toJson() => {'name': name, 'query': query};

  factory SavedSearch.fromJson(Map<String, dynamic> json) => SavedSearch(
    name: json['name'] as String? ?? '',
    query: json['query'] as String? ?? '',
  );
}

class SavedSearchesNotifier extends AsyncNotifier<List<SavedSearch>> {
  SharedPreferences? _prefs;

  @override
  Future<List<SavedSearch>> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kSavedSearchesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SavedSearch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _persist(List<SavedSearch> searches) async {
    await _prefs?.setString(
      _kSavedSearchesKey,
      jsonEncode(searches.map((s) => s.toJson()).toList()),
    );
    state = AsyncData(searches);
  }

  Future<void> add(SavedSearch search) async {
    final current = List<SavedSearch>.from(state.valueOrNull ?? []);
    current.insert(0, search);
    await _persist(current);
  }

  Future<void> remove(String name) async {
    final current = List<SavedSearch>.from(state.valueOrNull ?? [])
      ..removeWhere((s) => s.name == name);
    await _persist(current);
  }
}

final savedSearchesProvider =
    AsyncNotifierProvider<SavedSearchesNotifier, List<SavedSearch>>(
      SavedSearchesNotifier.new,
    );
