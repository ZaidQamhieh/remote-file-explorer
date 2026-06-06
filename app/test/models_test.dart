import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/drive.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/health.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/core/models/pair_response.dart';
import 'package:remote_file_explorer/core/models/upload_session.dart';

void main() {
  group('Entry.fromJson', () {
    test('parses full object', () {
      final json = {
        'name': 'hello.txt',
        'path': '/home/user/hello.txt',
        'isDir': false,
        'size': 1234,
        'mimeType': 'text/plain',
        'mode': '-rw-r--r--',
        'modified': '2024-01-15T10:30:00Z',
        'created': '2024-01-10T08:00:00Z',
        'isSymlink': false,
      };
      final e = Entry.fromJson(json);
      expect(e.name, 'hello.txt');
      expect(e.path, '/home/user/hello.txt');
      expect(e.isDir, isFalse);
      expect(e.size, 1234);
      expect(e.mimeType, 'text/plain');
      expect(e.mode, '-rw-r--r--');
      expect(e.modified, DateTime.utc(2024, 1, 15, 10, 30));
      expect(e.created, DateTime.utc(2024, 1, 10, 8));
      expect(e.isSymlink, isFalse);
    });

    test('handles missing optional fields', () {
      final e = Entry.fromJson({'name': 'x', 'path': '/', 'isDir': true});
      expect(e.size, isNull);
      expect(e.mimeType, isNull);
      expect(e.modified, isNull);
      expect(e.isSymlink, isFalse);
    });

    test('round-trips through toJson', () {
      final json = {
        'name': 'doc.pdf',
        'path': '/docs/doc.pdf',
        'isDir': false,
        'size': 9999,
        'mimeType': 'application/pdf',
        'mode': '-rw-------',
        'modified': '2025-06-01T12:00:00.000Z',
        'created': '2025-05-01T00:00:00.000Z',
        'isSymlink': true,
      };
      final e = Entry.fromJson(json);
      final e2 = Entry.fromJson(e.toJson());
      expect(e2.name, e.name);
      expect(e2.path, e.path);
      expect(e2.size, e.size);
      expect(e2.isSymlink, e.isSymlink);
    });
  });

  group('Drive.fromJson', () {
    test('parses drive', () {
      final d = Drive.fromJson({
        'path': r'C:\',
        'label': 'System',
        'totalBytes': 500000000000,
        'freeBytes': 200000000000,
      });
      expect(d.path, r'C:\');
      expect(d.label, 'System');
      expect(d.totalBytes, 500000000000);
      expect(d.freeBytes, 200000000000);
    });

    test('handles missing label', () {
      final d = Drive.fromJson({'path': '/mnt/data'});
      expect(d.label, isNull);
      expect(d.totalBytes, isNull);
    });
  });

  group('Listing.fromJson', () {
    test('parses listing with entries', () {
      final l = Listing.fromJson({
        'path': '/home',
        'entries': [
          {'name': 'file.txt', 'path': '/home/file.txt', 'isDir': false},
          {'name': 'docs', 'path': '/home/docs', 'isDir': true},
        ],
        'nextCursor': 'abc123',
      });
      expect(l.path, '/home');
      expect(l.entries.length, 2);
      expect(l.entries[0].name, 'file.txt');
      expect(l.entries[1].isDir, isTrue);
      expect(l.nextCursor, 'abc123');
    });

    test('handles empty entries and no cursor', () {
      final l = Listing.fromJson({'path': '/', 'entries': []});
      expect(l.entries, isEmpty);
      expect(l.nextCursor, isNull);
    });
  });

  group('PairResponse.fromJson', () {
    test('parses full response', () {
      final p = PairResponse.fromJson({
        'deviceToken': 'tok-abc',
        'deviceId': 'dev-123',
        'agentName': 'My PC',
        'certFingerprint': 'aa:bb:cc',
      });
      expect(p.deviceToken, 'tok-abc');
      expect(p.deviceId, 'dev-123');
      expect(p.agentName, 'My PC');
      expect(p.certFingerprint, 'aa:bb:cc');
    });

    test('handles missing fingerprint', () {
      final p = PairResponse.fromJson({
        'deviceToken': 't',
        'deviceId': 'd',
        'agentName': 'n',
      });
      expect(p.certFingerprint, isNull);
    });
  });

  group('UploadSession.fromJson', () {
    test('parses session', () {
      final s = UploadSession.fromJson({
        'id': 'sess-1',
        'path': '/uploads/file.bin',
        'size': 8192,
        'chunkSize': 4096,
        'totalChunks': 2,
        'receivedChunks': [0],
        'status': 'open',
      });
      expect(s.id, 'sess-1');
      expect(s.totalChunks, 2);
      expect(s.receivedChunks, [0]);
      expect(s.status, 'open');
    });
  });

  group('Health.fromJson', () {
    test('parses health', () {
      final h = Health.fromJson({
        'status': 'ok',
        'name': 'MyAgent',
        'version': '0.1.0',
        'os': 'windows',
        'readOnly': false,
      });
      expect(h.status, 'ok');
      expect(h.os, 'windows');
      expect(h.readOnly, isFalse);
    });
  });

  group('Host', () {
    test('baseUri is correct', () {
      const h = Host(id: '1', label: 'PC', address: '192.168.1.10:8765');
      expect(h.baseUri, Uri.parse('https://192.168.1.10:8765/v1'));
    });

    test('round-trips JSON', () {
      const h = Host(
        id: 'x',
        label: 'Server',
        address: 'srv.ts.net:8765',
        certFingerprint: 'fp123',
      );
      final h2 = Host.fromJson(h.toJson());
      expect(h2.id, h.id);
      expect(h2.label, h.label);
      expect(h2.certFingerprint, h.certFingerprint);
    });

    test('copyWith overrides only given fields', () {
      const h = Host(id: '1', label: 'A', address: 'a:1');
      final h2 = h.copyWith(label: 'B');
      expect(h2.label, 'B');
      expect(h2.id, '1');
      expect(h2.address, 'a:1');
    });
  });
}
