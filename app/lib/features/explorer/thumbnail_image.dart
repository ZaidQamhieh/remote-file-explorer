import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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

/// Deduplicates thumbnail requests by cache key and limits process-wide HTTP
/// fetch concurrency. A subscription can leave the queue before dispatch or
/// cancel an active request once its last widget has detached.
class _ThumbnailFetchQueue {
  _ThumbnailFetchQueue._();
  static final _ThumbnailFetchQueue instance = _ThumbnailFetchQueue._();

  static const int _maxConcurrent = 4;

  final Map<String, _ThumbnailFetch> _inFlight = <String, _ThumbnailFetch>{};
  final List<_ThumbnailFetch> _pending = <_ThumbnailFetch>[];
  int _active = 0;

  _ThumbnailRequest request(
    String key,
    Future<Uint8List?> Function(CancelToken token) load,
  ) {
    final job = _inFlight.putIfAbsent(key, () {
      final created = _ThumbnailFetch(key, load);
      _pending.add(created);
      return created;
    });
    final subscription = _ThumbnailSubscription(job);
    job.subscriptions.add(subscription);
    _pump();
    return _ThumbnailRequest(this, subscription);
  }

  void cancel(_ThumbnailSubscription subscription) {
    if (subscription.completed) return;
    final job = subscription.job;
    subscription.complete(null);
    if (job.subscriptions.isNotEmpty) return;

    job.abandoned = true;
    if (identical(_inFlight[job.key], job)) _inFlight.remove(job.key);
    if (job.started) {
      job.cancelToken.cancel('No thumbnail widgets are waiting');
    } else {
      _pending.remove(job);
    }
    _pump();
  }

  void _pump() {
    while (_active < _maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      if (job.abandoned || job.subscriptions.isEmpty) continue;
      job.started = true;
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_ThumbnailFetch job) async {
    try {
      final data = await job.load(job.cancelToken);
      if (!job.abandoned) {
        _ThumbnailCache.instance.put(job.key, data);
        for (final subscription in job.subscriptions.toList()) {
          subscription.complete(data);
        }
      }
    } catch (error, stackTrace) {
      if (!job.abandoned) {
        for (final subscription in job.subscriptions.toList()) {
          subscription.completeError(error, stackTrace);
        }
      }
    } finally {
      if (identical(_inFlight[job.key], job)) _inFlight.remove(job.key);
      _active--;
      _pump();
    }
  }
}

class _ThumbnailFetch {
  _ThumbnailFetch(this.key, this.load);

  final String key;
  final Future<Uint8List?> Function(CancelToken token) load;
  final CancelToken cancelToken = CancelToken();
  final Set<_ThumbnailSubscription> subscriptions = <_ThumbnailSubscription>{};
  bool started = false;
  bool abandoned = false;
}

class _ThumbnailSubscription {
  _ThumbnailSubscription(this.job);

  final _ThumbnailFetch job;
  final Completer<Uint8List?> _completer = Completer<Uint8List?>();
  bool completed = false;

  Future<Uint8List?> get future => _completer.future;

  void complete(Uint8List? data) {
    if (completed) return;
    completed = true;
    job.subscriptions.remove(this);
    _completer.complete(data);
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (completed) return;
    completed = true;
    job.subscriptions.remove(this);
    _completer.completeError(error, stackTrace);
  }
}

class _ThumbnailRequest {
  _ThumbnailRequest(this._queue, this._subscription);

  final _ThumbnailFetchQueue _queue;
  final _ThumbnailSubscription _subscription;

  Future<Uint8List?> get future => _subscription.future;

  void cancel() => _queue.cancel(_subscription);
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
  _ThumbnailRequest? _request;

  String get _cacheKey => _cacheKeyFor(widget);

  static String _cacheKeyFor(ThumbnailImage widget) => thumbnailCacheKey(
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
    if (_cacheKeyFor(oldWidget) != _cacheKey ||
        (oldWidget.entry.mimeType ?? '') != (widget.entry.mimeType ?? '')) {
      _request?.cancel();
      _request = null;
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
    if (cache.contains(_cacheKey)) {
      _request?.cancel();
      _request = null;
      final cached = cache.get(_cacheKey);
      _bytes = cached;
      _failed = cached == null;
      _loading = false;
      return;
    }

    // Captured now so a completion that lands after `didUpdateWidget` moved
    // this state on to a different entry/size can recognize itself as stale
    // and skip applying its (now-wrong) result (PR-16).
    final requestKey = _cacheKey;
    final requestClient = widget.client;
    final requestPath = widget.entry.path;
    final requestSize = widget.size;
    _loading = true;
    final request = _ThumbnailFetchQueue.instance.request(
      requestKey,
      (token) => requestClient.thumbnail(
        requestPath,
        size: requestSize,
        cancelToken: token,
      ),
    );
    _request = request;
    unawaited(
      request.future.then<void>(
        (data) {
          if (!mounted ||
              !identical(request, _request) ||
              requestKey != _cacheKey) {
            return;
          }
          _request = null;
          setState(() {
            _bytes = data;
            _failed = data == null;
            _loading = false;
          });
        },
        onError: (Object _, StackTrace __) {
          if (!mounted ||
              !identical(request, _request) ||
              requestKey != _cacheKey) {
            return;
          }
          _request = null;
          setState(() {
            _failed = true;
            _loading = false;
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
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
