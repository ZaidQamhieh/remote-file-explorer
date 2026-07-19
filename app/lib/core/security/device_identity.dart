import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Parses stored Ed25519 key material, validating it decodes to the
/// algorithm's fixed 32-byte key lengths — returns null (never throws) for
/// anything else, so a truncated write or corrupted keystore entry falls
/// back to regenerating a fresh identity instead of crashing every call
/// that needs one (PR-55). Pure and unit-testable on its own.
SimpleKeyPairData? tryParseDeviceKeyPair(String storedPriv, String storedPub) {
  try {
    final privBytes = base64Decode(storedPriv);
    final pubBytes = base64Decode(storedPub);
    if (privBytes.length != 32 || pubBytes.length != 32) return null;
    return SimpleKeyPairData(
      privBytes,
      publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
  } catch (_) {
    return null;
  }
}

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

  /// The in-flight load/generate call, so concurrent first-callers (e.g.
  /// `/pair` and `/register` firing near-simultaneously on a cold start)
  /// await the *same* future instead of racing separate reads and each
  /// generating and writing a different keypair (PR-55).
  Future<SimpleKeyPair>? _pending;

  Future<SimpleKeyPair> _keyPair() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _pending ??= _loadOrCreate().then((keyPair) {
      _cached = keyPair;
      _pending = null;
      return keyPair;
    });
  }

  Future<SimpleKeyPair> _loadOrCreate() async {
    final storedPriv = await _secure.read(key: _kPrivateKey);
    final storedPub = await _secure.read(key: _kPublicKey);
    if (storedPriv != null && storedPub != null) {
      final parsed = tryParseDeviceKeyPair(storedPriv, storedPub);
      if (parsed != null) return parsed;
      // Malformed stored material (truncated write, corrupted keystore
      // entry) — fall through and regenerate rather than crash every call
      // that needs the identity (PR-55).
    }
    return _generateAndStore();
  }

  Future<SimpleKeyPair> _generateAndStore() async {
    final keyPair = await _algorithm.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();
    await _secure.write(key: _kPrivateKey, value: base64Encode(privBytes));
    await _secure.write(key: _kPublicKey, value: base64Encode(pubKey.bytes));
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
