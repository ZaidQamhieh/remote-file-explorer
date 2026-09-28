import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/offline_body_cache.dart';

class _MemoryKeyStore implements OfflineBodyCacheKeyStore {
  Uint8List? key;
  bool failReads = false;

  @override
  Future<Uint8List?> readKey() async {
    if (failReads) throw StateError('secure storage unavailable');
    final value = key;
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> writeKey(Uint8List value) async {
    key = Uint8List.fromList(value);
  }
}

void main() {
  late Directory tmpDir;
  late _MemoryKeyStore keyStore;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('offline_body_cache_test_');
    keyStore = _MemoryKeyStore();
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  OfflineBodyCache cache() =>
      OfflineBodyCache(baseDir: tmpDir, keyStore: keyStore);

  Directory getCacheDir() => Directory('${tmpDir.path}/offline_cache');

  String cacheFilename(String hostId, String path) =>
      base64Url.encode(utf8.encode('$hostId:$path')).replaceAll('=', '');

  test('put / get / has / remove roundtrip', () async {
    final offlineCache = cache();
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    expect(await offlineCache.has('h1', '/foo/bar.txt'), isFalse);
    expect(await offlineCache.get('h1', '/foo/bar.txt'), isNull);

    await offlineCache.put('h1', '/foo/bar.txt', bytes);

    expect(await offlineCache.has('h1', '/foo/bar.txt'), isTrue);
    expect(await offlineCache.get('h1', '/foo/bar.txt'), equals(bytes));

    await offlineCache.remove('h1', '/foo/bar.txt');

    expect(await offlineCache.has('h1', '/foo/bar.txt'), isFalse);
    expect(await offlineCache.get('h1', '/foo/bar.txt'), isNull);
  });

  test(
    'cached file contains ciphertext and key remains outside cache files',
    () async {
      final offlineCache = cache();
      final body = Uint8List.fromList(utf8.encode('private document contents'));
      await offlineCache.put('h1', '/private.txt', body);

      final file = File(
        '${getCacheDir().path}/${cacheFilename('h1', '/private.txt')}',
      );
      final stored = await file.readAsBytes();
      expect(
        utf8.decode(stored, allowMalformed: true),
        isNot(contains('private document contents')),
      );
      expect(stored.length, body.length + 8 + 12 + 16);
      expect(keyStore.key, hasLength(32));

      final files = await getCacheDir().list().toList();
      expect(files.whereType<File>(), hasLength(1));
    },
  );

  test('different hosts with the same path have separate entries', () async {
    final offlineCache = cache();
    final a = Uint8List.fromList([1]);
    final b = Uint8List.fromList([2]);

    await offlineCache.put('h1', '/file.txt', a);
    await offlineCache.put('h2', '/file.txt', b);

    expect(await offlineCache.get('h1', '/file.txt'), equals(a));
    expect(await offlineCache.get('h2', '/file.txt'), equals(b));
  });

  test('tampered authenticated data is deleted and never returned', () async {
    final offlineCache = cache();
    await offlineCache.put('h1', '/file.txt', Uint8List.fromList([1, 2, 3]));
    final file = File(
      '${getCacheDir().path}/${cacheFilename('h1', '/file.txt')}',
    );
    final stored = await file.readAsBytes();
    stored[stored.length - 1] ^= 0xff;
    await file.writeAsBytes(stored, flush: true);

    await expectLater(
      offlineCache.get('h1', '/file.txt'),
      throwsA(isA<OfflineBodyCacheIntegrityException>()),
    );
    expect(await file.exists(), isFalse);
    expect(await offlineCache.has('h1', '/file.txt'), isFalse);
  });

  test('missing secure key makes old encrypted bodies unavailable', () async {
    final firstCache = cache();
    await firstCache.put('h1', '/file.txt', Uint8List.fromList([7, 8]));
    keyStore.key = null;

    final afterKeyLoss = cache();
    expect(await afterKeyLoss.get('h1', '/file.txt'), isNull);
    expect(await afterKeyLoss.has('h1', '/file.txt'), isFalse);
    expect(
      await File(
        '${getCacheDir().path}/${cacheFilename('h1', '/file.txt')}',
      ).exists(),
      isFalse,
    );
  });

  test('secure storage errors fail closed and write no cache body', () async {
    keyStore.failReads = true;
    final offlineCache = cache();

    await expectLater(
      offlineCache.put('h1', '/file.txt', Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
    expect(await getCacheDir().list().toList(), isEmpty);
  });

  test('legacy plaintext files are deleted and never returned', () async {
    final dir = getCacheDir();
    await dir.create(recursive: true);
    final legacy = File('${dir.path}/${cacheFilename('h1', '/legacy.txt')}');
    await legacy.writeAsBytes(utf8.encode('plaintext legacy document'));

    final offlineCache = cache();
    expect(await offlineCache.has('h1', '/legacy.txt'), isFalse);
    expect(await offlineCache.get('h1', '/legacy.txt'), isNull);
    expect(await legacy.exists(), isFalse);
    expect(await offlineCache.totalBytes(), 0);
  });

  test('evictHost removes only that host entries', () async {
    final offlineCache = cache();
    await offlineCache.put('h1', '/a.txt', Uint8List.fromList([1]));
    await offlineCache.put('h1', '/b.txt', Uint8List.fromList([2]));
    await offlineCache.put('h2', '/c.txt', Uint8List.fromList([3]));

    await offlineCache.evictHost('h1');

    expect(await offlineCache.has('h1', '/a.txt'), isFalse);
    expect(await offlineCache.has('h1', '/b.txt'), isFalse);
    expect(await offlineCache.has('h2', '/c.txt'), isTrue);
  });

  test('evictHost on non-existent host is a no-op', () async {
    final offlineCache = cache();
    await expectLater(offlineCache.evictHost('ghost'), completes);
  });

  group('totalBytes', () {
    test('is zero for an empty cache', () async {
      expect(await cache().totalBytes(), 0);
    });

    test('sums stored encrypted file sizes across hosts', () async {
      final offlineCache = cache();
      await offlineCache.put('h1', '/a.txt', Uint8List(10));
      await offlineCache.put('h1', '/b.txt', Uint8List(20));
      await offlineCache.put('h2', '/c.txt', Uint8List(5));

      expect(await offlineCache.totalBytes(), 3 * (8 + 12 + 16) + 35);
    });

    test('drops after remove and host eviction', () async {
      final offlineCache = cache();
      await offlineCache.put('h1', '/a.txt', Uint8List(10));
      await offlineCache.put('h1', '/b.txt', Uint8List(20));

      await offlineCache.remove('h1', '/a.txt');
      expect(await offlineCache.totalBytes(), 8 + 12 + 16 + 20);

      await offlineCache.evictHost('h1');
      expect(await offlineCache.totalBytes(), 0);
    });
  });
}
