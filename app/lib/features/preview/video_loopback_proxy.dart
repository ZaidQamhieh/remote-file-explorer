import 'dart:async';
import 'dart:io';

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
  VideoLoopbackProxy._(this._server, this._client, this._remotePath) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final AgentClient _client;
  final String _remotePath;

  int get port => _server.port;

  static Future<VideoLoopbackProxy> start(
    AgentClient client,
    String remotePath,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return VideoLoopbackProxy._(server, client, remotePath);
  }

  Future<void> _handle(HttpRequest request) async {
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
