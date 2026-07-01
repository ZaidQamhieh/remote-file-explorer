// Tests for C1's QR hand-off host matching: matchHandoffHost (the pure core
// of _QrScanScreenState._onBarcodeDetected in qr_scan_screen.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/handoff/qr_scan_screen.dart';

Host _host(String id, String? fp) =>
    Host(id: id, label: id, address: '$id:8765', certFingerprint: fp);

void main() {
  group('matchHandoffHost', () {
    test('empty list returns null', () {
      expect(matchHandoffHost(const [], 'aa'), isNull);
    });

    test('no match returns null', () {
      final hosts = [_host('a', 'fp-a'), _host('b', 'fp-b')];
      expect(matchHandoffHost(hosts, 'fp-zzz'), isNull);
    });

    test('single match returns that host', () {
      final hosts = [_host('a', 'fp-a')];
      expect(matchHandoffHost(hosts, 'fp-a')?.id, 'a');
    });

    test('multiple hosts, one matches', () {
      final hosts = [
        _host('a', 'fp-a'),
        _host('b', 'fp-b'),
        _host('c', 'fp-c'),
      ];
      expect(matchHandoffHost(hosts, 'fp-b')?.id, 'b');
    });

    test('hosts with no fingerprint never match', () {
      final hosts = [_host('a', null), _host('b', 'fp-b')];
      expect(matchHandoffHost(hosts, 'fp-b')?.id, 'b');
      expect(matchHandoffHost([_host('a', null)], 'fp-a'), isNull);
    });
  });

  group('HandoffPayload.tryParse', () {
    test('valid JSON parses all fields', () {
      final p = HandoffPayload.tryParse(
        '{"certFingerprint":"fp","path":"/a/b.txt","name":"b.txt"}',
      );
      expect(p?.certFingerprint, 'fp');
      expect(p?.path, '/a/b.txt');
      expect(p?.name, 'b.txt');
    });

    test('invalid JSON returns null', () {
      expect(HandoffPayload.tryParse('not json'), isNull);
    });

    test('missing field returns null', () {
      expect(
        HandoffPayload.tryParse('{"certFingerprint":"fp","path":"/a"}'),
        isNull,
      );
    });
  });
}
