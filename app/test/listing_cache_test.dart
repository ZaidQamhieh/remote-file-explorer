import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/storage/listing_cache.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('rfe_cache_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Entry mkEntry(String name) => Entry(
    name: name,
    path: '/root/$name',
    isDir: false,
    size: 1,
    mimeType: 'text/plain',
    mode: '-rw-r--r--',
    modified: DateTime(2026, 1, 1),
    created: DateTime(2026, 1, 1),
    isSymlink: false,
  );

  test('put then get round-trips entries', () async {
    final cache = ListingCache(baseDir: tmp);
    await cache.put('host-1', '/root', [mkEntry('a.txt'), mkEntry('b.txt')]);

    final got = await cache.get('host-1', '/root');
    expect(got, isNotNull);
    expect(got!.entries.map((e) => e.name), ['a.txt', 'b.txt']);
    expect(
      got.fetchedAt.isBefore(DateTime.now().add(const Duration(seconds: 1))),
      isTrue,
    );
  });

  test('get returns null for unknown path', () async {
    final cache = ListingCache(baseDir: tmp);
    expect(await cache.get('host-1', '/nope'), isNull);
  });

  test('evicts oldest beyond capacity', () async {
    final cache = ListingCache(baseDir: tmp, maxEntries: 2);
    await cache.put('h', '/p1', [mkEntry('1')]);
    await Future.delayed(const Duration(milliseconds: 5));
    await cache.put('h', '/p2', [mkEntry('2')]);
    await Future.delayed(const Duration(milliseconds: 5));
    await cache.put('h', '/p3', [mkEntry('3')]); // evicts /p1

    expect(await cache.get('h', '/p1'), isNull);
    expect(await cache.get('h', '/p2'), isNotNull);
    expect(await cache.get('h', '/p3'), isNotNull);
  });
}
