import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_backup.dart';

/// Small injectable abstraction over [FlutterSecureStorage] so
/// [BackupService] is unit-testable without platform channels.
abstract class SecureKv {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
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
///  - **FlutterSecureStorage**: `rfe_token_<id>` (device bearer tokens),
///    `rfe_fp_<id>` (cert fingerprints), and `rfe_device_identity_{private,
///    public}_v1` (this device's pairing identity — see [_neverBackedUp]:
///    the private half is excluded, not exported like the rest).
///
/// The gather step is generic — it exports every *other* key in both
/// stores — so new state added in future waves is covered automatically.
class BackupService {
  BackupService(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final SecureKv _secure;

  /// Prefixes of SharedPreferences keys this app owns. On import, every
  /// existing key matching one of these is removed before the backup's keys
  /// are written back, so the restored snapshot is exact (no orphan hosts or
  /// stale settings left over from the device being restored onto).
  static const _ownedPrefixes = ['rfe_', 'app.', 'host.'];

  /// Secure-storage keys that never round-trip through a backup. The
  /// private device identity key (`device_identity.dart`) is meant to stay
  /// permanently device-bound — a backup/passphrase becomes a portable
  /// clone of that identity otherwise, letting it be replayed onto a
  /// different device (PR-17). Excluded on both export (new backups never
  /// contain it) and import (an old backup taken before this fix, or a
  /// hand-crafted one, can't smuggle a foreign identity in either).
  static const _neverBackedUp = {'rfe_device_identity_private_v1'};

  /// Gathers all app-owned SharedPreferences entries + all secure-storage
  /// entries, builds a [BackupPayload], and returns the encrypted envelope
  /// JSON (as produced by [encodeBackup]).
  Future<String> exportToEnvelope(String passphrase) async {
    final prefsMap = <String, PrefEntry>{};
    for (final key in _prefs.getKeys()) {
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

    final secureMap = Map<String, String>.from(await _secure.readAll())
      ..removeWhere((key, _) => _neverBackedUp.contains(key));

    final payload = BackupPayload.create(prefs: prefsMap, secure: secureMap);
    return encodeBackup(payload, passphrase);
  }

  /// Decodes [envelopeJson] with [passphrase] and **replaces** app state:
  /// removes every existing app-owned SharedPreferences key (see
  /// [_ownedPrefixes]) and all secure-storage entries, then writes every key
  /// from the decoded payload with its original type.
  ///
  /// Throws [BackupException] (from [decodeBackup]) on a wrong passphrase or
  /// corrupted/tampered file — in that case no existing state is touched.
  Future<void> importFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    final payload = await decodeBackup(envelopeJson, passphrase);

    // Clear existing app-owned state first (replace semantics).
    for (final key in _prefs.getKeys().toList()) {
      if (_ownedPrefixes.any((p) => key.startsWith(p))) {
        await _prefs.remove(key);
      }
    }
    await _secure.deleteAll();

    // Write back every key from the backup with its original type.
    for (final entry in payload.prefs.entries) {
      final pref = entry.value;
      switch (pref.type) {
        case PrefType.boolType:
          await _prefs.setBool(entry.key, pref.value as bool);
        case PrefType.intType:
          await _prefs.setInt(entry.key, pref.value as int);
        case PrefType.doubleType:
          await _prefs.setDouble(entry.key, pref.value as double);
        case PrefType.stringType:
          await _prefs.setString(entry.key, pref.value as String);
        case PrefType.stringListType:
          await _prefs.setStringList(entry.key, pref.value as List<String>);
      }
    }

    for (final entry in payload.secure.entries) {
      if (_neverBackedUp.contains(entry.key)) continue;
      await _secure.write(entry.key, entry.value);
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
