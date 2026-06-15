import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Encrypted config export/import (N1).
///
/// This file is **pure** — no I/O, no Flutter, no platform plugins — so it can
/// be unit-tested directly. [BackupService] (in `backup_service.dart`) handles
/// gathering app state and writing/reading files.
///
/// ## Crypto design (frozen)
///
/// - Inner payload: JSON-encoded [BackupPayload].
/// - Key derivation: **PBKDF2-HMAC-SHA256**, 200000 iterations, 256-bit key,
///   random 16-byte salt.
/// - Cipher: **AES-GCM-256** with a random 12-byte nonce, over the UTF-8 bytes
///   of the inner JSON.
/// - Outer envelope (written to the backup file), JSON with base64 fields:
///   `{ "format": "rfe-backup", "v": 1, "kdf": "pbkdf2-hmac-sha256", "iter":
///   200000, "salt": "...", "nonce": "...", "ct": "...", "mac": "..." }`
///   (each `"..."` is a base64-encoded byte string).

/// Number of PBKDF2 iterations used to derive the AES key from the passphrase.
const int kBackupPbkdf2Iterations = 200000;

/// Length (in bytes) of the random PBKDF2 salt.
const int kBackupSaltLength = 16;

/// Derived key length, in bits.
const int _kKeyBits = 256;

const String _kFormat = 'rfe-backup';
const int _kVersion = 1;
const String _kKdf = 'pbkdf2-hmac-sha256';

/// Thrown for any backup encode/decode failure — wrong passphrase, corrupt or
/// tampered envelope, unsupported format/version, etc. The [message] is
/// human-readable and safe to show in a snackbar.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The kind of value stored under a [PrefEntry] — mirrors the
/// `SharedPreferences` types actually used by the app.
enum PrefType { boolType, intType, doubleType, stringType, stringListType }

String _prefTypeTag(PrefType t) => switch (t) {
  PrefType.boolType => 'bool',
  PrefType.intType => 'int',
  PrefType.doubleType => 'double',
  PrefType.stringType => 'string',
  PrefType.stringListType => 'stringList',
};

PrefType _prefTypeFromTag(String tag) => switch (tag) {
  'bool' => PrefType.boolType,
  'int' => PrefType.intType,
  'double' => PrefType.doubleType,
  'string' => PrefType.stringType,
  'stringList' => PrefType.stringListType,
  _ => throw BackupException('Unknown preference type "$tag" in backup.'),
};

/// A single `SharedPreferences` entry, typed so it round-trips exactly.
class PrefEntry {
  const PrefEntry(this.type, this.value);

  /// Convenience constructors that infer [type] from a `SharedPreferences`
  /// value (as returned by `prefs.get(key)`).
  factory PrefEntry.fromValue(Object value) {
    switch (value) {
      case bool b:
        return PrefEntry(PrefType.boolType, b);
      case int i:
        return PrefEntry(PrefType.intType, i);
      case double d:
        return PrefEntry(PrefType.doubleType, d);
      case String s:
        return PrefEntry(PrefType.stringType, s);
      case List<String> l:
        return PrefEntry(PrefType.stringListType, l);
      default:
        throw BackupException(
          'Unsupported preference value type: ${value.runtimeType}',
        );
    }
  }

  final PrefType type;

  /// The underlying value: `bool`, `int`, `double`, `String`, or
  /// `List<String>` depending on [type].
  final Object value;

  Map<String, dynamic> toJson() => {
    't': _prefTypeTag(type),
    'v': type == PrefType.stringListType ? value as List<String> : value,
  };

  factory PrefEntry.fromJson(Map<String, dynamic> j) {
    final type = _prefTypeFromTag(j['t'] as String);
    final raw = j['v'];
    final Object value = switch (type) {
      PrefType.boolType => raw as bool,
      PrefType.intType => (raw as num).toInt(),
      PrefType.doubleType => (raw as num).toDouble(),
      PrefType.stringType => raw as String,
      PrefType.stringListType => (raw as List).cast<String>(),
    };
    return PrefEntry(type, value);
  }

  @override
  bool operator ==(Object other) {
    if (other is! PrefEntry || other.type != type) return false;
    if (type == PrefType.stringListType) {
      final a = value as List<String>;
      final b = other.value as List<String>;
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return other.value == value;
  }

  @override
  int get hashCode =>
      type == PrefType.stringListType
          ? Object.hashAll([type, ...(value as List<String>)])
          : Object.hash(type, value);
}

/// The full app-state snapshot that gets encrypted into a backup file.
class BackupPayload {
  const BackupPayload({
    required this.version,
    required this.createdAt,
    required this.prefs,
    required this.secure,
  });

  /// Builds a payload stamped with [DateTime.now] (UTC) and version 1.
  factory BackupPayload.create({
    required Map<String, PrefEntry> prefs,
    required Map<String, String> secure,
  }) => BackupPayload(
    version: _kVersion,
    createdAt: DateTime.now().toUtc(),
    prefs: prefs,
    secure: secure,
  );

