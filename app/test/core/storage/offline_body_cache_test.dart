import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/offline_body_cache.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('offline_body_cache_test_');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('put / get / has / remove roundtrip', () async {
    final cache = OfflineBodyCache(baseDir: tmpDir);
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    expect(await cache.has('h1', '/foo/bar.txt'), isFalse);
    expect(await cache.get('h1', '/foo/bar.txt'), isNull);

    await cache.put('h1', '/foo/bar.txt', bytes);

    expect(await cache.has('h1', '/foo/bar.txt'), isTrue);
    expect(await cache.get('h1', '/foo/bar.txt'), equals(bytes));

    await cache.remove('h1', '/foo/bar.txt');

    expect(await cache.has('h1', '/foo/bar.txt'), isFalse);
    expect(await cache.get('h1', '/foo/bar.txt'), isNull);
  });

  test('different hosts with the same path have separate entries', () async {
    final cache = OfflineBodyCache(baseDir: tmpDir);
    final a = Uint8List.fromList([1]);
    final b = Uint8List.fromList([2]);

    await cache.put('h1', '/file.txt', a);
    await cache.put('h2', '/file.txt', b);

    expect(await cache.get('h1', '/file.txt'), equals(a));
    expect(await cache.get('h2', '/file.txt'), equals(b));
  });

  test('evictHost removes only that host entries', () async {
    final cache = OfflineBodyCache(baseDir: tmpDir);
    await cache.put('h1', '/a.txt', Uint8List.fromList([1]));
    await cache.put('h1', '/b.txt', Uint8List.fromList([2]));
    await cache.put('h2', '/c.txt', Uint8List.fromList([3]));

    await cache.evictHost('h1');

    expect(await cache.has('h1', '/a.txt'), isFalse);
    expect(await cache.has('h1', '/b.txt'), isFalse);
    expect(await cache.has('h2', '/c.txt'), isTrue);
  });

  test('evictHost on non-existent host is a no-op', () async {
    final cache = OfflineBodyCache(baseDir: tmpDir);
    await expectLater(cache.evictHost('ghost'), completes);
  });

  group('totalBytes (PR-29)', () {
    test('is zero for an empty cache', () async {
      final cache = OfflineBodyCache(baseDir: tmpDir);
      expect(await cache.totalBytes(), 0);
    });

    test('sums every cached file across all hosts', () async {
      final cache = OfflineBodyCache(baseDir: tmpDir);
      await cache.put('h1', '/a.txt', Uint8List(10));
      await cache.put('h1', '/b.txt', Uint8List(20));
      await cache.put('h2', '/c.txt', Uint8List(5));

      expect(await cache.totalBytes(), 35);
    });

    test('drops back down after remove/evictHost', () async {
      final cache = OfflineBodyCache(baseDir: tmpDir);
      await cache.put('h1', '/a.txt', Uint8List(10));
      await cache.put('h1', '/b.txt', Uint8List(20));

      await cache.remove('h1', '/a.txt');
      expect(await cache.totalBytes(), 20);

      await cache.evictHost('h1');
      expect(await cache.totalBytes(), 0);
    });
  });
}
