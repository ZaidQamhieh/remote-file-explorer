import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class CacheStats {
  const CacheStats({this.listingBytes = 0, this.tempBytes = 0});

  final int listingBytes;
  final int tempBytes;

  int get totalBytes => listingBytes + tempBytes;
}

class CacheManager {
  Future<CacheStats> computeStats() async {
    final results = await Future.wait([
      _dirSize(await _listingCacheDir()),
      _dirSize(await getTemporaryDirectory()),
    ]);
    return CacheStats(listingBytes: results[0], tempBytes: results[1]);
  }

  Future<void> clearListingCache() async {
    final dir = await _listingCacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> clearTempFiles() async {
    final dir = await getTemporaryDirectory();
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> clearAll() async {
    await Future.wait([clearListingCache(), clearTempFiles()]);
  }

  Future<Directory> _listingCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/listing_cache');
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}

final cacheManagerProvider = Provider((_) => CacheManager());

final cacheStatsProvider = FutureProvider.autoDispose<CacheStats>((ref) {
  return ref.read(cacheManagerProvider).computeStats();
});
