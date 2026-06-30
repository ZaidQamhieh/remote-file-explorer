import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/hosts/host_open_listener.dart';

void main() {
  const hostA = Host(
    id: 'host-1',
    label: 'Desk PC',
    address: '192.168.1.20:8765',
  );
  const hostB = Host(
    id: 'host-2',
    label: 'Laptop',
    address: '192.168.1.21:8765',
  );

  group('resolveHostById', () {
    test('returns the matching host', () {
      expect(resolveHostById([hostA, hostB], 'host-2'), hostB);
    });

    test('returns null when no host matches', () {
      expect(resolveHostById([hostA, hostB], 'unknown'), isNull);
    });

    test('returns null for an empty host list', () {
      expect(resolveHostById([], 'host-1'), isNull);
    });
  });
}
