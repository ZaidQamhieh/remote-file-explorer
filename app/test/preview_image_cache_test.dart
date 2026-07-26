import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/preview_image_cache.dart';

class _FakeClient extends AgentClient {
  _FakeClient(super.host, this.response);

  final Uint8List response;
  int calls = 0;

  @override
  Future<Uint8List> fetchBytes(
    String remotePath, {
    CancelToken? cancelToken,
    int maxBytes = maxInMemoryResponseBytes,
  }) async {
    calls++;
    return response;
  }
}

void main() {
  const firstHost = Host(id: 'first', label: 'First', address: 'first:8765');
  const secondHost = Host(
    id: 'second',
    label: 'Second',
    address: 'second:8765',
  );

  test('isolates identical remote paths across hosts', () async {
    final cache = PreviewImageCache();
    final first = _FakeClient(firstHost, Uint8List.fromList([1]));
    final second = _FakeClient(secondHost, Uint8List.fromList([2]));

    expect(await cache.fetch(first, '/photo.jpg'), [1]);
    expect(await cache.fetch(second, '/photo.jpg'), [2]);
    expect(first.calls, 1);
    expect(second.calls, 1);
  });

  test('invalidates a cached path when the remote version changes', () async {
    final cache = PreviewImageCache();
    final first = _FakeClient(firstHost, Uint8List.fromList([1]));
    final replacement = _FakeClient(firstHost, Uint8List.fromList([2]));
    final before = DateTime.utc(2026, 1, 1);
    final after = DateTime.utc(2026, 1, 2);

    expect(await cache.fetch(first, '/photo.jpg', modified: before, size: 1), [
      1,
    ]);
    expect(
      await cache.fetch(replacement, '/photo.jpg', modified: after, size: 1),
      [2],
    );
    expect(replacement.calls, 1);
  });

  test('does not retain an item larger than the byte budget', () async {
    final cache = PreviewImageCache(maxBytes: 2);
    final client = _FakeClient(firstHost, Uint8List.fromList([1, 2, 3]));

    await cache.fetch(client, '/large.jpg');
    await cache.fetch(client, '/large.jpg');

    expect(client.calls, 2);
  });
}
