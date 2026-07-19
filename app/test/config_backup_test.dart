import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/backup/config_backup.dart';

// config_backup.dart unit tests — pure crypto round-trip, wrong-passphrase
// and tamper-detection behaviour, and envelope shape.

void main() {
  BackupPayload samplePayload() => BackupPayload.create(
    prefs: {
      'rfe_hosts_v1': const PrefEntry(PrefType.stringListType, [
        '{"id":"h1"}',
        '{"id":"h2"}',
      ]),
      'app.themeMode': const PrefEntry(PrefType.stringType, 'dark'),
      'app.dynamicColor': const PrefEntry(PrefType.boolType, true),
      'host.h1.sortAscending': const PrefEntry(PrefType.boolType, false),
      'some.intValue': const PrefEntry(PrefType.intType, 42),
      'some.doubleValue': const PrefEntry(PrefType.doubleType, 3.14),
    },
    secure: {'rfe_token_h1': 'tok-123', 'rfe_fp_h1': 'aa:bb:cc'},
  );

  group('encodeBackup / decodeBackup', () {
    test('round-trip returns an equal payload', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'correct horse battery');
      final decoded = await decodeBackup(envelope, 'correct horse battery');

      expect(decoded, payload);
      expect(decoded.prefs, payload.prefs);
      expect(decoded.secure, payload.secure);
      expect(decoded.version, payload.version);
      expect(decoded.createdAt, payload.createdAt);
    });

    test('preserves all pref types exactly', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final decoded = await decodeBackup(envelope, 'passphrase12');

      expect(decoded.prefs['rfe_hosts_v1']!.value, [
        '{"id":"h1"}',
        '{"id":"h2"}',
      ]);
      expect(decoded.prefs['rfe_hosts_v1']!.type, PrefType.stringListType);
      expect(decoded.prefs['app.themeMode']!.value, 'dark');
      expect(decoded.prefs['app.themeMode']!.type, PrefType.stringType);
      expect(decoded.prefs['app.dynamicColor']!.value, true);
      expect(decoded.prefs['app.dynamicColor']!.type, PrefType.boolType);
      expect(decoded.prefs['host.h1.sortAscending']!.value, false);
      expect(decoded.prefs['some.intValue']!.value, 42);
      expect(decoded.prefs['some.intValue']!.type, PrefType.intType);
      expect(decoded.prefs['some.doubleValue']!.value, 3.14);
      expect(decoded.prefs['some.doubleValue']!.type, PrefType.doubleType);
    });

    test('wrong passphrase throws BackupException', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'right-passphrase');

      expect(
        () => decodeBackup(envelope, 'wrong-passphrase'),
        throwsA(isA<BackupException>()),
      );
    });

    test('tampering with the ciphertext throws BackupException', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;

      // Flip a byte in the ciphertext.
      final ctBytes = base64Decode(map['ct'] as String);
      ctBytes[0] = ctBytes[0] ^ 0xFF;
      map['ct'] = base64Encode(ctBytes);
      final tampered = jsonEncode(map);

      expect(
        () => decodeBackup(tampered, 'passphrase12'),
        throwsA(isA<BackupException>()),
      );
    });

    test('tampering with the MAC throws BackupException', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;

      final macBytes = base64Decode(map['mac'] as String);
      macBytes[0] = macBytes[0] ^ 0xFF;
      map['mac'] = base64Encode(macBytes);
      final tampered = jsonEncode(map);

      expect(
        () => decodeBackup(tampered, 'passphrase12'),
        throwsA(isA<BackupException>()),
      );
    });

    test('envelope is valid JSON with the documented fields', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;

      expect(map['format'], 'rfe-backup');
      expect(map['v'], 1);
      expect(map['kdf'], 'pbkdf2-hmac-sha256');
      expect(map['iter'], kBackupPbkdf2Iterations);
      expect(map['salt'], isA<String>());
      expect(map['nonce'], isA<String>());
      expect(map['ct'], isA<String>());
      expect(map['mac'], isA<String>());

      // salt should decode to kBackupSaltLength bytes.
      expect(base64Decode(map['salt'] as String).length, kBackupSaltLength);
      // AES-GCM nonce is 12 bytes.
      expect(base64Decode(map['nonce'] as String).length, 12);
    });
  });

  group('envelope bounds (PR-22)', () {
    test('encodeBackup rejects a passphrase shorter than the minimum', () {
      final payload = samplePayload();
      expect(
        () => encodeBackup(payload, 'short'),
        throwsA(isA<BackupException>()),
      );
    });

    test('decodeBackup rejects an iteration count above the cap', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      map['iter'] = kBackupMaxIterations + 1;

      expect(
        () => decodeBackup(jsonEncode(map), 'passphrase12'),
        throwsA(isA<BackupException>()),
      );
    });

    test('decodeBackup rejects a zero/negative iteration count', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      map['iter'] = 0;

      expect(
        () => decodeBackup(jsonEncode(map), 'passphrase12'),
        throwsA(isA<BackupException>()),
      );
    });

    test('decodeBackup rejects an oversized ciphertext field', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      map['ct'] = base64Encode(
        List<int>.filled(kBackupMaxCiphertextLength + 1, 0),
      );

      expect(
        () => decodeBackup(jsonEncode(map), 'passphrase12'),
        throwsA(isA<BackupException>()),
      );
    });

    test('decodeBackup rejects an oversized salt field', () async {
      final payload = samplePayload();
      final envelope = await encodeBackup(payload, 'passphrase12');
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      map['salt'] = base64Encode(List<int>.filled(kBackupMaxSaltLength + 1, 0));

      expect(
        () => decodeBackup(jsonEncode(map), 'passphrase12'),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
