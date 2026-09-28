import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Aggregate byte budget for the whole offline body cache across all hosts.
const int kOfflineCacheMaxBytes = 500 * 1024 * 1024;

/// Storage abstraction for the cache's encryption key.
///
/// Implementations must keep the key in platform secure storage. The default
/// implementation below uses Keychain/Keystore through flutter_secure_storage;
/// this interface exists so tests can inject an in-memory store.
abstract interface class OfflineBodyCacheKeyStore {
  Future<Uint8List?> readKey();

  Future<void> writeKey(Uint8List key);
}

/// Signals that an encrypted cache entry failed its authenticated check.
class OfflineBodyCacheIntegrityException implements Exception {
  const OfflineBodyCacheIntegrityException();

  @override
  String toString() => 'Offline body cache entry failed authentication';
}

class _SecureStorageKeyStore implements OfflineBodyCacheKeyStore {
  _SecureStorageKeyStore(this._storage);

  static const _keyName = 'rfe.offline_body_cache.aes_gcm_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> readKey() async {
    final encoded = await _storage.read(key: _keyName);
    if (encoded == null) return null;
    try {
      final key = Uint8List.fromList(base64Url.decode(encoded));
      if (key.length != 32) {
        throw const FormatException('Unexpected key length');
      }
      return key;
    } on FormatException catch (error) {
      throw StateError('Offline cache secure key is invalid: $error');
    }
  }

  @override
  Future<void> writeKey(Uint8List key) async {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key.length', 'must be 32 bytes');
    }
    await _storage.write(key: _keyName, value: base64UrlEncode(key));
  }
}

/// Persists AES-GCM encrypted file bodies for offline access.
///
/// Body files remain in `<app-support>/offline_cache`, with the same
/// host/path-derived name used by the previous plaintext implementation. Each
/// file contains a format marker, a 12-byte nonce, a 16-byte authentication
/// tag, and ciphertext. The AES-256 key is generated once and stored only in
/// platform secure storage; it is never written beside the cache files.
class OfflineBodyCache {
  OfflineBodyCache({
    Directory? baseDir,
    FlutterSecureStorage? secureStorage,
    OfflineBodyCacheKeyStore? keyStore,
  }) : _baseDir = baseDir,
       _keyStore =
           keyStore ??
           _SecureStorageKeyStore(
             secureStorage ?? const FlutterSecureStorage(),
           );

  static const List<int> _magic = <int>[
    0x52,
    0x46,
    0x45,
    0x4f,
    0x42,
    0x43,
    0x01,
    0x0a,
  ];
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _headerLength = 8 + _nonceLength + _macLength;
  static Future<void> _secureKeyLock = Future<void>.value();

  final Directory? _baseDir;
  final OfflineBodyCacheKeyStore _keyStore;
  final AesGcm _cipher = AesGcm.with256bits();
  Future<Directory>? _directoryFuture;
  Future<Uint8List>? _keyFuture;

  Future<Directory> _dir() => _directoryFuture ??= _initializeDirectory();

  Future<Directory> _initializeDirectory() async {
    final base = _baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline_cache');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
      return dir;
    }

