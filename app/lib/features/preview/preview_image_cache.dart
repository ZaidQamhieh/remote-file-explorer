import 'dart:typed_data';

import '../../core/api/agent_client.dart';

/// Process-wide cache + in-flight de-duplication for full-resolution preview
/// image bytes, keyed by remote path.
///
/// Separate from the grid's *thumbnail* cache (`thumbnail_image.dart`): this
/// holds the full image bytes the [ImagePreviewScreen] decodes. It exists so
/// the [PreviewPager] can **preload neighbouring images** (±1) when a page
/// settles — the swipe then shows the next image instantly because its bytes
/// are already fetched (or in flight). Bounded so paging through a large
/// folder doesn't grow memory without limit.
class PreviewImageCache {
  PreviewImageCache._();
  static final PreviewImageCache instance = PreviewImageCache._();

  static const int _maxEntries = 8;

  final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _inflight =
      <String, Future<Uint8List>>{};

  /// Two hosts can legitimately share a remote path (e.g. `/home/x/y.jpg` on
  /// each), so the cache/in-flight key must include host identity — a
  /// path-only key let a stale image from a *different* host's file show up
  /// while previewing this one (PR-16).
  String _key(AgentClient client, String path) => '${client.host.id}@$path';

  Uint8List? peek(AgentClient client, String path) =>
      _bytes[_key(client, path)];

  /// Fetches [path]'s bytes through [client], coalescing concurrent calls for
  /// the same path and caching the result. Used both by the viewer (to display)
  /// and the pager (to warm neighbours).
  Future<Uint8List> fetch(AgentClient client, String path) {
    final key = _key(client, path);
    final cached = _bytes[key];
    if (cached != null) return Future.value(cached);
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = client
        .fetchBytes(path)
        .then((data) {
          _put(key, data);
          _inflight.remove(key);
          return data;
        })
        .catchError((Object e) {
          _inflight.remove(key);
          throw e;
        });
    _inflight[key] = future;
    return future;
  }

  /// Kicks off [fetch] for [path] without awaiting it, swallowing errors —
  /// used to warm neighbours where a failure should be silent (the user just
  /// won't get the instant-swap benefit; the viewer will surface its own error
  /// when actually navigated to).
  void preload(AgentClient client, String path) {
    final key = _key(client, path);
    if (_bytes.containsKey(key) || _inflight.containsKey(key)) return;
    // ignore: unawaited_futures
    fetch(client, path).catchError((_) => Uint8List(0));
  }

  void _put(String key, Uint8List data) {
    if (_bytes.containsKey(key)) {
      _bytes.remove(key);
    } else if (_bytes.length >= _maxEntries) {
      _bytes.remove(_bytes.keys.first);
    }
    _bytes[key] = data;
  }
}
