import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/photo_backup/photo_backup_logic.dart';

void main() {
  group('backupRemotePath', () {
    test('lays photos out in YYYY/YYYY-MM date folders', () {
      final p = backupRemotePath(
        destRoot: '/home/u/PhoneBackup',
        created: DateTime(2026, 3, 7),
        name: 'IMG_1.jpg',
      );
      expect(p, '/home/u/PhoneBackup/2026/2026-03/IMG_1.jpg');
    });

    test('trims a trailing slash on destRoot', () {
      final p = backupRemotePath(
        destRoot: '/data/pics/',
        created: DateTime(2025, 12, 31),
        name: 'a.png',
      );
      expect(p, '/data/pics/2025/2025-12/a.png');
    });

    test('handles the filesystem root without a double slash', () {
      final p = backupRemotePath(
        destRoot: '/',
        created: DateTime(2024, 1, 9),
        name: 'x.jpg',
      );
      expect(p, '/2024/2024-01/x.jpg');
    });
  });

  group('pendingIds', () {
    test('excludes already-backed-up ids, preserving order', () {
      final pending = pendingIds(['a', 'b', 'c', 'd'], {'b', 'd'});
      expect(pending, ['a', 'c']);
    });

    test('empty backed-up set returns everything', () {
      expect(pendingIds(['a', 'b'], {}), ['a', 'b']);
    });
  });
}
