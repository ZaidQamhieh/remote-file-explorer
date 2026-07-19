import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Aggregate byte budget for the whole offline body cache across all hosts
/// (PR-29, partial): callers that pre-cache a folder for offline access
/// (see `ExplorerNotifier._preCacheCurrentEntries`) check [totalBytes]
/// against this before writing more, so pinning many large folders can't
/// grow the cache unboundedly. Per-file/per-folder budgets, free-space
/// checks, and LRU eviction are still unaddressed — this only stops the
/// aggregate from growing past a fixed cap.
const int kOfflineCacheMaxBytes = 500 * 1024 * 1024;

/// Persists raw file bytes for offline access.
///
/// Storage: `<app-support>/offline_cache/<key>` where the key is the
/// base64Url-encoded (padding stripped) UTF-8 bytes of `"$hostId:$path"`.
/// This avoids filesystem-unsafe characters with no extra dependencies.
class OfflineBodyCache {
  OfflineBodyCache({Directory? baseDir}) : _baseDir = baseDir;

  /// Inject a temp directory in tests instead of hitting path_provider.
  final Directory? _baseDir;

  Future<Directory> _dir() async {
    final base = _baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline_cache');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  String _key(String hostId, String path) =>
  // ponytail: base64Url strips unsafe chars; padding removed for clean names.
  base64Url.encode(utf8.encode('$hostId:$path')).replaceAll('=', '');

  File _fileFor(Directory dir, String hostId, String path) =>
      File('${dir.path}/${_key(hostId, path)}');

  /// Sums the on-disk size of every cached file, across all hosts.
  Future<int> totalBytes() async {
    final dir = await _dir();
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } catch (_) {
        // Deleted mid-scan or otherwise unreadable — skip.
      }
    }
    return total;
  }

  Future<void> put(String hostId, String path, Uint8List bytes) async {
    final f = _fileFor(await _dir(), hostId, path);
    await f.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> get(String hostId, String path) async {
    final f = _fileFor(await _dir(), hostId, path);
    if (!f.existsSync()) return null;
    return f.readAsBytes();
  }

  Future<bool> has(String hostId, String path) async {
    final f = _fileFor(await _dir(), hostId, path);
    return f.existsSync();
  }

  Future<void> remove(String hostId, String path) async {
    final f = _fileFor(await _dir(), hostId, path);
    if (f.existsSync()) await f.delete();
  }

  /// Deletes all cached files belonging to [hostId] (call on host unpair).
  /// ponytail: linear scan over cache dir — cache is small in practice;
  ///           upgrade to a per-host subdirectory if evictions become slow.
  Future<void> evictHost(String hostId) async {
    final dir = await _dir();
    if (!dir.existsSync()) return;
    final prefix = '$hostId:';
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final filename = entity.uri.pathSegments.last;
      try {
        // Restore '=' padding so base64Url.decode is happy.
        final padded = filename.padRight((filename.length + 3) ~/ 4 * 4, '=');
        final decoded = utf8.decode(base64Url.decode(padded));
        if (decoded.startsWith(prefix)) await entity.delete();
      } catch (_) {
        // Not one of our files — skip.
      }
    }
  }
}
