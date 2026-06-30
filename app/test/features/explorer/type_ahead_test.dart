// Tests for P2's type-ahead jump: firstMatchIndex (the pure core of
// _ExplorerScreenState._handleTypeAheadKey in explorer_screen.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/features/explorer/explorer_screen.dart';

Entry _entry(String name) =>
    Entry(name: name, path: '/root/$name', isDir: false);

void main() {
  group('firstMatchIndex', () {
    test('empty list returns null', () {
      expect(firstMatchIndex(const [], 'a'), isNull);
    });

    test('empty typed query returns null', () {
      final entries = [_entry('alpha.txt')];
      expect(firstMatchIndex(entries, ''), isNull);
    });

    test('no match returns null', () {
      final entries = [_entry('alpha.txt'), _entry('beta.txt')];
      expect(firstMatchIndex(entries, 'zzz'), isNull);
    });

    test('single match returns its index', () {
      final entries = [_entry('alpha.txt'), _entry('beta.txt')];
      expect(firstMatchIndex(entries, 'bet'), 1);
    });

    test('multiple matches picks the first', () {
      final entries = [
        _entry('zeta.txt'),
        _entry('beta1.txt'),
        _entry('beta2.txt'),
      ];
      expect(firstMatchIndex(entries, 'beta'), 1);
    });

    test('case-insensitive', () {
      final entries = [_entry('Alpha.txt')];
      expect(firstMatchIndex(entries, 'ALPH'), 0);
      expect(firstMatchIndex(entries, 'alph'), 0);
    });
  });
}
