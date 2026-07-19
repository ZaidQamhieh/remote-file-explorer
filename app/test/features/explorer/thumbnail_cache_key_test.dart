// Tests for thumbnailCacheKey (PR-16: cross-host thumbnail cache leak +
// stale-file staleness), the pure key-builder behind ThumbnailImage's cache.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/thumbnail_image.dart';

void main() {
  group('thumbnailCacheKey', () {
    test('same path on two different hosts produces different keys', () {
      final a = thumbnailCacheKey(
        hostId: 'host-a',
        path: '/home/user/photo.jpg',
        size: 256,
        version: 1000,
      );
      final b = thumbnailCacheKey(
        hostId: 'host-b',
        path: '/home/user/photo.jpg',
        size: 256,
        version: 1000,
      );
      expect(a, isNot(b));
    });

    test('a replaced file (new version) produces a different key', () {
      final before = thumbnailCacheKey(
        hostId: 'host-a',
        path: '/home/user/photo.jpg',
        size: 256,
        version: 1000,
      );
      final after = thumbnailCacheKey(
        hostId: 'host-a',
        path: '/home/user/photo.jpg',
        size: 256,
        version: 2000,
      );
      expect(before, isNot(after));
    });

    test('same host/path/size/version is stable', () {
      String build() => thumbnailCacheKey(
        hostId: 'host-a',
        path: '/home/user/photo.jpg',
        size: 256,
        version: 1000,
      );
      expect(build(), build());
    });
  });
}
