import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/security/device_identity.dart';

/// In-memory stand-in for the native flutter_secure_storage platform channel
/// — there's no real Keystore/Keychain in `flutter test`.
void _mockSecureStorageChannel() {
  final store = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map).cast<String, dynamic>();
        switch (call.method) {
          case 'read':
            return store[args['key']];
          case 'write':
            store[args['key'] as String] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(args['key']);
            return null;
          case 'containsKey':
            return store.containsKey(args['key']);
          default:
            return null;
        }
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockSecureStorageChannel();

  test(
    'publicKeyBase64 is stable and signBase64 produces a verifiable signature',
    () async {
      final identity = DeviceIdentity.instance;
      final publicKeyB64 = await identity.publicKeyBase64();
      final publicKeyB64Again = await identity.publicKeyBase64();
      expect(publicKeyB64, publicKeyB64Again);

      const message = 'test-nonce-123';
      final signatureB64 = await identity.signBase64(message);

      final algorithm = Ed25519();
      final isValid = await algorithm.verify(
        utf8.encode(message),
        signature: Signature(
          base64Decode(signatureB64),
          publicKey: SimplePublicKey(
            base64Decode(publicKeyB64),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      expect(isValid, isTrue);

      // A signature over a different message must not verify.
      final isValidForWrongMessage = await algorithm.verify(
        utf8.encode('a-different-message'),
        signature: Signature(
          base64Decode(signatureB64),
          publicKey: SimplePublicKey(
            base64Decode(publicKeyB64),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      expect(isValidForWrongMessage, isFalse);
    },
  );
}
