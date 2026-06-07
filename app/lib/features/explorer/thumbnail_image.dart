import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
import '../../core/theme/tokens.dart';

/// Process-wide in-memory cache of decoded thumbnail bytes, keyed by the
/// entry's remote path. Capped at [_maxEntries] so re-scrolling the grid
/// doesn't refetch thumbnails, without growing unbounded for huge trees.
///
/// `null` values record "fetched, but the agent has no thumbnail for this
/// file" so we don't keep retrying every rebuild.
class _ThumbnailCache {
  _ThumbnailCache._();
  static final _ThumbnailCache instance = _ThumbnailCache._();

  static const int _maxEntries = 200;

  final Map<String, Uint8List?> _entries = <String, Uint8List?>{};

  bool contains(String key) => _entries.containsKey(key);

  Uint8List? get(String key) => _entries[key];

  void put(String key, Uint8List? value) {
    if (_entries.containsKey(key)) {
      _entries.remove(key); // re-insert to bump recency
    } else if (_entries.length >= _maxEntries) {
      _entries.remove(_entries.keys.first); // evict oldest
    }
    _entries[key] = value;
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

  String get _cacheKey => '${widget.entry.path}@${widget.size}';

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

    _loading = true;
    widget.client.thumbnail(widget.entry.path, size: widget.size).then((data) {
      cache.put(_cacheKey, data);
      if (!mounted) return;
      setState(() {
        _bytes = data;
        _failed = data == null;
        _loading = false;
      });
    }).catchError((Object _) {
      cache.put(_cacheKey, null);
      if (!mounted) return;
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
