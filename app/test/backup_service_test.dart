import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/backup/backup_service.dart';
import 'package:remote_file_explorer/core/backup/config_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

// BackupService unit tests — export/import round-trip against a mocked
// SharedPreferences and an in-memory fake SecureKv.

/// Simple in-memory fake for [SecureKv], used in place of
/// FlutterSecureStorage (which requires platform channels).
class FakeSecureKv implements SecureKv {
  final Map<String, String> store = {};

  /// Keys that throw on write, for simulating a failure partway through a
  /// restore (PR-21's rollback test).
  final Set<String> failOnWrite = {};

  @override
  Future<Map<String, String>> readAll() async => Map.of(store);

  @override
  Future<void> write(String key, String value) async {
    if (failOnWrite.contains(key)) {
      throw Exception('simulated write failure: $key');
    }
    store[key] = value;
  }

  @override
  Future<void> deleteAll() async {
    store.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const passphrase = 'super-secret-passphrase';

  group('BackupService export/import round-trip', () {
    test('reproduces prefs (with types) and secure entries', () async {
      SharedPreferences.setMockInitialValues({
        'rfe_hosts_v1': ['{"id":"h1"}', '{"id":"h2"}'],
        'app.themeMode': 'dark',
        'host.h1.sortField': 'size',
        'rfe_some_int': 7,
        'rfe_some_bool': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final secure = FakeSecureKv();
      await secure.write('rfe_token_h1', 'tok-abc');
      await secure.write('rfe_fp_h1', 'fp-123');

      final service = BackupService(prefs, secure);
      final envelope = await service.exportToEnvelope(passphrase);

      // Sanity: the envelope round-trips through decodeBackup directly too.
      final payload = await decodeBackup(envelope, passphrase);
      expect(payload.prefs['rfe_hosts_v1']!.value, [
        '{"id":"h1"}',
        '{"id":"h2"}',
      ]);
      expect(payload.prefs['app.themeMode']!.value, 'dark');
      expect(payload.prefs['host.h1.sortField']!.value, 'size');
      expect(payload.prefs['rfe_some_int']!.value, 7);
      expect(payload.prefs['rfe_some_int']!.type, PrefType.intType);
      expect(payload.prefs['rfe_some_bool']!.value, true);
      expect(payload.secure['rfe_token_h1'], 'tok-abc');
      expect(payload.secure['rfe_fp_h1'], 'fp-123');

      // Now mutate state on "this device" before importing — simulates a
      // fresh install with different (or no) data.
      await prefs.clear();
      await prefs.setString('rfe_hosts_v1', 'should-be-overwritten');
      secure.store.clear();
      await secure.write('rfe_token_other', 'leftover');

      await service.importFromEnvelope(envelope, passphrase);

      expect(prefs.getStringList('rfe_hosts_v1'), [
        '{"id":"h1"}',
        '{"id":"h2"}',
      ]);
      expect(prefs.getString('app.themeMode'), 'dark');
      expect(prefs.getString('host.h1.sortField'), 'size');
      expect(prefs.getInt('rfe_some_int'), 7);
      expect(prefs.getBool('rfe_some_bool'), true);

      expect(await secure.readAll(), {
        'rfe_token_h1': 'tok-abc',
        'rfe_fp_h1': 'fp-123',
      });
    });

    test(
      'replace semantics: a stale rfe_ key not in the backup is removed',
      () async {
        SharedPreferences.setMockInitialValues({
          'rfe_hosts_v1': ['{"id":"h1"}'],
          'app.gridView': false,
        });
        final prefs = await SharedPreferences.getInstance();
        final secure = FakeSecureKv();
        final service = BackupService(prefs, secure);

        final envelope = await service.exportToEnvelope(passphrase);

        // Add an extra "stale" key that is NOT part of the exported backup.
        await prefs.setString('rfe_stale_leftover', 'orphan');
        expect(prefs.containsKey('rfe_stale_leftover'), isTrue);

        await service.importFromEnvelope(envelope, passphrase);

        expect(prefs.containsKey('rfe_stale_leftover'), isFalse);
        expect(prefs.getStringList('rfe_hosts_v1'), ['{"id":"h1"}']);
        expect(prefs.getBool('app.gridView'), false);
      },
    );

    test(
      'never exports the private device identity key, and refuses to '
      'import one even from an old-format backup that has it (PR-17)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final secure = FakeSecureKv();
        await secure.write(
          'rfe_device_identity_private_v1',
          'super-secret-key',
        );
        await secure.write('rfe_device_identity_public_v1', 'public-key');
        await secure.write('rfe_token_h1', 'tok-abc');

        final service = BackupService(prefs, secure);
        final envelope = await service.exportToEnvelope(passphrase);

        final payload = await decodeBackup(envelope, passphrase);
        expect(
          payload.secure.containsKey('rfe_device_identity_private_v1'),
          isFalse,
        );
        expect(payload.secure['rfe_device_identity_public_v1'], 'public-key');
        expect(payload.secure['rfe_token_h1'], 'tok-abc');

        // Simulate importing an old-format backup that DOES carry a private
        // identity key (hand-crafted here, since exportToEnvelope can no
        // longer produce one) — e.g. a backup taken before this fix, or a
        // tampered file trying to plant a foreign identity on this device.
        final legacyPayload = BackupPayload.create(
          prefs: const {},
          secure: {
            'rfe_device_identity_private_v1': 'attacker-supplied-key',
            'rfe_token_h1': 'tok-abc',
          },
        );
        final legacyEnvelope = await encodeBackup(legacyPayload, passphrase);

        await service.importFromEnvelope(legacyEnvelope, passphrase);

        // The attacker's key must never land — full stop. (Secure storage
        // is wiped and rebuilt on every import regardless, per the existing
        // replace semantics, so this device's own prior identity is gone
        // too; DeviceIdentity lazily regenerates a fresh one on next use,
        // requiring re-pairing — the accepted trade-off for never letting a
        // private identity round-trip through a backup at all.)
        final after = await secure.readAll();
        expect(
          after['rfe_device_identity_private_v1'],
          isNot('attacker-supplied-key'),
        );
        expect(after.containsKey('rfe_device_identity_private_v1'), isFalse);
        expect(after['rfe_token_h1'], 'tok-abc');
      },
    );

    test(
      'a write failure partway through import rolls back to the '
      'pre-restore state instead of leaving a half-written install (PR-21)',
      () async {
        SharedPreferences.setMockInitialValues({
          'rfe_hosts_v1': ['{"id":"original"}'],
          'app.themeMode': 'light',
        });
        final prefs = await SharedPreferences.getInstance();
        final secure = FakeSecureKv();
        await secure.write('rfe_token_h1', 'original-token');
        final service = BackupService(prefs, secure);

        // Build a backup with different prefs and a secure key that will
        // fail to write, simulating a platform error mid-restore.
        final payload = BackupPayload.create(
          prefs: {
            'rfe_hosts_v1': PrefEntry.fromValue(['{"id":"new"}']),
            'app.themeMode': PrefEntry.fromValue('dark'),
          },
          secure: {'rfe_token_h2': 'new-token'},
        );
        final envelope = await encodeBackup(payload, passphrase);
        secure.failOnWrite.add('rfe_token_h2');

        await expectLater(
          service.importFromEnvelope(envelope, passphrase),
          throwsException,
        );

        // Rolled back, not half-applied: original prefs and secure state
        // are both back exactly as they were.
        expect(prefs.getStringList('rfe_hosts_v1'), ['{"id":"original"}']);
        expect(prefs.getString('app.themeMode'), 'light');
        expect(await secure.readAll(), {'rfe_token_h1': 'original-token'});
      },
    );

    test('non-rfe/app/host keys are left untouched on import', () async {
      SharedPreferences.setMockInitialValues({
        'rfe_hosts_v1': ['{"id":"h1"}'],
        'unrelated.key': 'keep-me',
      });
      final prefs = await SharedPreferences.getInstance();
      final secure = FakeSecureKv();
      final service = BackupService(prefs, secure);

      final envelope = await service.exportToEnvelope(passphrase);
      await service.importFromEnvelope(envelope, passphrase);

      expect(prefs.getString('unrelated.key'), 'keep-me');
    });
  });
}
