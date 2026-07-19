import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/storage/listing_cache.dart';

// Minimal Entry factory for tests.
Entry _entry(String name) => Entry(
  name: name,
  path: '/$name',
  isDir: false,
  size: 0,
  modified: null,
  mimeType: null,
);

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('listing_cache_test_');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('put / get round-trip', () async {
    final cache = ListingCache(baseDir: tmpDir);
    await cache.put('host1', '/foo', [_entry('bar')]);
    final listing = await cache.get('host1', '/foo');
    expect(listing, isNotNull);
    expect(listing!.entries, hasLength(1));
    expect(listing.entries.first.name, equals('bar'));
  });

  test('eviction removes oldest entry beyond maxEntries', () async {
    final cache = ListingCache(baseDir: tmpDir, maxEntries: 2);

    // Add small delay so fetchedAt timestamps are distinct.
    await cache.put('h1', '/a', [_entry('a')]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.put('h1', '/b', [_entry('b')]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    // This third put should evict /a (oldest).
    await cache.put('h1', '/c', [_entry('c')]);

    expect(await cache.get('h1', '/a'), isNull);
    expect(await cache.get('h1', '/b'), isNotNull);
    expect(await cache.get('h1', '/c'), isNotNull);
  });

  test('pinned entry survives eviction that would normally remove it', () async {
    final cache = ListingCache(baseDir: tmpDir, maxEntries: 2);

    await cache.put('h1', '/pinned', [_entry('pinned')]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.put('h1', '/b', [_entry('b')]);

    // Pin /pinned so eviction skips it.
    cache.setPinned('h1:/pinned', true);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    // This third put would normally evict /pinned (oldest), but it is pinned.
    await cache.put('h1', '/c', [_entry('c')]);

    // /pinned must survive; /b is the next-oldest and should be evicted instead.
    expect(await cache.get('h1', '/pinned'), isNotNull);
    expect(await cache.get('h1', '/c'), isNotNull);
    expect(await cache.get('h1', '/b'), isNull);
  });

  test('setPinned(false) allows entry to be evicted again', () async {
    final cache = ListingCache(baseDir: tmpDir, maxEntries: 2);

    await cache.put('h1', '/was-pinned', [_entry('wp')]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.put('h1', '/b', [_entry('b')]);

    cache.setPinned('h1:/was-pinned', true);
    cache.setPinned('h1:/was-pinned', false); // unpin

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.put('h1', '/c', [_entry('c')]);

    // /was-pinned is oldest and no longer protected — should be evicted.
    expect(await cache.get('h1', '/was-pinned'), isNull);
  });

  test(
    'concurrent put() calls for the same host do not lose an entry (PR-49)',
    () async {
      final cache = ListingCache(baseDir: tmpDir);

      // Fire without awaiting, so both read-modify-write cycles overlap.
      final a = cache.put('h1', '/a', [_entry('a')]);
      final b = cache.put('h1', '/b', [_entry('b')]);
      await Future.wait([a, b]);

      expect(await cache.get('h1', '/a'), isNotNull);
      expect(await cache.get('h1', '/b'), isNotNull);
    },
  );
}
