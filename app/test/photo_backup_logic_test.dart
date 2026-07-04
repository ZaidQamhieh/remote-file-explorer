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

  group('albumsToScan', () {
    test('empty selection means all photos (every available album)', () {
      expect(albumsToScan(['x', 'y', 'z'], {}), ['x', 'y', 'z']);
    });

    test('filters to the selected albums, preserving available order', () {
      expect(albumsToScan(['x', 'y', 'z'], {'z', 'x'}), ['x', 'z']);
    });

    test('drops a selected album that no longer exists on the device', () {
      expect(albumsToScan(['x', 'y'], {'y', 'gone'}), ['y']);
    });
  });

  group('isFileStable', () {
    test('false immediately when the first read is zero-byte', () async {
      var waited = false;
      final stable = await isFileStable(
        () async => 0,
        wait: (_) async => waited = true,
      );
      expect(stable, isFalse);
      expect(waited, isFalse); // no point waiting on an empty file
    });

    test('false when the length is still growing between reads', () async {
      final lengths = [100, 250];
      var i = 0;
      final stable = await isFileStable(
        () async => lengths[i++],
        wait: (_) async {},
      );
      expect(stable, isFalse);
    });

    test('true once two reads a beat apart agree and are non-zero', () async {
      final stable = await isFileStable(() async => 4096, wait: (_) async {});
      expect(stable, isTrue);
    });
  });
}
