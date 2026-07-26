import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_backup.dart';

/// Small injectable abstraction over [FlutterSecureStorage] so
/// [BackupService] is unit-testable without platform channels.
abstract class SecureKv {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// [FlutterSecureStorage]-backed implementation of [SecureKv].
class FlutterSecureKv implements SecureKv {
  const FlutterSecureKv([this._secure = const FlutterSecureStorage()]);

  final FlutterSecureStorage _secure;

  @override
  Future<Map<String, String>> readAll() => _secure.readAll();

  @override
  Future<void> write(String key, String value) =>
      _secure.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _secure.delete(key: key);

  @override
  Future<void> deleteAll() => _secure.deleteAll();
}

/// Gathers the app's full persisted state into an encrypted backup, and
/// restores it (replacing existing state) from one.
///
/// Storage surface (see `docs/architecture.md` / host_store.dart /
/// settings_controller.dart):
///  - **SharedPreferences**: `rfe_*` (host list, favorites, recent searches,
///    last-seen), `app.*` (two-tier app defaults incl. visibility/theme),
///    `host.<id>.*` (per-device overrides), plus any `settings.*` migration
///    bookkeeping keys.
///  - **FlutterSecureStorage**: only `rfe_fp_<id>` certificate fingerprints.
/// Bearer tokens and the permanent device identity are deliberately excluded;
/// restored hosts must be paired again.
class BackupService {
  BackupService(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final SecureKv _secure;

  /// Prefixes of SharedPreferences keys this app owns. On import, every
  /// existing key matching one of these is removed before the backup's keys
  /// are written back, so the restored snapshot is exact (no orphan hosts or
  /// stale settings left over from the device being restored onto).
  static const _ownedPrefixes = ['rfe_', 'app.', 'host.', 'settings.'];

  static bool _isOwnedPrefKey(String key) =>
      _ownedPrefixes.any((prefix) => key.startsWith(prefix));

  static bool _isManagedSecureKey(String key) =>
      key.startsWith('rfe_token_') || key.startsWith('rfe_fp_');

  static bool _isExportableSecureKey(String key) => key.startsWith('rfe_fp_');

  /// Gathers all app-owned SharedPreferences entries + all secure-storage
  /// entries, builds a [BackupPayload], and returns the encrypted envelope
  /// JSON (as produced by [encodeBackup]).
  Future<String> exportToEnvelope(String passphrase) async {
    if (passphrase.length < kBackupMinimumPassphraseLength) {
      throw const BackupException('Passphrase must be at least 12 characters.');
    }
    final prefsMap = <String, PrefEntry>{};
    for (final key in _prefs.getKeys()) {
      if (!_isOwnedPrefKey(key)) continue;
      final value = _prefs.get(key);
      if (value == null) continue;
      try {
        prefsMap[key] = PrefEntry.fromValue(value);
      } on BackupException {
        // Skip values of types this format doesn't model (shouldn't happen
        // in practice — SharedPreferences only stores bool/int/double/String/
        // List<String>).
      }
    }

    final secureMap = Map<String, String>.fromEntries(
      (await _secure.readAll()).entries.where(
        (entry) => _isExportableSecureKey(entry.key),
      ),
    );

    final payload = BackupPayload.create(prefs: prefsMap, secure: secureMap);
    return encodeBackup(payload, passphrase);
  }

  /// Decodes [envelopeJson] with [passphrase] and **replaces** app state:
  /// removes every existing app-owned SharedPreferences key (see
  /// [_ownedPrefixes]) and host token/fingerprint entries, then writes the
  /// portable subset. Device identity and unrelated secure keys are preserved.
  ///
  /// Throws [BackupException] (from [decodeBackup]) on a wrong passphrase or
  /// corrupted/tampered file — in that case no existing state is touched.
  Future<void> importFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    final payload = await decodeBackup(envelopeJson, passphrase);

    if (payload.version != 1 ||
        payload.prefs.keys.any((key) => !_isOwnedPrefKey(key)) ||
        payload.secure.keys.any((key) => !_isExportableSecureKey(key))) {
      throw const BackupException('This backup contains unsupported data.');
    }

    final previousPrefs = _snapshotPrefs();
    final previousSecure = Map<String, String>.fromEntries(
      (await _secure.readAll()).entries.where(
        (entry) => _isManagedSecureKey(entry.key),
      ),
    );

    try {
      await _replaceState(payload.prefs, payload.secure);
    } catch (_) {
      try {
        await _replaceState(previousPrefs, previousSecure);
      } catch (_) {
        throw const BackupException(
          'Restore failed and the previous configuration could not be fully recovered.',
        );
      }
      throw const BackupException(
        'Restore failed. The previous configuration was restored.',
      );
    }
  }

  Map<String, PrefEntry> _snapshotPrefs() {
    final snapshot = <String, PrefEntry>{};
    for (final key in _prefs.getKeys()) {
      if (!_isOwnedPrefKey(key)) continue;
      final value = _prefs.get(key);
      if (value != null) snapshot[key] = PrefEntry.fromValue(value);
    }
    return snapshot;
  }

  Future<void> _replaceState(
    Map<String, PrefEntry> prefs,
    Map<String, String> secure,
  ) async {
    for (final key in _prefs.getKeys().toList()) {
      if (_isOwnedPrefKey(key) && !await _prefs.remove(key)) {
        throw StateError('failed to remove preference');
      }
    }
    for (final key in (await _secure.readAll()).keys) {
      if (_isManagedSecureKey(key)) await _secure.delete(key);
    }

    for (final entry in prefs.entries) {
      final pref = entry.value;
      late final bool stored;
      switch (pref.type) {
        case PrefType.boolType:
          stored = await _prefs.setBool(entry.key, pref.value as bool);
        case PrefType.intType:
          stored = await _prefs.setInt(entry.key, pref.value as int);
        case PrefType.doubleType:
          stored = await _prefs.setDouble(entry.key, pref.value as double);
        case PrefType.stringType:
          stored = await _prefs.setString(entry.key, pref.value as String);
        case PrefType.stringListType:
          stored = await _prefs.setStringList(
            entry.key,
            List<String>.from(pref.value as List<String>),
          );
      }
      if (!stored) {
        throw StateError('failed to write preference');
      }
    }

    for (final entry in secure.entries) {
      if (_isManagedSecureKey(entry.key)) {
        await _secure.write(entry.key, entry.value);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return BackupService(prefs, const FlutterSecureKv());
});