    try {
      await _removeLegacyPlaintext(dir);
      return dir;
    } catch (_) {
      // Do not leave old plaintext entries behind if secure storage cannot be
      // read while validating a possible encrypted entry. Cache bodies are
      // reconstructible, so deleting this cache directory's named entries is
      // safer than preserving data whose encryption state cannot be proven.
      await _deleteCacheNamedFiles(dir);
      _directoryFuture = null;
      rethrow;
    }
  }

  String _identity(String hostId, String path) => '$hostId:$path';

  String _key(String hostId, String path) => base64Url
      .encode(utf8.encode(_identity(hostId, path)))
      .replaceAll('=', '');

  File _fileFor(Directory dir, String hostId, String path) =>
      File('${dir.path}/${_key(hostId, path)}');

  Uint8List _associatedData(String hostId, String path) => Uint8List.fromList(
    utf8.encode('rfe:offline-body-cache:v1\u0000${_identity(hostId, path)}'),
  );

  /// Sums the on-disk size of encrypted cached files, across all hosts.
  Future<int> totalBytes() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } catch (_) {
        // Deleted mid-scan or otherwise unreadable — skip.
      }
    }
    return total;
  }

  Future<void> put(String hostId, String path, Uint8List bytes) async {
    final dir = await _dir();
    final key = await _getOrCreateKey();
    final nonce = _randomBytes(_nonceLength);
    final box = await _cipher.encrypt(
      bytes,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _associatedData(hostId, path),
    );
    final envelope = Uint8List.fromList(<int>[
      ..._magic,
      ...nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
    await _fileFor(dir, hostId, path).writeAsBytes(envelope, flush: true);
  }

  Future<Uint8List?> get(String hostId, String path) async {
    final file = _fileFor(await _dir(), hostId, path);
    if (!file.existsSync()) return null;

    final envelope = await file.readAsBytes();
    if (!_hasMagic(envelope)) {
      await file.delete();
      return null;
    }

    final key = await _readExistingKey();
    if (key == null) {
      await file.delete();
      return null;
    }

    try {
      return await _decrypt(envelope, key, hostId, path);
    } on Object {
      await file.delete();
      throw const OfflineBodyCacheIntegrityException();
    }
  }

  Future<bool> has(String hostId, String path) async {
    final file = _fileFor(await _dir(), hostId, path);
    if (!file.existsSync()) return false;
    final envelope = await file.readAsBytes();
    if (!_hasMagic(envelope)) {
      await file.delete();
      return false;
    }
    if (await _readExistingKey() == null) {
      await file.delete();
      return false;
    }
    return true;
  }

  Future<void> remove(String hostId, String path) async {
    final file = _fileFor(await _dir(), hostId, path);
    if (file.existsSync()) await file.delete();
  }

  /// Deletes all cached files belonging to [hostId] (call on host unpair).
  Future<void> evictHost(String hostId) async {
    final dir = await _dir();
    final prefix = '$hostId:';
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final identity = _decodeIdentity(entity.uri.pathSegments.last);
      if (identity != null && identity.startsWith(prefix)) {
        await entity.delete();
      }
    }
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256), growable: false),
    );
  }

  Future<Uint8List> _getOrCreateKey() {
    final current = _keyFuture;
    if (current != null) return current;
    final future = _loadOrCreateKey();
    _keyFuture = future;
    return future;
  }

  Future<Uint8List> _loadOrCreateKey() async {
    try {
      return await _withSecureKeyLock(() async {
        final existing = await _keyStore.readKey();
        if (existing != null) return _validateKey(existing);
        final key = _randomBytes(32);
        await _keyStore.writeKey(key);
        return Uint8List.fromList(key);
      });
    } catch (_) {
      _keyFuture = null;
      rethrow;
    }
  }

  Future<Uint8List?> _readExistingKey() async {
    final current = _keyFuture;
    if (current != null) return current;
    return _withSecureKeyLock(() async {
      final key = await _keyStore.readKey();
      return key == null ? null : _validateKey(key);
    });
  }

  static Future<T> _withSecureKeyLock<T>(Future<T> Function() action) async {
    final previous = _secureKeyLock;
    final release = Completer<void>();
    _secureKeyLock = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Uint8List _validateKey(Uint8List key) {
    if (key.length != 32) {
      throw StateError('Offline cache secure key must be 32 bytes');
    }
    return key;
  }

  bool _hasMagic(Uint8List bytes) {
    if (bytes.length < _headerLength) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  Future<Uint8List> _decrypt(
    Uint8List envelope,
    Uint8List key,
    String hostId,
    String path,
  ) async {
    if (!_hasMagic(envelope)) {
      throw const FormatException('Invalid cache envelope');
    }
    final nonce = envelope.sublist(_magic.length, _magic.length + _nonceLength);
    final macStart = _magic.length + _nonceLength;
    final mac = Mac(envelope.sublist(macStart, macStart + _macLength));
    final ciphertext = envelope.sublist(_headerLength);
    final cleartext = await _cipher.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: mac),
      secretKey: SecretKey(key),
      aad: _associatedData(hostId, path),
    );
    return Uint8List.fromList(cleartext);
  }

  /// Removes old plaintext files and any encrypted-looking entry that cannot
  /// be authenticated with the secure-store key. Only authenticated envelopes
  /// survive the upgrade sweep.
  Future<void> _removeLegacyPlaintext(Directory dir) async {
    Uint8List? key;
    var keyChecked = false;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final identity = _decodeIdentity(entity.uri.pathSegments.last);
      if (identity == null) continue;

      final bytes = await entity.readAsBytes();
      if (!_hasMagic(bytes)) {
        await entity.delete();
        continue;
      }

      if (!keyChecked) {
        key = await _readExistingKey();
        keyChecked = true;
      }
      if (key == null) {
        await entity.delete();
        continue;
      }

      final separator = identity.indexOf(':');
      if (separator < 0) {
        await entity.delete();
        continue;
      }
      final hostId = identity.substring(0, separator);
      final path = identity.substring(separator + 1);
      try {
        await _decrypt(bytes, key, hostId, path);
      } on Object {
        await entity.delete();
      }
    }
  }

  Future<void> _deleteCacheNamedFiles(Directory dir) async {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (_decodeIdentity(entity.uri.pathSegments.last) != null) {
        try {
          await entity.delete();
        } catch (_) {
          // Preserve the original secure-store error. The current operation
          // still fails closed and will not return any cached body.
        }
      }
    }
  }

  String? _decodeIdentity(String filename) {
    try {
      final padded = filename.padRight((filename.length + 3) ~/ 4 * 4, '=');
      final bytes = base64Url.decode(padded);
      final identity = utf8.decode(bytes);
      // Accept only the exact canonical filename format used by this cache.
      if (_key(
            identity.substring(0, identity.indexOf(':')),
            identity.substring(identity.indexOf(':') + 1),
          ) !=
          filename) {
        return null;
      }
      if (!identity.contains(':')) return null;
      return identity;
    } on Object {
      return null;
    }
  }
}
