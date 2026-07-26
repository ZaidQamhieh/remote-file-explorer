import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/api/agent_client.dart';

/// A loopback-only HTTP server that lets `video_player` stream a remote file
/// without knowing about the agent's TLS pinning or bearer auth.
///
/// `video_player` needs a local file or a plain `http(s)://` URL — it can't
/// be handed a [AgentClient]. This binds `127.0.0.1:<ephemeral port>`,
/// forwards each GET (including any `Range` header, so seeking works) to
/// [AgentClient.openContentStream], and relays the response straight through.
/// The agent connection does the pinning/auth; the player never sees it.
class VideoLoopbackProxy {
  VideoLoopbackProxy._(
    this._server,
    this._client,
    this._remotePath,
    this._capabilityPath,
  ) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final AgentClient _client;
  final String _remotePath;
  final String _capabilityPath;
  int _activeRequests = 0;

  static const int _maxConcurrentRequests = 4;

  int get port => _server.port;
  Uri get uri => Uri.parse('http://127.0.0.1:$port$_capabilityPath');

  static Future<VideoLoopbackProxy> start(
    AgentClient client,
    String remotePath,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return VideoLoopbackProxy._(server, client, remotePath, '/stream/$token');
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != _capabilityPath) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && !_validSingleRange(range)) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await request.response.close();
      return;
    }
    if (_activeRequests >= _maxConcurrentRequests) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    _activeRequests++;
    try {
      final res = await _client.openContentStream(
        _remotePath,
        rangeHeader: range,
      );
      final stream = res.data?.stream;
      if (stream == null) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
      request.response.statusCode = res.statusCode ?? HttpStatus.ok;
      for (final name in const [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
      ]) {
        final value = res.headers.value(name);
        if (value != null) request.response.headers.set(name, value);
      }
      if (request.method == 'GET') {
        await request.response.addStream(stream);
      } else {
        await stream.listen(null).cancel();
      }
      await request.response.close();
    } catch (_) {
      // Best-effort proxy — video_player surfaces the broken connection as
      // its own playback error, which the preview screen already handles.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    } finally {
      _activeRequests--;
    }
  }

  Future<void> close() => _server.close(force: true);
}

bool _validSingleRange(String value) {
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value);
  return match != null &&
      (match.group(1)!.isNotEmpty || match.group(2)!.isNotEmpty);
}
