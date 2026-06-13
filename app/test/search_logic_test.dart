import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/storage/visibility_prefs.dart';
import 'package:remote_file_explorer/features/search/search_logic.dart';

void main() {
  Entry mkEntry(String name, {bool isDir = false}) => Entry(
        name: name,
        path: '/root/$name',
        isDir: isDir,
      );

  group('isGlobQuery', () {
    test('detects * and ? as glob markers', () {
      expect(isGlobQuery('*.txt'), isTrue);
      expect(isGlobQuery('file?.dat'), isTrue);
      expect(isGlobQuery('plain'), isFalse);
      expect(isGlobQuery(''), isFalse);
    });
  });

  group('sortByRelevance', () {
    test('starts-with matches come before other matches', () {
      final entries = [
        mkEntry('zzz_report.txt'),
        mkEntry('report_final.txt'),
        mkEntry('Report.txt'),
      ];
      final sorted = sortByRelevance(entries, 'report');
      expect(sorted.map((e) => e.name).toList(), [
        'Report.txt', // starts with "report" (case-insensitive)
        'report_final.txt', // starts with "report"
        'zzz_report.txt', // contains but doesn't start with
      ]);
    });

    test('alphabetical within each relevance group, case-insensitive', () {
      final entries = [
        mkEntry('report_b.txt'),
        mkEntry('Report_a.txt'),
        mkEntry('xx_report.txt'),
        mkEntry('aa_report.txt'),
      ];
      final sorted = sortByRelevance(entries, 'report');
      expect(sorted.map((e) => e.name).toList(), [
        'Report_a.txt',
        'report_b.txt',
        'aa_report.txt',
        'xx_report.txt',
      ]);
    });

    test('glob queries are sorted purely alphabetically', () {
      final entries = [
        mkEntry('zzz.txt'),
        mkEntry('report.txt'),
        mkEntry('aaa_report.txt'),
      ];
      final sorted = sortByRelevance(entries, '*.txt');
      expect(sorted.map((e) => e.name).toList(), [
        'aaa_report.txt',
        'report.txt',
        'zzz.txt',
      ]);
    });

    test('empty query is sorted alphabetically', () {
      final entries = [mkEntry('b'), mkEntry('a'), mkEntry('c')];
      final sorted = sortByRelevance(entries, '');
      expect(sorted.map((e) => e.name).toList(), ['a', 'b', 'c']);
    });

    test('does not mutate the input list', () {
      final entries = [mkEntry('b'), mkEntry('a')];
      final original = List<Entry>.from(entries);
      sortByRelevance(entries, '');
      expect(entries.map((e) => e.name), original.map((e) => e.name));
    });
  });

  group('filterSearchResults', () {
    final results = [
      mkEntry('readme.txt'),
      mkEntry('.env'),
      mkEntry('app.log'),
    ];

    test('filters out entries hidden by visibility prefs by default', () {
      const prefs = VisibilityPrefs(hiddenExtensions: {'log'});
      final filtered =
          filterSearchResults(results, prefs, includeHidden: false);
      expect(filtered.map((e) => e.name), ['readme.txt']);
    });

    test('includeHidden: true returns results unchanged', () {
      const prefs = VisibilityPrefs(hiddenExtensions: {'log'});
      final filtered =
          filterSearchResults(results, prefs, includeHidden: true);
      expect(filtered, results);
    });
  });

  group('highlightRange', () {
    test('finds the case-insensitive match range', () {
      final range = highlightRange('My Report.PDF', 'report');
      expect(range, const HighlightRange(3, 9));
    });

    test('returns null when there is no match', () {
      expect(highlightRange('document.txt', 'xyz'), isNull);
    });

    test('returns null for an empty query', () {
      expect(highlightRange('document.txt', ''), isNull);
    });

    test('returns null for glob queries', () {
      expect(highlightRange('document.txt', '*.txt'), isNull);
      expect(highlightRange('document.txt', 'doc?ment'), isNull);
    });

    test('highlights only the first occurrence', () {
      final range = highlightRange('foo_foo.txt', 'foo');
      expect(range, const HighlightRange(0, 3));
    });
  });
}