  final int version;
  final DateTime createdAt;
  final Map<String, PrefEntry> prefs;
  final Map<String, String> secure;

  Map<String, dynamic> toJson() => {
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    'prefs': prefs.map((k, v) => MapEntry(k, v.toJson())),
    'secure': secure,
  };

  factory BackupPayload.fromJson(Map<String, dynamic> j) {
    final prefsJson = j['prefs'];
    final secureJson = j['secure'];
    if (prefsJson is! Map || secureJson is! Map) {
      throw const BackupException('Malformed backup payload.');
    }
    return BackupPayload(
      version: (j['version'] as num?)?.toInt() ?? 1,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      prefs: prefsJson.map(
        (k, v) => MapEntry(
          k as String,
          PrefEntry.fromJson(v as Map<String, dynamic>),
        ),
      ),
      secure: secureJson.map((k, v) => MapEntry(k as String, v as String)),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! BackupPayload) return false;
    if (other.version != version) return false;
    if (other.createdAt != createdAt) return false;
    if (other.secure.length != secure.length) return false;
    for (final entry in secure.entries) {
      if (other.secure[entry.key] != entry.value) return false;
    }
    if (other.prefs.length != prefs.length) return false;
    for (final entry in prefs.entries) {
      if (other.prefs[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    version,
    createdAt,
    Object.hashAllUnordered(
      prefs.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      secure.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Encode / decode (pure crypto, no I/O)
// ---------------------------------------------------------------------------

final _random = Random.secure();

List<int> _randomBytes(int length) =>
    List<int>.generate(length, (_) => _random.nextInt(256));

Pbkdf2 _kdf() => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: kBackupPbkdf2Iterations,
  bits: _kKeyBits,
);

/// Encrypts [payload] with [passphrase], returning the envelope JSON string
/// that gets written to the backup file.
Future<String> encodeBackup(BackupPayload payload, String passphrase) async {
  final salt = _randomBytes(kBackupSaltLength);
  final secretKey = await _kdf().deriveKeyFromPassword(
    password: passphrase,
    nonce: salt,
  );

  final algorithm = AesGcm.with256bits();
  final nonce = algorithm.newNonce();
  final plaintext = utf8.encode(jsonEncode(payload.toJson()));

  final secretBox = await algorithm.encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: nonce,
  );

  final envelope = {
    'format': _kFormat,
    'v': _kVersion,
    'kdf': _kKdf,
    'iter': kBackupPbkdf2Iterations,
    'salt': base64Encode(salt),
    'nonce': base64Encode(secretBox.nonce),
    'ct': base64Encode(secretBox.cipherText),
    'mac': base64Encode(secretBox.mac.bytes),
  };
  return jsonEncode(envelope);
}

/// Decrypts [envelopeJson] (as produced by [encodeBackup]) with [passphrase],
/// returning the original [BackupPayload].
///
/// Throws [BackupException] if the envelope is malformed/unsupported, the
/// passphrase is wrong, or the ciphertext/MAC has been tampered with.
Future<BackupPayload> decodeBackup(
  String envelopeJson,
  String passphrase,
) async {
  late final Map<String, dynamic> envelope;
  try {
    envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
  } catch (_) {
    throw const BackupException('This file is not a valid backup.');
  }

  if (envelope['format'] != _kFormat) {
    throw const BackupException('This file is not an RFE backup.');
  }
  if (envelope['v'] != _kVersion) {
    throw BackupException('Unsupported backup version: ${envelope['v']}.');
  }
  if (envelope['kdf'] != _kKdf) {
    throw BackupException('Unsupported key derivation: ${envelope['kdf']}.');
  }

  final List<int> salt;
  final List<int> nonce;
  final List<int> ct;
  final List<int> mac;
  final int iterations;
  try {
    salt = base64Decode(envelope['salt'] as String);
    nonce = base64Decode(envelope['nonce'] as String);
    ct = base64Decode(envelope['ct'] as String);
    mac = base64Decode(envelope['mac'] as String);
    iterations = (envelope['iter'] as num).toInt();
  } catch (_) {
    throw const BackupException('This backup file is corrupted.');
  }

  final secretKey = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: _kKeyBits,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  final algorithm = AesGcm.with256bits();
  final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(mac));

  List<int> plaintext;
  try {
    plaintext = await algorithm.decrypt(secretBox, secretKey: secretKey);
  } on SecretBoxAuthenticationError {
    throw const BackupException(
      'Incorrect passphrase, or this backup file has been corrupted.',
    );
  } catch (_) {
    throw const BackupException(
      'Incorrect passphrase, or this backup file has been corrupted.',
    );
  }

  try {
    final decoded = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    return BackupPayload.fromJson(decoded);
  } catch (_) {
    throw const BackupException('This backup file is corrupted.');
  }
}
