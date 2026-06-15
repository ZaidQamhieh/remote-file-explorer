import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/trash_entry.dart';

void main() {
  group('TrashEntry.fromJson', () {
    test('parses a full payload', () {
      final t = TrashEntry.fromJson({
        'id': 'doc.txt',
        'name': 'doc.txt',
        'originalPath': '/home/u/doc.txt',
        'deletedAt': '2026-06-16T10:00:00Z',
        'size': 42,
        'isDir': false,
      });
      expect(t.id, 'doc.txt');
      expect(t.originalPath, '/home/u/doc.txt');
      expect(t.size, 42);
      expect(t.isDir, isFalse);
      expect(t.deletedAt, isNotNull);
    });

    test('tolerates missing optional fields', () {
      final t = TrashEntry.fromJson({
        'id': 'x',
        'name': 'x',
        'originalPath': '/x',
      });
      expect(t.deletedAt, isNull);
      expect(t.size, isNull);
      expect(t.isDir, isFalse);
    });
  });
}
