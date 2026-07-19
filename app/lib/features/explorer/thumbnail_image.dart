import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';

/// Builds the thumbnail cache key: [hostId] keeps two agents with the same
/// remote path from sharing bytes, and [version] (mtime, falling back to
/// file size) keeps a replaced file from serving its predecessor's stale
/// thumbnail for the rest of the process lifetime (PR-16). Pure and
/// unit-testable on its own (see `test/features/explorer/`).
String thumbnailCacheKey({
  required String hostId,
  required String path,
  required int size,
  required int version,
}) => '$hostId@$path@$size@$version';

/// Process-wide in-memory cache of decoded thumbnail bytes, keyed by
/// `(hostId, path, size, version)` — see [ThumbnailImage._cacheKey] — and
/// capped by total decoded bytes rather than entry count, so a handful of
/// large renditions can't blow past the intended memory budget the way a
/// count-only cap would (PR-16).
///
/// `null` values record "fetched, but the agent has no thumbnail for this
/// file" so we don't keep retrying every rebuild.
class _ThumbnailCache {
  _ThumbnailCache._();
  static final _ThumbnailCache instance = _ThumbnailCache._();

  static const int _maxBytes = 32 * 1024 * 1024;

  final Map<String, Uint8List?> _entries = <String, Uint8List?>{};
  int _bytes = 0;

  bool contains(String key) => _entries.containsKey(key);

  Uint8List? get(String key) => _entries[key];

  void put(String key, Uint8List? value) {
    final existing = _entries.remove(key);
    if (existing != null) _bytes -= existing.length;
    _entries[key] = value; // (re-)insert at the end to bump recency
    if (value != null) _bytes += value.length;
    while (_bytes > _maxBytes && _entries.length > 1) {
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey);
      if (oldest != null) _bytes -= oldest.length;
    }
  }
}

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

  String get _cacheKey => thumbnailCacheKey(
    hostId: widget.client.host.id,
    path: widget.entry.path,
    size: widget.size,
    version:
        widget.entry.modified?.millisecondsSinceEpoch ?? widget.entry.size ?? 0,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.size != widget.size) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  void _load() {
    final mime = widget.entry.mimeType ?? '';
    if (!mime.startsWith('image/')) {
      return; // not an image — keep showing the fallback.
    }

    final cache = _ThumbnailCache.instance;
    if (cache.contains(_cacheKey)) {
      final cached = cache.get(_cacheKey);
      _bytes = cached;
      _failed = cached == null;
      return;
    }

    // Captured now so a completion that lands after `didUpdateWidget` moved
    // this state on to a different entry/size can recognize itself as stale
    // and skip applying its (now-wrong) result (PR-16).
    final requestKey = _cacheKey;
    _loading = true;
    widget.client
        .thumbnail(widget.entry.path, size: widget.size)
        .then((data) {
          cache.put(requestKey, data);
          if (!mounted || requestKey != _cacheKey) return;
          setState(() {
            _bytes = data;
            _failed = data == null;
            _loading = false;
          });
        })
        .catchError((Object _) {
          cache.put(requestKey, null);
          if (!mounted || requestKey != _cacheKey) return;
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
