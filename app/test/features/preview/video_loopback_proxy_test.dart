// Tests for VideoLoopbackProxy's request gating (PR-27): only GET/HEAD at
// the instance's own random one-use path may reach the agent forward —
// anything else (wrong method, wrong/guessed path) must be rejected before
// ever touching AgentClient, so another local process scanning the
// ephemeral port can't read the file through it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/video_loopback_proxy.dart';

void main() {
  late AgentClient client;
  late VideoLoopbackProxy proxy;

  setUp(() async {
    client = AgentClient(
      const Host(id: 'h1', label: 'h1', address: '127.0.0.1:1'),
    );
    proxy = await VideoLoopbackProxy.start(client, '/some/file.mp4');
  });

  tearDown(() async {
    await proxy.close();
    client.close();
  });

  Future<int> statusFor(String method, String path) async {
    final httpClient = HttpClient();
    try {
      final req = await httpClient.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${proxy.port}$path'),
      );
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      httpClient.close(force: true);
    }
  }

  test('path is random and not a guessable constant', () {
    expect(proxy.path, startsWith('/'));
    expect(proxy.path.length, greaterThan(16));
    expect(proxy.path, isNot('/video'));
  });

  test(
    'wrong path is rejected with 404, never reaching the agent forward',
    () async {
      expect(await statusFor('GET', '/video'), HttpStatus.notFound);
      expect(await statusFor('GET', '/'), HttpStatus.notFound);
      expect(await statusFor('GET', '/wrong-token'), HttpStatus.notFound);
    },
  );

  test(
    'a non-GET/HEAD method at the correct path is rejected with 404',
    () async {
      expect(await statusFor('POST', proxy.path), HttpStatus.notFound);
      expect(await statusFor('DELETE', proxy.path), HttpStatus.notFound);
    },
  );

  test('GET at the correct path passes the guard (fails later trying to reach '
      'the fake agent, but not with a guard 404)', () async {
    expect(await statusFor('GET', proxy.path), isNot(HttpStatus.notFound));
  });
}
