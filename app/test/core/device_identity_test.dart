// Tests for tryParseDeviceKeyPair, the pure validation behind
// DeviceIdentity's PR-55 corruption-recovery fix: malformed stored key
// material must fall back to regenerating a fresh identity, not crash.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/security/device_identity.dart';

void main() {
  group('tryParseDeviceKeyPair', () {
    test('valid 32-byte keys parse successfully', () async {
      final priv = base64Encode(List<int>.filled(32, 7));
      final pub = base64Encode(List<int>.filled(32, 9));

      final parsed = tryParseDeviceKeyPair(priv, pub);

      expect(parsed, isNotNull);
      expect(await parsed!.extractPrivateKeyBytes(), List<int>.filled(32, 7));
      final publicKey = await parsed.extractPublicKey();
      expect(publicKey.bytes, List<int>.filled(32, 9));
    });

    test('wrong-length key material returns null instead of throwing', () {
      final shortPriv = base64Encode(List<int>.filled(16, 1));
      final pub = base64Encode(List<int>.filled(32, 2));

      expect(tryParseDeviceKeyPair(shortPriv, pub), isNull);
    });

    test('non-base64 stored value returns null instead of throwing', () {
      expect(tryParseDeviceKeyPair('not-valid-base64!!', 'also-not'), isNull);
    });
  });
}
