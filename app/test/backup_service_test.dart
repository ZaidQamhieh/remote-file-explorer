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

  @override
  Future<Map<String, String>> readAll() async => Map.of(store);

  @override
  Future<void> write(String key, String value) async {
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
