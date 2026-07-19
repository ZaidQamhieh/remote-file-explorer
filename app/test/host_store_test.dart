import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/storage/host_store.dart';
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
        jsonDecode(encoded) as Map<String, dynamic>,
      );
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
        Host(
          id: 'h2',
          label: 'PC 2',
          address: '10.0.0.2:8765',
          certFingerprint: 'abc',
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'rfe_hosts_v1',
        hosts.map((h) => jsonEncode(h.toJson())).toList(),
      );

      final raw = prefs.getStringList('rfe_hosts_v1')!;
      expect(raw.length, 2);

      final decoded =
          raw
              .map((s) => Host.fromJson(jsonDecode(s) as Map<String, dynamic>))
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
      stored =
          stored.where((s) {
            final m = jsonDecode(s) as Map<String, dynamic>;
            return m['id'] != 'h2';
          }).toList();
      await prefs.setStringList('rfe_hosts_v1', stored);

      final remaining =
          (prefs.getStringList('rfe_hosts_v1') ?? [])
              .map((s) => Host.fromJson(jsonDecode(s) as Map<String, dynamic>))
              .toList();

      expect(remaining.length, 2);
      expect(remaining.map((h) => h.id), isNot(contains('h2')));
    });

    test('one corrupt entry is skipped instead of bricking the whole host '
        'list (PR-54)', () async {
      const good1 = Host(id: 'h1', label: 'A', address: 'a:1');
      const good2 = Host(id: 'h2', label: 'B', address: 'b:2');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('rfe_hosts_v1', [
        jsonEncode(good1.toJson()),
        'not valid json at all',
        jsonEncode(good2.toJson()),
        jsonEncode({'label': 'missing required id/address fields'}),
      ]);

      final store = await HostStore.create();
      final hosts = store.listHosts();

      expect(hosts.map((h) => h.id), containsAll(<String>['h1', 'h2']));
      expect(hosts.length, 2);
    });
  });

  group('commitPairingSteps (PR-37)', () {
    test('runs addHost then setToken then setFingerprint in order', () async {
      final calls = <String>[];
      await commitPairingSteps(
        addHost: () async => calls.add('addHost'),
        setToken: () async => calls.add('setToken'),
        setFingerprint: () async => calls.add('setFingerprint'),
        removeHost: () async => calls.add('removeHost'),
      );
      expect(calls, ['addHost', 'setToken', 'setFingerprint']);
    });

    test('skips setFingerprint when null (unpinned host)', () async {
      final calls = <String>[];
      await commitPairingSteps(
        addHost: () async => calls.add('addHost'),
        setToken: () async => calls.add('setToken'),
        setFingerprint: null,
        removeHost: () async => calls.add('removeHost'),
      );
      expect(calls, ['addHost', 'setToken']);
    });

    test(
      'a setToken failure rolls back the just-added host and rethrows',
      () async {
        final calls = <String>[];
        await expectLater(
          commitPairingSteps(
            addHost: () async => calls.add('addHost'),
            setToken: () async => throw Exception('secure storage full'),
            setFingerprint: () async => calls.add('setFingerprint'),
            removeHost: () async => calls.add('removeHost'),
          ),
          throwsException,
        );
        // Host was added, then rolled back; fingerprint was never attempted.
        expect(calls, ['addHost', 'removeHost']);
      },
    );

    test('a setFingerprint failure rolls back the host even though the token '
        'write already succeeded', () async {
      final calls = <String>[];
      await expectLater(
        commitPairingSteps(
          addHost: () async => calls.add('addHost'),
          setToken: () async => calls.add('setToken'),
          setFingerprint: () async => throw Exception('secure storage full'),
          removeHost: () async => calls.add('removeHost'),
        ),
        throwsException,
      );
      expect(calls, ['addHost', 'setToken', 'removeHost']);
    });
  });

  group('Last-seen timestamp', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when never recorded', () async {
      final store = await HostStore.create();
      expect(store.getLastSeen('h1'), isNull);
    });

    test('round-trips a recorded timestamp', () async {
      final store = await HostStore.create();
      final now = DateTime.now();
      await store.setLastSeen('h1', now);

      final got = store.getLastSeen('h1');
      expect(got, isNotNull);
      // SharedPreferences stores millisecond precision.
      expect(got!.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('defaults to now when no timestamp is given', () async {
      final store = await HostStore.create();
      final before = DateTime.now();
      await store.setLastSeen('h1');
      final after = DateTime.now();

      final got = store.getLastSeen('h1')!;
      expect(
        got.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(got.isAfter(after.add(const Duration(seconds: 1))), isFalse);
    });

    test('timestamps for different hosts are independent', () async {
      final store = await HostStore.create();
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 6, 1);
      await store.setLastSeen('h1', t1);
      await store.setLastSeen('h2', t2);

      expect(
        store.getLastSeen('h1')!.millisecondsSinceEpoch,
        t1.millisecondsSinceEpoch,
      );
      expect(
        store.getLastSeen('h2')!.millisecondsSinceEpoch,
        t2.millisecondsSinceEpoch,
      );
    });
  });
}
