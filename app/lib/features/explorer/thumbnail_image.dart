import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';

/// Process-wide in-memory cache of thumbnail bytes, keyed by host, remote file
/// version, and rendition size. Both entry count and bytes are bounded.
///
/// `null` values record "fetched, but the agent has no thumbnail for this
/// file" so we don't keep retrying every rebuild.
class _ThumbnailCache {
  _ThumbnailCache._();
  static final _ThumbnailCache instance = _ThumbnailCache._();

  static const int _maxEntries = 200;
  static const int _maxBytes = 32 * 1024 * 1024;

  final Map<_ThumbnailCacheKey, Uint8List?> _entries =
      <_ThumbnailCacheKey, Uint8List?>{};
  int _storedBytes = 0;

  bool contains(_ThumbnailCacheKey key) => _entries.containsKey(key);

  Uint8List? get(_ThumbnailCacheKey key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key);
    _entries[key] = value;
    return value;
  }

  void put(_ThumbnailCacheKey key, Uint8List? value) {
    final replaced = _entries.remove(key);
    if (replaced != null) _storedBytes -= replaced.lengthInBytes;

    if (value != null && value.lengthInBytes > _maxBytes) return;
    while (_entries.isNotEmpty &&
        (_entries.length >= _maxEntries ||
            _storedBytes + (value?.lengthInBytes ?? 0) > _maxBytes)) {
      final evicted = _entries.remove(_entries.keys.first);
      if (evicted != null) _storedBytes -= evicted.lengthInBytes;
    }
    _entries[key] = value;
    _storedBytes += value?.lengthInBytes ?? 0;
  }
}

typedef _ThumbnailCacheKey =
    ({
      String hostId,
      String path,
      int? modifiedMicros,
      int? sourceSize,
      int renditionSize,
    });

_ThumbnailCacheKey _cacheKeyFor(ThumbnailImage widget) => (
  hostId: widget.client.host.id,
  path: widget.entry.path,
  modifiedMicros: widget.entry.modified?.microsecondsSinceEpoch,
  sourceSize: widget.entry.size,
  renditionSize: widget.size,
);

/// Displays a server-rendered thumbnail for image [entry]s, fetched through
/// [client] and cached in-memory for the lifetime of the app.
///
/// While loading, or when no thumbnail is available (non-image, unsupported
/// format, decode failure, etc.), [fallback] is shown instead — callers
/// should pass whatever the grid normally renders for that entry (e.g. the
/// generic file-type icon) so the UI degrades gracefully.
class ThumbnailImage extends StatefulWidget {
  const ThumbnailImage({
    super.key,
    required this.entry,
    required this.client,
    required this.fallback,
    this.size = 256,
  });

  final Entry entry;
  final AgentClient client;
  final Widget fallback;
  final int size;

  @override
  State<ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<ThumbnailImage> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  _ThumbnailCacheKey get _cacheKey => _cacheKeyFor(widget);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_cacheKeyFor(oldWidget) != _cacheKey) {
      _bytes = null;
      _failed = false;
      _loading = false;
      _load();
    }
  }

  void _load() {
    final mime = widget.entry.mimeType ?? '';
    if (!mime.startsWith('image/')) {
      return; // not an image — keep showing the fallback.
    }

    final cache = _ThumbnailCache.instance;
    final key = _cacheKey;
    if (cache.contains(key)) {
      final cached = cache.get(key);
      _bytes = cached;
      _failed = cached == null;
      return;
    }

    _loading = true;
    final client = widget.client;
    final path = widget.entry.path;
    final size = widget.size;
    client
        .thumbnail(path, size: size)
        .then((data) {
          cache.put(key, data);
          if (!mounted || key != _cacheKey) return;
          setState(() {
            _bytes = data;
            _failed = data == null;
            _loading = false;
          });
        })
        .catchError((Object _) {
          cache.put(key, null);
          if (!mounted || key != _cacheKey) return;
          setState(() {
            _failed = true;
            _loading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: Radii.chipR,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => widget.fallback,
        ),
      );
    }

    if (_failed || !(widget.entry.mimeType ?? '').startsWith('image/')) {
      return widget.fallback;
    }

    if (_loading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      );
    }

    return widget.fallback;
  }
}
