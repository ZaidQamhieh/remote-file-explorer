import 'dart:async';
import 'dart:convert';

/// A single parsed SSE event from the agent's `/events` stream.
class SseEvent {
  const SseEvent({
    required this.type,
    required this.path,
    required this.action,
  });

  final String type;
  final String path;
  final String action;

  factory SseEvent.fromJson(Map<String, dynamic> json) => SseEvent(
    type: json['type'] as String? ?? '',
    path: json['path'] as String? ?? '',
    action: json['action'] as String? ?? '',
  );
}

/// Factory that opens a new SSE stream (each call returns a fresh connection).
typedef SseStreamFactory = Stream<String> Function();

/// Listens to the agent's SSE event stream, parses events, and exposes them
/// as a broadcast [Stream<SseEvent>]. Reconnects with exponential backoff on
/// error/disconnect.
class SseListener {
  SseListener(this._streamFactory);

  final SseStreamFactory _streamFactory;
  final _controller = StreamController<SseEvent>.broadcast();
  bool _disposed = false;
  bool _listening = false;
  int _backoff = 1;

  Stream<SseEvent> get events => _controller.stream;
  bool get connected => _listening;

  void start() {
    _listen();
  }

  /// Consumes the SSE stream using `await for`, which properly handles errors
  /// from async* generators without leaking them into the parent zone.
  Future<void> _listen() async {
    if (_disposed) return;
    _listening = true;
    try {
      await for (final line in _streamFactory()) {
        if (_disposed) break;
        _backoff = 1;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          _controller.add(SseEvent.fromJson(json));
        } catch (_) {
          // Malformed JSON — skip silently.
        }
      }
      // Stream ended normally.
      _listening = false;
      _reconnect();
    } catch (_) {
      _listening = false;
      _reconnect();
    }
  }

  void _reconnect() {
    if (_disposed) return;
    final delay = Duration(seconds: _backoff);
    _backoff = (_backoff * 2).clamp(1, 30);
    Future.delayed(delay, _listen);
  }

  void dispose() {
    _disposed = true;
    _listening = false;
    _controller.close();
  }
}
