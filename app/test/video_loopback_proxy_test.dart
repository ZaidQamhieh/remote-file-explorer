import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/video_loopback_proxy.dart';

class _FakeClient extends AgentClient {
  _FakeClient() : super(const Host(id: 'host', label: 'Host', address: 'x'));

  int calls = 0;

  @override
  Future<Response<ResponseBody>> openContentStream(
    String remotePath, {
    String? rangeHeader,
  }) async {
    calls++;
    final request = RequestOptions(path: '/content');
    return Response<ResponseBody>(
      requestOptions: request,
      statusCode: HttpStatus.ok,
      data: ResponseBody.fromBytes(
        utf8.encode('private video'),
        HttpStatus.ok,
        headers: {
          HttpHeaders.contentTypeHeader: ['video/mp4'],
        },
      ),
    );
  }
}

void main() {
  test('requires an unguessable capability path', () async {
    final client = _FakeClient();
    final proxy = await VideoLoopbackProxy.start(client, '/secret.mp4');
    final http = HttpClient();
    addTearDown(() async {
      http.close(force: true);
      await proxy.close();
      client.close();
    });

    final guessed =
        await (await http.getUrl(
          Uri.parse('http://127.0.0.1:${proxy.port}/video'),
        )).close();
    await guessed.drain<void>();
    expect(guessed.statusCode, HttpStatus.notFound);
    expect(client.calls, 0);

    final allowed = await (await http.getUrl(proxy.uri)).close();
    final body = await utf8.decoder.bind(allowed).join();
    expect(allowed.statusCode, HttpStatus.ok);
    expect(body, 'private video');
    expect(client.calls, 1);
  });
}
