import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/search_result.dart';

void main() {
  final sampleEntries = [
    {'name': 'a.txt', 'path': '/root/a.txt', 'isDir': false},
    {'name': 'b.txt', 'path': '/root/b.txt', 'isDir': false},
  ];

  group('SearchResult.fromResponse', () {
    test('parses entries with no special headers', () {
      final result = SearchResult.fromResponse(sampleEntries, {});
      expect(result.entries, hasLength(2));
      expect(result.entries.map((e) => e.name), ['a.txt', 'b.txt']);
      expect(result.truncated, isFalse);
      expect(result.timeBudgetHit, isFalse);
    });

    test('detects X-Search-Truncated: 1', () {
      final result = SearchResult.fromResponse(sampleEntries, {
        'x-search-truncated': ['1'],
      });
      expect(result.truncated, isTrue);
      expect(result.timeBudgetHit, isFalse);
    });

    test('detects X-Search-Time-Budget: 1', () {
      final result = SearchResult.fromResponse(sampleEntries, {
        'x-search-time-budget': ['1'],
      });
      expect(result.timeBudgetHit, isTrue);
      expect(result.truncated, isFalse);
    });

    test('both headers can be set simultaneously', () {
      final result = SearchResult.fromResponse(sampleEntries, {
        'x-search-truncated': ['1'],
        'x-search-time-budget': ['1'],
      });
      expect(result.truncated, isTrue);
      expect(result.timeBudgetHit, isTrue);
    });

    test('header matching is case-insensitive', () {
      final result = SearchResult.fromResponse(sampleEntries, {
        'X-Search-Truncated': ['1'],
      });
      expect(result.truncated, isTrue);
    });

    test('header values other than "1" are ignored', () {
      final result = SearchResult.fromResponse(sampleEntries, {
        'x-search-truncated': ['0'],
      });
      expect(result.truncated, isFalse);
    });

    test('handles an empty entry list', () {
      final result = SearchResult.fromResponse(const [], {});
      expect(result.entries, isEmpty);
    });
  });
}
