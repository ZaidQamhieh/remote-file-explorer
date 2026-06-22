import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/dup_finder_screen.dart';

void main() {
  group('groupDuplicates', () {
    test('returns empty list when all hashes are unique', () {
      final hashes = {'/a.txt': 'aaa', '/b.txt': 'bbb', '/c.txt': 'ccc'};
      final sizes = {'/a.txt': 100, '/b.txt': 200, '/c.txt': 300};
      expect(groupDuplicates(hashes, sizes), isEmpty);
    });

    test('groups paths sharing the same hash', () {
      final hashes = {'/a.txt': 'aaa', '/b.txt': 'aaa', '/c.txt': 'bbb'};
      final sizes = {'/a.txt': 100, '/b.txt': 100, '/c.txt': 200};
      final groups = groupDuplicates(hashes, sizes);
      expect(groups.length, 1);
      expect(groups.first, containsAll(['/a.txt', '/b.txt']));
    });

    test('multiple duplicate groups', () {
      final hashes = {
        '/a.txt': 'h1',
        '/b.txt': 'h1',
        '/c.txt': 'h2',
        '/d.txt': 'h2',
        '/e.txt': 'h3',
      };
      final sizes = {
        '/a.txt': 50,
        '/b.txt': 50,
        '/c.txt': 200,
        '/d.txt': 200,
        '/e.txt': 999,
      };
      final groups = groupDuplicates(hashes, sizes);
      expect(groups.length, 2);
    });

    test('sorts groups by descending file size', () {
      final hashes = {
        '/small1': 'hs',
        '/small2': 'hs',
        '/big1': 'hb',
        '/big2': 'hb',
      };
      final sizes = {
        '/small1': 10,
        '/small2': 10,
        '/big1': 9999,
        '/big2': 9999,
      };
      final groups = groupDuplicates(hashes, sizes);
      expect(groups.length, 2);
      // First group should be the larger files
      expect(groups.first, containsAll(['/big1', '/big2']));
      expect(groups.last, containsAll(['/small1', '/small2']));
    });

    test('returns empty list for empty input', () {
      expect(groupDuplicates({}, {}), isEmpty);
    });

    test('handles three copies of the same file', () {
      final hashes = {'/a': 'h1', '/b': 'h1', '/c': 'h1'};
      final sizes = {'/a': 100, '/b': 100, '/c': 100};
      final groups = groupDuplicates(hashes, sizes);
      expect(groups.length, 1);
      expect(groups.first.length, 3);
    });
  });

  group('computeWaste', () {
    test('zero waste for no groups', () {
      expect(computeWaste([], {}), 0);
    });

    test('waste is size * (copies - 1) per group', () {
      final groups = [
        ['/a', '/b'], // 2 copies of 100 bytes -> 100 wasted
      ];
      final sizes = {'/a': 100, '/b': 100};
      expect(computeWaste(groups, sizes), 100);
    });

    test('three copies waste 2x the file size', () {
      final groups = [
        ['/a', '/b', '/c'], // 3 copies of 500 bytes -> 1000 wasted
      ];
      final sizes = {'/a': 500, '/b': 500, '/c': 500};
      expect(computeWaste(groups, sizes), 1000);
    });

    test('sums waste across multiple groups', () {
      final groups = [
        ['/a', '/b'], // 100 * 1 = 100 wasted
        ['/c', '/d', '/e'], // 200 * 2 = 400 wasted
      ];
      final sizes = {'/a': 100, '/b': 100, '/c': 200, '/d': 200, '/e': 200};
      expect(computeWaste(groups, sizes), 500);
    });

    test('missing size treated as zero', () {
      final groups = [
        ['/a', '/b'],
      ];
      expect(computeWaste(groups, {}), 0);
    });
  });
}
