import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/host.dart';

// PR-82: real HTTP/TLS round-trip coverage for AgentClient, which previously
// had only pure-function unit tests (agent_client_gzip_test.dart). This spins
// up a real self-signed HTTPS server (openssl, no new pub dependency) and
// drives a real AgentClient against it over an actual loopback socket, so TLS
// pinning, header attachment, error-code mapping, chunked upload, resumed
// download, and the dual-address fallback interceptor are exercised for
// real instead of asserted only in isolated pure-function form.

Future<void> _writeJson(
  HttpRequest req,
  int status,
  Map<String, dynamic> body,
) async {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  await req.response.close();
}

/// A real HTTPS server backed by a freshly generated self-signed cert. Each
/// test sets [handler] to script the response(s) it needs, then closes the
/// server isn't required per-test — [close] runs once in tearDownAll.
class _FakeAgentServer {
  _FakeAgentServer._(this._server, this.port, this.certSha256Hex);

  final HttpServer _server;
  final int port;

  /// SHA-256 of the leaf cert's DER bytes, computed the same way
  /// AgentClient's badCertificateCallback computes it -- the ground truth
  /// for pin-match / pin-mismatch tests.
  final String certSha256Hex;

  Future<void> Function(HttpRequest req)? handler;

  static Future<_FakeAgentServer> start(Directory certDir) async {
    final keyPath = '${certDir.path}/key.pem';
    final certPath = '${certDir.path}/cert.pem';
    final gen = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '1',
      '-nodes',
      '-subj',
      '/CN=localhost',
    ]);
    if (gen.exitCode != 0) {
      throw StateError('openssl cert generation failed: ${gen.stderr}');
    }

    final pem = await File(certPath).readAsString();
    final b64 =
        pem
            .replaceAll('-----BEGIN CERTIFICATE-----', '')
            .replaceAll('-----END CERTIFICATE-----', '')
            .replaceAll('\n', '')
            .trim();
    final fingerprint = sha256.convert(base64.decode(b64)).toString();

    final ctx =
        SecurityContext()
          ..useCertificateChain(certPath)
          ..usePrivateKey(keyPath);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      ctx,
    );
    final fake = _FakeAgentServer._(server, server.port, fingerprint);
    server.listen((req) async {
      final h = fake.handler;
      if (h == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      await h(req);
    });
    return fake;
  }

  Future<void> close() => _server.close(force: true);
}

