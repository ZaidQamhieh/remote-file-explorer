import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/entry.dart';

/// A cached directory listing plus the time it was fetched.
class CachedListing {
  CachedListing({required this.entries, required this.fetchedAt});
  final List<Entry> entries;
  final DateTime fetchedAt;
}

/// Persists recent directory listings per host so navigation is instant and the
/// explorer stays browsable (read-only) while the host is unreachable.
///
/// Storage: one JSON file per host under the app documents dir, mapping
/// `path -> { fetchedAt, entries }`. Capped at [maxEntries] directories per
/// host (oldest `fetchedAt` evicted first).
class ListingCache {
  ListingCache({this.baseDir, this.maxEntries = 200});

  /// Override for tests; defaults to the app documents dir.
  final Directory? baseDir;
  final int maxEntries;

  /// Keys of the form `"$hostId:$path"` that the eviction pass must skip.
  /// In-memory only; [syncPinned] re-hydrates it from `PinStore` on every
  /// build of `ExplorerNotifier` so it's correct again after a restart.
  final Set<String> _pinnedKeys = {};

  /// Per-host write chain (PR-49): [put] does a read-modify-write of the
  /// whole per-host file, so two concurrent `put()` calls for the same host
  /// (rapid navigation, background refresh) can both read the same stale
  /// data and the second write silently clobbers the first's entry. Chaining
  /// through this per-host future serializes them without blocking other
  /// hosts.
  final Map<String, Future<void>> _writeChains = {};

  /// Mark or unmark a cached listing as pinned so the eviction pass skips it.
  /// [key] must be in the form `"$hostId:$path"` — same format used by
  /// [ExplorerNotifier.setPinnedListing].
  void setPinned(String key, bool pinned) {
    if (pinned) {
      _pinnedKeys.add(key);
    } else {
      _pinnedKeys.remove(key);
    }
  }

  /// Replaces the pinned-path set for [hostId] with [paths] (bare remote
  /// paths, not `"$hostId:$path"` keys) — used to hydrate pin state from
  /// `PinStore` on notifier build, since [_pinnedKeys] is otherwise lost on
  /// every restart.
  void syncPinned(String hostId, Iterable<String> paths) {
    _pinnedKeys.removeWhere((k) => k.startsWith('$hostId:'));
    _pinnedKeys.addAll(paths.map((p) => '$hostId:$p'));
  }

  Future<Directory> _dir() async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/listing_cache');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _fileFor(String hostId) async {
    final safe = hostId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${(await _dir()).path}/$safe.json');
  }

  Future<Map<String, dynamic>> _read(String hostId) async {
    final f = await _fileFor(hostId);
    if (!await f.exists()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String hostId, Map<String, dynamic> data) async {
    final f = await _fileFor(hostId);
    await f.writeAsString(jsonEncode(data));
  }

  Future<void> put(String hostId, String path, List<Entry> entries) {
    final prior = _writeChains[hostId] ?? Future.value();
    final next = prior.then((_) => _putLocked(hostId, path, entries));
    _writeChains[hostId] = next.catchError((_) {});
    return next;
  }

  Future<void> _putLocked(
    String hostId,
    String path,
    List<Entry> entries,
  ) async {
    final data = await _read(hostId);
    data[path] = {
      'fetchedAt': DateTime.now().toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };

    // Evict oldest beyond capacity.
    if (data.length > maxEntries) {
      final keys =
          data.keys.toList()..sort((a, b) {
            final fa =
                DateTime.tryParse(
                  (data[a] as Map)['fetchedAt'] as String? ?? '',
                ) ??
                DateTime(0);
            final fb =
                DateTime.tryParse(
                  (data[b] as Map)['fetchedAt'] as String? ?? '',
                ) ??
                DateTime(0);
            return fa.compareTo(fb);
          });
      // Evict oldest non-pinned entries until we're back at capacity.
      var toEvict = data.length - maxEntries;
      for (final k in keys) {
        if (toEvict <= 0) break;
        if (_pinnedKeys.contains('$hostId:$k')) {
          continue; // ponytail: skip pinned
        }
        data.remove(k);
        toEvict--;
      }
    }
    await _write(hostId, data);
  }

  /// Deletes [hostId]'s entire cached-listing file — call on host unpair so a
  /// forgotten host's directory listings don't keep reappearing.
  Future<void> evictHost(String hostId) async {
    final f = await _fileFor(hostId);
    if (await f.exists()) await f.delete();
    _pinnedKeys.removeWhere((k) => k.startsWith('$hostId:'));
  }

  Future<CachedListing?> get(String hostId, String path) async {
    final data = await _read(hostId);
    final raw = data[path];
    if (raw is! Map) return null;
    final fetchedAt =
        DateTime.tryParse(raw['fetchedAt'] as String? ?? '') ?? DateTime(0);
    final entries =
        ((raw['entries'] as List?) ?? const [])
            .map((e) => Entry.fromJson(e as Map<String, dynamic>))
            .toList();
    return CachedListing(entries: entries, fetchedAt: fetchedAt);
  }
}
