import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// This device's permanent Ed25519 identity — generated once, kept in
/// [FlutterSecureStorage] (Android Keystore-backed) for the life of the app
/// install. Every agent this phone pairs/logs into pins this same public key
/// per device row (see the agent's `verifyDeviceProof`), so a stolen bearer
/// token alone can't let an attacker re-mint a token as this device from a
/// different key — the private key never leaves the device.
class DeviceIdentity {
  DeviceIdentity._();

  static final DeviceIdentity instance = DeviceIdentity._();

  static const _kPrivateKey = 'rfe_device_identity_private_v1';
  static const _kPublicKey = 'rfe_device_identity_public_v1';

  final _secure = const FlutterSecureStorage();
  final _algorithm = Ed25519();
  SimpleKeyPair? _cached;

  Future<SimpleKeyPair> _keyPair() async {
    final cached = _cached;
    if (cached != null) return cached;

    final storedPriv = await _secure.read(key: _kPrivateKey);
    final storedPub = await _secure.read(key: _kPublicKey);
    if (storedPriv != null && storedPub != null) {
      final keyPair = SimpleKeyPairData(
        base64Decode(storedPriv),
        publicKey: SimplePublicKey(
          base64Decode(storedPub),
          type: KeyPairType.ed25519,
        ),
        type: KeyPairType.ed25519,
      );
      _cached = keyPair;
      return keyPair;
    }

    final keyPair = await _algorithm.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();
    await _secure.write(key: _kPrivateKey, value: base64Encode(privBytes));
    await _secure.write(key: _kPublicKey, value: base64Encode(pubKey.bytes));
    _cached = keyPair;
    return keyPair;
  }

  /// This device's public key, standard base64 — send as `devicePublicKey`
  /// on `/pair`, `/register`, and `/login`.
  Future<String> publicKeyBase64() async {
    final pub = await (await _keyPair()).extractPublicKey();
    return base64Encode(pub.bytes);
  }

  /// Signs [message] (typically a challenge nonce from `/auth/challenge`)
  /// with this device's private key, standard base64 — send as `signature`.
  Future<String> signBase64(String message) async {
    final signature = await _algorithm.sign(
      utf8.encode(message),
      keyPair: await _keyPair(),
    );
    return base64Encode(signature.bytes);
  }
}
