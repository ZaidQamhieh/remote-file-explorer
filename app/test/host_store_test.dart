import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:shared_preferences/shared_preferences.dart';

// HostStore unit tests — exercises the JSON serialisation logic used by the
// store, plus SharedPreferences mock to verify the storage format.
//
// FlutterSecureStorage (token/fingerprint) requires platform channels and is
// not tested here; integration tests would cover that end-to-end.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Host JSON serialisation', () {
    test('all fields survive a JSON round-trip', () {
      const host = Host(
        id: 'abc',
        label: 'Test PC',
        address: 'pc.tailnet.ts.net:8765',
        certFingerprint: 'deadbeef',
        tailscaleName: 'pc.tailnet.ts.net',
      );
      final json = host.toJson();
      final host2 = Host.fromJson(json);

      expect(host2.id, host.id);
      expect(host2.label, host.label);
      expect(host2.address, host.address);
      expect(host2.certFingerprint, host.certFingerprint);
      expect(host2.tailscaleName, host.tailscaleName);
    });

    test('optional fields are omitted from JSON when null', () {
      const host = Host(id: 'x', label: 'y', address: 'z:1');
      final json = host.toJson();
      expect(json.containsKey('certFingerprint'), isFalse);
      expect(json.containsKey('tailscaleName'), isFalse);
    });

    test('round-trips through jsonEncode / jsonDecode', () {
      const host = Host(
        id: 'h1',
        label: 'My Server',
        address: '192.168.1.5:8765',
        certFingerprint: 'fp123',
      );
      final encoded = jsonEncode(host.toJson());
      final decoded = Host.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded.id, host.id);
      expect(decoded.certFingerprint, host.certFingerprint);
    });
  });

  group('SharedPreferences host list format', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('encode + decode preserves multiple hosts', () async {
      const hosts = [
        Host(id: 'h1', label: 'PC 1', address: '10.0.0.1:8765'),
        Host(id: 'h2', label: 'PC 2', address: '10.0.0.2:8765',
            certFingerprint: 'abc'),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'rfe_hosts_v1',
        hosts.map((h) => jsonEncode(h.toJson())).toList(),
      );

      final raw = prefs.getStringList('rfe_hosts_v1')!;
      expect(raw.length, 2);

      final decoded = raw
          .map((s) =>
              Host.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();

      expect(decoded[0].id, 'h1');
      expect(decoded[1].certFingerprint, 'abc');
    });

    test('removing a host leaves others intact', () async {
      const hosts = [
        Host(id: 'h1', label: 'A', address: 'a:1'),
        Host(id: 'h2', label: 'B', address: 'b:2'),
        Host(id: 'h3', label: 'C', address: 'c:3'),
      ];

      final prefs = await SharedPreferences.getInstance();
      var stored = hosts.map((h) => jsonEncode(h.toJson())).toList();
      await prefs.setStringList('rfe_hosts_v1', stored);

      // Simulate removal of h2
      stored = stored.where((s) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return m['id'] != 'h2';
      }).toList();
      await prefs.setStringList('rfe_hosts_v1', stored);

      final remaining = (prefs.getStringList('rfe_hosts_v1') ?? [])
          .map((s) =>
              Host.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();

      expect(remaining.length, 2);
      expect(remaining.map((h) => h.id), isNot(contains('h2')));
    });
  });
}
