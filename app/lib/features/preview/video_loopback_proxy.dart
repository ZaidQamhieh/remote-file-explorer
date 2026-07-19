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
    this.path,
  ) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final AgentClient _client;
  final String _remotePath;

  /// Random one-use URL path this instance serves at — any other localhost
  /// process that discovers the ephemeral port still can't request the
  /// file without also knowing this (PR-27).
  final String path;

  int get port => _server.port;

  static Future<VideoLoopbackProxy> start(
    AgentClient client,
    String remotePath,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = base64Url.encode(
      List<int>.generate(24, (_) => Random.secure().nextInt(256)),
    );
    return VideoLoopbackProxy._(server, client, remotePath, '/$token');
  }

  Future<void> _handle(HttpRequest request) async {
    if ((request.method != 'GET' && request.method != 'HEAD') ||
        request.uri.path != path) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final res = await _client.openContentStream(
        _remotePath,
        rangeHeader: request.headers.value(HttpHeaders.rangeHeader),
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
      await request.response.addStream(stream);
      await request.response.close();
    } catch (_) {
      // Best-effort proxy — video_player surfaces the broken connection as
      // its own playback error, which the preview screen already handles.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() => _server.close(force: true);
}
