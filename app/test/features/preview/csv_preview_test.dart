import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/preview/csv_preview.dart';

void main() {
  group('parseCsvRows (PR-67)', () {
    test('simple unquoted rows', () {
      expect(parseCsvRows('a,b,c\n1,2,3\n'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('trims unquoted fields', () {
      expect(parseCsvRows('a, b , c\n'), [
        ['a', 'b', 'c'],
      ]);
    });

    test('a quoted field containing a comma is kept as one field', () {
      expect(parseCsvRows('name,note\nAda,"hello, world"\n'), [
        ['name', 'note'],
        ['Ada', 'hello, world'],
      ]);
    });

    test('a doubled quote inside a quoted field is an escaped literal "', () {
      expect(parseCsvRows('note\n"she said ""hi"""\n'), [
        ['note'],
        ['she said "hi"'],
      ]);
    });

    test('a quoted field containing an embedded newline stays one row', () {
      expect(parseCsvRows('note\n"line one\nline two"\nafter\n'), [
        ['note'],
        ['line one\nline two'],
        ['after'],
      ]);
    });

    test('blank lines are dropped', () {
      expect(parseCsvRows('a,b\n\n1,2\n\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('a trailing row with no terminating newline is still parsed', () {
      expect(parseCsvRows('a,b\n1,2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('CRLF line endings are handled like LF', () {
      expect(parseCsvRows('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('empty input produces no rows', () {
      expect(parseCsvRows(''), isEmpty);
    });

    test(
      'preserves whitespace inside a quoted field (no trim, unlike unquoted)',
      () {
        expect(parseCsvRows('note\n"  padded  "\n'), [
          ['note'],
          ['  padded  '],
        ]);
      },
    );
  });
}
