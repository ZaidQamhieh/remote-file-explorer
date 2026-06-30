import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/share_link.dart';

void main() {
  group('ShareLink.fromJson', () {
    test('parses a mint response (token, tokenHash, expiresAt, url)', () {
      final json = {
        'token': 'raw-token-hex',
        'tokenHash': 'hash-hex',
        'expiresAt': 1234567890,
        'url': 'https://10.0.0.1:8765/v1/share/raw-token-hex',
      };
      final l = ShareLink.fromJson(json);
      expect(l.token, 'raw-token-hex');
      expect(l.tokenHash, 'hash-hex');
      expect(l.path, '');
      expect(l.expiresAt, 1234567890);
      expect(l.url, 'https://10.0.0.1:8765/v1/share/raw-token-hex');
    });

    test('parses a list-entry response (no token/url, has path)', () {
      final json = {
        'tokenHash': 'hash-hex',
        'path': '/home/me/file.txt',
        'expiresAt': 42,
      };
      final l = ShareLink.fromJson(json);
      expect(l.token, '');
      expect(l.tokenHash, 'hash-hex');
      expect(l.path, '/home/me/file.txt');
      expect(l.expiresAt, 42);
      expect(l.url, '');
    });

    test('defaults missing fields', () {
      final l = ShareLink.fromJson({});
      expect(l.token, '');
      expect(l.tokenHash, '');
      expect(l.path, '');
      expect(l.expiresAt, 0);
      expect(l.url, '');
    });
  });
}
