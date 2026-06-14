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
  final Map<String, Future<Uint8List>> _inflight = <String, Future<Uint8List>>{};

  Uint8List? peek(String path) => _bytes[path];

  /// Fetches [path]'s bytes through [client], coalescing concurrent calls for
  /// the same path and caching the result. Used both by the viewer (to display)
  /// and the pager (to warm neighbours).
  Future<Uint8List> fetch(AgentClient client, String path) {
    final cached = _bytes[path];
    if (cached != null) return Future.value(cached);
    final pending = _inflight[path];
    if (pending != null) return pending;

    final future = client.fetchBytes(path).then((data) {
      _put(path, data);
      _inflight.remove(path);
      return data;
    }).catchError((Object e) {
      _inflight.remove(path);
      throw e;
    });
    _inflight[path] = future;
    return future;
  }

  /// Kicks off [fetch] for [path] without awaiting it, swallowing errors —
  /// used to warm neighbours where a failure should be silent (the user just
  /// won't get the instant-swap benefit; the viewer will surface its own error
  /// when actually navigated to).
  void preload(AgentClient client, String path) {
    if (_bytes.containsKey(path) || _inflight.containsKey(path)) return;
    // ignore: unawaited_futures
    fetch(client, path).catchError((_) => Uint8List(0));
  }

  void _put(String path, Uint8List data) {
    if (_bytes.containsKey(path)) {
      _bytes.remove(path);
    } else if (_bytes.length >= _maxEntries) {
      _bytes.remove(_bytes.keys.first);
    }
    _bytes[path] = data;
  }
}