/// Grabs an ephemeral loopback port and immediately releases it, so a
/// connection attempt to it fails fast with ECONNREFUSED -- used to simulate
/// an unreachable primary address for the fallback tests.
Future<int> _unusedPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // TestWidgetsFlutterBinding installs an HttpOverrides that fakes every
  // HttpClient to return 400 with no real network call -- a safety net for
  // widget tests that accidentally hit the network. This suite deliberately
  // does real HTTP/TLS against a local loopback server, so undo it.
  HttpOverrides.global = null;

  // AgentClient._wantsGzip() calls Connectivity().checkConnectivity(), which
  // goes over a platform method channel with no real platform in a `flutter
  // test` VM -- stub it to report wifi (matching the gzip pure-function
  // tests' "no gzip on wifi" case) so requests that reach that code path
  // don't throw MissingPluginException.
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(connectivityChannel, (call) async {
        if (call.method == 'check') return <String>['wifi'];
        return null;
      });

  late Directory certDir;
  late _FakeAgentServer server;

  setUpAll(() async {
    certDir = Directory.systemTemp.createTempSync('agent_client_it_');
    server = await _FakeAgentServer.start(certDir);
  });

  tearDownAll(() async {
    await server.close();
    certDir.deleteSync(recursive: true);
  });

  setUp(() {
    server.handler = null;
  });

  Host hostFor(_FakeAgentServer s, {String? pin, String? deviceToken}) => Host(
    id: 'test-host',
    label: 'Test',
    address: '127.0.0.1:${s.port}',
    certFingerprint: pin,
  );

  group('TLS pinning (TOFU)', () {
    test(
      'unpinned host accepts the self-signed cert and captures the fingerprint',
      () async {
        server.handler = (req) => _writeJson(req, 200, {'status': 'ok'});
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        final health = await client.health();

        expect(health.status, 'ok');
        expect(client.lastSeenFingerprint, server.certSha256Hex);
      },
    );

    test('pinned host with a matching fingerprint connects normally', () async {
      server.handler = (req) => _writeJson(req, 200, {'status': 'ok'});
      final client = AgentClient(hostFor(server, pin: server.certSha256Hex));
      addTearDown(client.close);

      final health = await client.health();
      expect(health.status, 'ok');
    });

    test(
      'pinned host with a mismatched fingerprint fails the request instead of silently connecting',
      () async {
        server.handler = (req) => _writeJson(req, 200, {'status': 'ok'});
        final client = AgentClient(
          hostFor(
            server,
            pin:
                '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
        addTearDown(client.close);

        await expectLater(client.health(), throwsA(anything));
      },
    );
  });

  group('auth header attachment', () {
    test('no deviceToken -> no Authorization header sent', () async {
      String? seen = 'unset';
      server.handler = (req) async {
        seen = req.headers.value('authorization');
        await _writeJson(req, 200, {'status': 'ok'});
      };
      final client = AgentClient(hostFor(server));
      addTearDown(client.close);

      await client.health();
      expect(seen, isNull);
    });

    test(
      'deviceToken set -> every request carries Authorization: Bearer <token>',
      () async {
        String? seen;
        server.handler = (req) async {
          seen = req.headers.value('authorization');
          await _writeJson(req, 200, {'status': 'ok'});
        };
        final client = AgentClient(
          hostFor(server),
          deviceToken: 'secret-token-123',
        );
        addTearDown(client.close);

        await client.health();
        expect(seen, 'Bearer secret-token-123');
      },
    );

    test(
      'X-RFE-Client-Version header is always present (even if empty)',
      () async {
        String? seen = 'unset';
        server.handler = (req) async {
          seen = req.headers.value('x-rfe-client-version');
          await _writeJson(req, 200, {'status': 'ok'});
        };
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        await client.health();
        expect(seen, isNotNull);
      },
    );
  });

  group('directory listing round-trip', () {
    test(
      'list() sends path/cursor/limit query params and parses entries + nextCursor',
      () async {
        Uri? seenUri;
        server.handler = (req) async {
          seenUri = req.uri;
          await _writeJson(req, 200, {
            'path': '/docs',
            'entries': [
              {
                'name': 'a.txt',
                'path': '/docs/a.txt',
                'isDir': false,
                'size': 42,
              },
              {'name': 'sub', 'path': '/docs/sub', 'isDir': true},
            ],
            'nextCursor': 'page2',
          });
        };
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        final listing = await client.list('/docs', cursor: 'page1', limit: 50);

        expect(seenUri!.queryParameters['path'], '/docs');
        expect(seenUri!.queryParameters['cursor'], 'page1');
        expect(seenUri!.queryParameters['limit'], '50');
        expect(listing.entries, hasLength(2));
        expect(listing.entries[0].name, 'a.txt');
        expect(listing.entries[0].size, 42);
        expect(listing.entries[1].isDir, isTrue);
        expect(listing.nextCursor, 'page2');
      },
    );
  });

  group('error-code mapping over a real response', () {
    test('403 READ_ONLY on putContent throws ReadOnlyException', () async {
      server.handler =
          (req) => _writeJson(req, 403, {
            'code': 'READ_ONLY',
            'message': 'agent is read-only',
          });
      final client = AgentClient(hostFor(server));
      addTearDown(client.close);

      await expectLater(
        client.putContent('/f.txt', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ReadOnlyException>()),
      );
    });

    test('409 STALE_WRITE on putContent throws StaleWriteException', () async {
      server.handler =
          (req) => _writeJson(req, 409, {
            'code': 'STALE_WRITE',
            'message': 'file changed on disk',
          });
      final client = AgentClient(hostFor(server));
      addTearDown(client.close);

      await expectLater(
        client.putContent('/f.txt', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StaleWriteException>()),
      );
    });

    test(
      '413 PAYLOAD_TOO_LARGE on putContent throws PayloadTooLargeException',
      () async {
        server.handler =
            (req) => _writeJson(req, 413, {
              'code': 'PAYLOAD_TOO_LARGE',
              'message': 'too big',
            });
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        await expectLater(
          client.putContent('/f.txt', Uint8List.fromList([1, 2, 3])),
          throwsA(isA<PayloadTooLargeException>()),
        );
      },
    );

    test(
      'an unmapped error code surfaces as AgentApiException with the real status/code/message',
      () async {
        server.handler =
            (req) => _writeJson(req, 404, {
              'code': 'NOT_FOUND',
              'message': 'no such file',
            });
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        try {
          await client.meta('/missing.txt');
          fail('expected AgentApiException');
        } on AgentApiException catch (e) {
          expect(e.statusCode, 404);
          expect(e.code, 'NOT_FOUND');
          expect(e.message, 'no such file');
        }
      },
    );
  });

  group('putContent round-trip', () {
    test(
      'sends the exact bytes with Content-Type/Content-Length and returns the parsed Entry',
      () async {
        final sent = <int>[];
        Map<String, String>? seenHeaders;
        server.handler = (req) async {
          seenHeaders = {
            'content-type': req.headers.contentType?.mimeType ?? '',
            'content-length': req.headers.value('content-length') ?? '',
          };
          await for (final chunk in req) {
            sent.addAll(chunk);
          }
          await _writeJson(req, 200, {
            'name': 'f.txt',
            'path': '/f.txt',
            'isDir': false,
            'size': sent.length,
          });
        };
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        final bytes = Uint8List.fromList(utf8.encode('hello agent'));
        final entry = await client.putContent('/f.txt', bytes);

        expect(sent, bytes);
        expect(seenHeaders!['content-type'], 'application/octet-stream');
        expect(seenHeaders!['content-length'], '${bytes.length}');
        expect(entry.path, '/f.txt');
        expect(entry.size, bytes.length);
      },
    );
  });

  group('fetchBytes over a real streamed response', () {
    test('returns exactly the streamed bytes', () async {
      final payload = List<int>.generate(5000, (i) => i % 256);
      server.handler = (req) async {
        req.response.statusCode = 200;
        req.response.add(payload);
        await req.response.close();
      };
      final client = AgentClient(hostFor(server));
      addTearDown(client.close);

      final bytes = await client.fetchBytes('/big.bin');
      expect(bytes, payload);
    });

    test(
      'aborts with FetchTooLargeException once the real response exceeds maxBytes',
      () async {
        final payload = List<int>.filled(10000, 7);
        server.handler = (req) async {
          req.response.statusCode = 200;
          req.response.add(payload);
          await req.response.close();
        };
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        await expectLater(
          client.fetchBytes('/big.bin', maxBytes: 100),
          throwsA(isA<FetchTooLargeException>()),
        );
      },
    );
  });

  group('downloadFile over a real connection', () {
    test('writes the response body to the local file', () async {
      final payload = utf8.encode('downloaded content');
      server.handler = (req) async {
        req.response.statusCode = 200;
        req.response.add(payload);
        await req.response.close();
      };
      final client = AgentClient(hostFor(server));
      addTearDown(client.close);

      final dir = Directory.systemTemp.createTempSync('dl_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final local = File('${dir.path}/out.bin');

      await client.downloadFile(remotePath: '/f.bin', localFile: local);

      expect(local.readAsBytesSync(), payload);
    });

    test(
      'a resumed (Range) request answered with 200 instead of 206 throws '
      'RangeNotSatisfiedException and deletes the corrupted partial file',
      () async {
        server.handler = (req) async {
          // Server ignores the Range header and answers with a full 200 --
          // exactly the bug this exception exists to catch.
          req.response.statusCode = 200;
          req.response.add(utf8.encode('full file, not a range'));
          await req.response.close();
        };
        final client = AgentClient(hostFor(server));
        addTearDown(client.close);

        final dir = Directory.systemTemp.createTempSync('dl_resume_test_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final local = File('${dir.path}/partial.bin')
          ..writeAsStringSync('stale partial bytes');

        await expectLater(
          client.downloadFile(
            remotePath: '/f.bin',
            localFile: local,
            startByte: 20,
          ),
          throwsA(isA<RangeNotSatisfiedException>()),
        );
        expect(local.existsSync(), isFalse);
      },
    );
  });

  group('resumable upload session, real chunk + complete round-trip', () {
    test('open -> uploadChunk -> complete carries real bytes/headers through '
        'a live connection and parses the final verified result', () async {
      final chunkBytes = Uint8List.fromList(List.generate(64, (i) => i));
      String? seenSessionPath;
      List<int>? receivedChunk;
      String? contentRange;
      String? chunkSha;

      server.handler = (req) async {
        if (req.method == 'POST' && req.uri.path == '/v1/transfers') {
          await _writeJson(req, 200, {
            'id': 'sess-1',
            'path': '/big.bin',
            'size': chunkBytes.length,
            'chunkSize': chunkBytes.length,
            'totalChunks': 1,
            'receivedChunks': <int>[],
            'status': 'open',
          });
          return;
        }
        if (req.method == 'PUT' &&
            req.uri.path == '/v1/transfers/sess-1/chunks/0') {
          seenSessionPath = req.uri.path;
          contentRange = req.headers.value('content-range');
          chunkSha = req.headers.value('x-chunk-sha256');
          final buf = <int>[];
          await for (final c in req) {
            buf.addAll(c);
          }
          receivedChunk = buf;
          req.response.statusCode = 200;
          await req.response.close();
          return;
        }
        if (req.method == 'POST' &&
            req.uri.path == '/v1/transfers/sess-1/complete') {
          await _writeJson(req, 200, {
            'name': 'big.bin',
            'path': '/big.bin',
            'isDir': false,
            'size': chunkBytes.length,
            'verified': true,
            'sha256': 'deadbeef',
          });
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      };

      final client = AgentClient(hostFor(server));
      addTearDown(client.close);

      final session = await client.openUploadSession(
        path: '/big.bin',
        size: chunkBytes.length,
        sha256Hex: 'ignored-for-this-test',
        chunkSize: chunkBytes.length,
      );
      expect(session.id, 'sess-1');
      expect(session.totalChunks, 1);

      await client.uploadChunk(
        sessionId: session.id,
        chunkIndex: 0,
        data: chunkBytes,
        contentRange: 'bytes 0-${chunkBytes.length - 1}/${chunkBytes.length}',
        chunkSha256: 'chunk-hash-abc',
      );

      expect(seenSessionPath, '/v1/transfers/sess-1/chunks/0');
      expect(receivedChunk, chunkBytes);
      expect(
        contentRange,
        'bytes 0-${chunkBytes.length - 1}/${chunkBytes.length}',
      );
      expect(chunkSha, 'chunk-hash-abc');

      final result = await client.completeUpload(session.id);
      expect(result.verified, isTrue);
      expect(result.sha256, 'deadbeef');
      expect(result.entry.path, '/big.bin');
    });
  });

  group('unreachable agent', () {
    test(
      'a genuinely closed port surfaces AgentApiException(CONNECTION), matching isConnectivityFailure',
      () async {
        final closedPort = await _unusedPort();
        final host = Host(
          id: 'dead',
          label: 'Dead',
          address: '127.0.0.1:$closedPort',
        );
        final client = AgentClient(host);
        addTearDown(client.close);

        try {
          await client.health();
          fail('expected AgentApiException');
        } on AgentApiException catch (e) {
          expect(e.code, 'CONNECTION');
          expect(e.statusCode, 0);
        }
      },
    );
  });

  group('dual-address fallback (previously untested end to end)', () {
    test('a GET transparently retries against the second address when the '
        'first is unreachable, and succeeds', () async {
      server.handler = (req) => _writeJson(req, 200, {'status': 'ok'});
      final closedPort = await _unusedPort();
      final host = Host(
        id: 'fallback-host',
        label: 'Fallback',
        address: '127.0.0.1:$closedPort', // unreachable primary
        tailscaleAddress: '127.0.0.1:${server.port}', // reachable secondary
      );
      final client = AgentClient(host);
      addTearDown(client.close);

      final health = await client.health();

      expect(health.status, 'ok');
      expect(client.activeAddress, '127.0.0.1:${server.port}');
      expect(client.isActiveAddressTailscale, isTrue);
    });

    test('a write (PUT) is NOT auto-retried against the fallback address -- '
        'only GET/HEAD are safe to silently replay', () async {
      var putHandlerCalls = 0;
      server.handler = (req) async {
        if (req.method == 'PUT') putHandlerCalls++;
        await _writeJson(req, 200, {
          'name': 'f.txt',
          'path': '/f.txt',
          'isDir': false,
        });
      };
      final closedPort = await _unusedPort();
      final host = Host(
        id: 'fallback-host-2',
        label: 'Fallback2',
        address: '127.0.0.1:$closedPort', // unreachable primary
        tailscaleAddress: '127.0.0.1:${server.port}',
      );
      final client = AgentClient(host);
      addTearDown(client.close);

      await expectLater(
        client.putContent('/f.txt', Uint8List.fromList([1])),
        throwsA(isA<AgentApiException>()),
      );
      expect(putHandlerCalls, 0);
    });
  });
}
