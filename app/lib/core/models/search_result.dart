import 'entry.dart';

/// Result of a `GET /v1/search` call: the matched [entries] plus flags
/// derived from the response headers indicating whether the server held
/// results back.
class SearchResult {
  const SearchResult({
    required this.entries,
    this.truncated = false,
    this.timeBudgetHit = false,
  });

  /// Matching entries, in server-returned order.
  final List<Entry> entries;

  /// `true` when `X-Search-Truncated: 1` was present — the result count hit
  /// [limit] and there may be more matches that weren't returned.
  final bool truncated;

  /// `true` when `X-Search-Time-Budget: 1` was present — the server's walk
  /// time budget expired before finishing, so [entries] may be incomplete
  /// even if [truncated] is false.
  final bool timeBudgetHit;

  /// Builds a [SearchResult] from the decoded JSON array body and the raw
  /// response [headers] map (header names matched case-insensitively).
  factory SearchResult.fromResponse(
    List<dynamic> data,
    Map<String, List<String>> headers,
  ) {
    return SearchResult(
      entries:
          data.map((e) => Entry.fromJson(e as Map<String, dynamic>)).toList(),
      truncated: _flagSet(headers, 'x-search-truncated'),
      timeBudgetHit: _flagSet(headers, 'x-search-time-budget'),
    );
  }

  static bool _flagSet(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) {
        return entry.value.any((v) => v.trim() == '1');
      }
    }
    return false;
  }
}
