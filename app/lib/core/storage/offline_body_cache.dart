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

  static const _keyName = 'rfe.offline_body_cache.chacha20_poly1305_key.v2';
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

/// Persists ChaCha20-Poly1305 encrypted file bodies for offline access.
///
/// Body files remain in `<app-support>/offline_cache`, with the same
/// host/path-derived name used by the previous plaintext implementation. Each
/// file contains a format marker, a 12-byte nonce, a 16-byte authentication
/// tag, and ciphertext. The 256-bit key is generated once and stored only in
/// platform secure storage; it is never written beside the cache files. Bodies
/// are encrypted in bounded chunks to keep peak memory close to the caller's
/// input size rather than allocating multiple body-sized copies.
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
    0x02,
    0x0a,
  ];
  static const int _chunkSize = 64 * 1024;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _headerLength = 8 + _nonceLength + _macLength;
  static Future<void> _secureKeyLock = Future<void>.value();
  static final Map<String, Future<void>> _fileLocks = <String, Future<void>>{};

  final Directory? _baseDir;
  final OfflineBodyCacheKeyStore _keyStore;
  final StreamingCipher _cipher = Chacha20.poly1305Aead();
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
      await _removeOrphanedTempFiles(dir);
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
    utf8.encode('rfe:offline-body-cache:v2\u0000${_identity(hostId, path)}'),
  );

  /// Sums all files stored by the cache, including an in-progress encrypted
  /// replacement, so concurrent callers retain the same conservative budget.
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
    final file = _fileFor(dir, hostId, path);
    return _withFileLock(file.path, () async {
      await _putFile(file, key, hostId, path, bytes);
    });
  }

  Future<void> _putFile(
    File file,
    Uint8List key,
    String hostId,
    String path,
    Uint8List bytes,
  ) async {
    final temp = File(
      '${file.path}.tmp-${base64UrlEncode(_randomBytes(12)).replaceAll('=', '')}',
    );
    await _withFileLock(temp.path, () async {
      await _writeTempAndReplace(file, temp, key, hostId, path, bytes);
    });
  }

  Future<void> _writeTempAndReplace(
    File file,
    File temp,
    Uint8List key,
    String hostId,
    String path,
    Uint8List bytes,
  ) async {
    RandomAccessFile? handle;
    try {
      await temp.create(exclusive: true);
      handle = await temp.open(mode: FileMode.write);
      final nonce = _cipher.newNonce();
      await handle.writeFrom(<int>[
        ..._magic,
        ...nonce,
        ...List<int>.filled(_macLength, 0),
      ]);

      Mac? mac;
      final encryptedChunks = _cipher.encryptStream(
        _chunks(bytes),
        secretKey: SecretKey(key),
        nonce: nonce,
        aad: _associatedData(hostId, path),
        onMac: (value) => mac = value,
      );
      await for (final chunk in encryptedChunks) {
        await handle.writeFrom(chunk);
      }
      final finalMac = mac;
      if (finalMac == null || finalMac.bytes.length != _macLength) {
        throw StateError(
          'Offline cache encryption did not produce a valid MAC',
        );
      }
      await handle.setPosition(_magic.length + _nonceLength);
      await handle.writeFrom(finalMac.bytes);
      await handle.flush();
      await handle.close();
      handle = null;

      // The completed encrypted file is on the same filesystem as the target,
      // so readers see either the old envelope or the complete replacement.
      await temp.rename(file.path);
    } catch (_) {
      if (handle != null) await handle.close();
      if (temp.existsSync()) await temp.delete();
      rethrow;
    }
  }

  Future<Uint8List?> get(String hostId, String path) async {
    final file = _fileFor(await _dir(), hostId, path);
    return _withFileLock(file.path, () async {
      if (!file.existsSync()) return null;

      final header = await _readHeader(file);
      if (!_hasMagic(header)) {
        await file.delete();
        return null;
      }

      final key = await _readExistingKey();
      if (key == null) {
        await file.delete();
        return null;
      }

      try {
        final body = await _decryptFile(file, key, hostId, path, collect: true);
        return body;
      } on Object {
        await file.delete();
        throw const OfflineBodyCacheIntegrityException();
      }
    });
  }

  /// Reports whether an encrypted cache envelope exists and its secure-store
  /// key is available. This is intentionally an inexpensive, existence-only
  /// check: [get] performs full authenticated decryption and removes tampered
  /// entries before returning an integrity error.
  Future<bool> has(String hostId, String path) async {
    final file = _fileFor(await _dir(), hostId, path);
    return _withFileLock(file.path, () async {
      if (!file.existsSync()) return false;
      final header = await _readHeader(file);
      if (!_hasMagic(header)) {
        await file.delete();
        return false;
      }
      if (await _readExistingKey() == null) {
        await file.delete();
        return false;
      }
      return true;
    });
  }

  Future<void> remove(String hostId, String path) async {
    final file = _fileFor(await _dir(), hostId, path);
    await _withFileLock(file.path, () async {
      if (file.existsSync()) await file.delete();
    });
  }

  /// Deletes all cached files belonging to [hostId] (call on host unpair).
  Future<void> evictHost(String hostId) async {
    final dir = await _dir();
    final prefix = '$hostId:';
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final identity = _decodeIdentity(entity.uri.pathSegments.last);
      if (identity != null && identity.startsWith(prefix)) {
        await _withFileLock(entity.path, () async {
          if (entity.existsSync()) await entity.delete();
        });
      }
    }
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256), growable: false),
    );
  }

  Stream<Uint8List> _chunks(Uint8List bytes) async* {
    for (var offset = 0; offset < bytes.length; offset += _chunkSize) {
      final end = min(offset + _chunkSize, bytes.length);
      yield Uint8List.sublistView(bytes, offset, end);
    }
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

  static Future<T> _withFileLock<T>(
    String path,
    Future<T> Function() action,
  ) async {
    final previous = _fileLocks[path] ?? Future<void>.value();
    final release = Completer<void>();
    final current = release.future;
    _fileLocks[path] = current;
    await previous;
    try {
      return await action();
    } finally {
      if (identical(_fileLocks[path], current)) _fileLocks.remove(path);
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

  Future<Uint8List> _readHeader(File file) async {
    final handle = await file.open(mode: FileMode.read);
    try {
      return await handle.read(_headerLength);
    } finally {
      await handle.close();
    }
  }

  Stream<Uint8List> _readCiphertextChunks(File file) async* {
    final handle = await file.open(mode: FileMode.read);
    try {
      await handle.setPosition(_headerLength);
      while (true) {
        final chunk = await handle.read(_chunkSize);
        if (chunk.isEmpty) return;
        yield chunk;
      }
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List?> _decryptFile(
    File file,
    Uint8List key,
    String hostId,
    String path, {
    required bool collect,
  }) async {
    final header = await _readHeader(file);
    if (!_hasMagic(header)) {
      throw const FormatException('Invalid cache envelope');
    }
    final nonce = header.sublist(_magic.length, _magic.length + _nonceLength);
    final macStart = _magic.length + _nonceLength;
    final mac = Mac(header.sublist(macStart, macStart + _macLength));
    final fileLength = await file.length();
    if (fileLength < _headerLength) {
      throw const FormatException('Truncated cache envelope');
    }
    final bodyLength = fileLength - _headerLength;
    final output = collect ? Uint8List(bodyLength) : null;
    var outputOffset = 0;
    final clearChunks = _cipher.decryptStream(
      _readCiphertextChunks(file),
      secretKey: SecretKey(key),
      nonce: nonce,
      mac: Future<Mac>.value(mac),
      aad: _associatedData(hostId, path),
    );
    try {
      await for (final chunk in clearChunks) {
        final result = output;
        if (result != null) {
          if (outputOffset + chunk.length > result.length) {
            throw const FormatException('Invalid cache ciphertext length');
          }
          result.setRange(outputOffset, outputOffset + chunk.length, chunk);
          outputOffset += chunk.length;
        }
        if (chunk is Uint8List) chunk.fillRange(0, chunk.length, 0);
      }
      if (output != null && outputOffset != output.length) {
        throw const FormatException('Invalid cache plaintext length');
      }
      return output;
    } on Object {
      output?.fillRange(0, output.length, 0);
      rethrow;
    }
  }

  /// Removes old plaintext files and any current-format envelope that cannot
  /// be authenticated with the secure-store key. Only authenticated v2
  /// envelopes survive the upgrade sweep; older cache formats are disposable.
  Future<void> _removeLegacyPlaintext(Directory dir) async {
    Uint8List? key;
    var keyChecked = false;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final identity = _decodeIdentity(entity.uri.pathSegments.last);
      if (identity == null) continue;
      await _withFileLock(entity.path, () async {
        if (!entity.existsSync()) return;
        final header = await _readHeader(entity);
        if (!_hasMagic(header)) {
          await entity.delete();
          return;
        }

        if (!keyChecked) {
          key = await _readExistingKey();
          keyChecked = true;
        }
        final validationKey = key;
        if (validationKey == null) {
          await entity.delete();
          return;
        }

        final separator = identity.indexOf(':');
        if (separator < 0) {
          await entity.delete();
          return;
        }
        final hostId = identity.substring(0, separator);
        final path = identity.substring(separator + 1);
        try {
          await _decryptFile(
            entity,
            validationKey,
            hostId,
            path,
            collect: false,
          );
        } on Object {
          await entity.delete();
        }
      });
    }
  }

  Future<void> _deleteCacheNamedFiles(Directory dir) async {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (_decodeIdentity(entity.uri.pathSegments.last) != null) {
        await _withFileLock(entity.path, () async {
          try {
            if (entity.existsSync()) await entity.delete();
          } catch (_) {
            // Preserve the original secure-store error. The current operation
            // still fails closed and will not return any cached body.
          }
        });
      }
    }
  }

  Future<void> _removeOrphanedTempFiles(Directory dir) async {
    final suffixPattern = RegExp(r'^[A-Za-z0-9_-]{16}$');
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final filename = entity.uri.pathSegments.last;
      final marker = filename.indexOf('.tmp-');
      if (marker <= 0 ||
          filename.indexOf('.tmp-', marker + 5) >= 0 ||
          _decodeIdentity(filename.substring(0, marker)) == null ||
          !suffixPattern.hasMatch(filename.substring(marker + 5))) {
        continue;
      }
      await _withFileLock(entity.path, () async {
        if (entity.existsSync()) await entity.delete();
      });
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
