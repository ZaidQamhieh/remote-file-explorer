import 'dart:typed_data';

import '../../core/api/agent_client.dart';

/// Process-wide cache + in-flight de-duplication for full-resolution preview
/// image bytes. Keys include the host and file version so bytes can never leak
/// across computers or survive a remote file replacement.
///
/// Separate from the grid's *thumbnail* cache (`thumbnail_image.dart`): this
/// holds the full image bytes the [ImagePreviewScreen] decodes. It exists so
/// the [PreviewPager] can **preload neighbouring images** (±1) when a page
/// settles — the swipe then shows the next image instantly because its bytes
/// are already fetched (or in flight). Bounded so paging through a large
/// folder doesn't grow memory without limit.
class PreviewImageCache {
  PreviewImageCache({int maxEntries = 8, int maxBytes = 96 * 1024 * 1024})
    : assert(maxEntries > 0),
      assert(maxBytes > 0),
      _maxEntries = maxEntries,
      _maxBytes = maxBytes;

  static final PreviewImageCache instance = PreviewImageCache();

  final int _maxEntries;
  final int _maxBytes;
  int _storedBytes = 0;

  final Map<_PreviewCacheKey, Uint8List> _bytes =
      <_PreviewCacheKey, Uint8List>{};
  final Map<_PreviewCacheKey, Future<Uint8List>> _inflight =
      <_PreviewCacheKey, Future<Uint8List>>{};

  _PreviewCacheKey _key(
    AgentClient client,
    String path, {
    DateTime? modified,
    int? size,
  }) => (
    hostId: client.host.id,
    path: path,
    modifiedMicros: modified?.microsecondsSinceEpoch,
    size: size,
  );

  Uint8List? _cached(_PreviewCacheKey key) {
    final data = _bytes.remove(key);
    if (data != null) _bytes[key] = data;
    return data;
  }

  /// Fetches [path]'s bytes through [client], coalescing concurrent calls for
  /// the same path and caching the result. Used both by the viewer (to display)
  /// and the pager (to warm neighbours).
  Future<Uint8List> fetch(
    AgentClient client,
    String path, {
    DateTime? modified,
    int? size,
  }) {
    final key = _key(client, path, modified: modified, size: size);
    final cached = _cached(key);
    if (cached != null) return Future.value(cached);
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future =
        (() async {
          try {
            final data = await client.fetchBytes(path);
            _put(key, data);
            return data;
          } finally {
            _inflight.remove(key);
          }
        })();
    _inflight[key] = future;
    return future;
  }

  /// Kicks off [fetch] for [path] without awaiting it, swallowing errors —
  /// used to warm neighbours where a failure should be silent (the user just
  /// won't get the instant-swap benefit; the viewer will surface its own error
  /// when actually navigated to).
  void preload(
    AgentClient client,
    String path, {
    DateTime? modified,
    int? size,
  }) {
    final key = _key(client, path, modified: modified, size: size);
    if (_bytes.containsKey(key) || _inflight.containsKey(key)) return;
    // ignore: unawaited_futures
    fetch(
      client,
      path,
      modified: modified,
      size: size,
    ).catchError((_) => Uint8List(0));
  }

  void _put(_PreviewCacheKey key, Uint8List data) {
    final replaced = _bytes.remove(key);
    if (replaced != null) _storedBytes -= replaced.lengthInBytes;

    if (data.lengthInBytes > _maxBytes) return;
    while (_bytes.isNotEmpty &&
        (_bytes.length >= _maxEntries ||
            _storedBytes + data.lengthInBytes > _maxBytes)) {
      final evicted = _bytes.remove(_bytes.keys.first)!;
      _storedBytes -= evicted.lengthInBytes;
    }
    _bytes[key] = data;
    _storedBytes += data.lengthInBytes;
  }
}

typedef _PreviewCacheKey =
    ({String hostId, String path, int? modifiedMicros, int? size});
