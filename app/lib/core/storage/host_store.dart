import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/host.dart';

/// Keys used in SharedPreferences and FlutterSecureStorage.
const _kHostListKey = 'rfe_hosts_v1';
String _tokenKey(String hostId) => 'rfe_token_$hostId';
String _fpKey(String hostId) => 'rfe_fp_$hostId';

/// Persists [Host] metadata (non-secret) in [SharedPreferences] and
/// sensitive fields (device token, cert fingerprint) in [FlutterSecureStorage].
class HostStore {
  HostStore._(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static Future<HostStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    return HostStore._(prefs, secure);
  }

  // ---------------------------------------------------------------------------
  // Host list (non-sensitive, stored in SharedPreferences as JSON)
  // ---------------------------------------------------------------------------

  List<Host> listHosts() {
    final raw = _prefs.getStringList(_kHostListKey) ?? [];
    return raw
        .map((s) => Host.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addHost(Host host) async {
    final hosts = listHosts()..removeWhere((h) => h.id == host.id);
    hosts.add(host);
    await _saveHosts(hosts);
  }

  Future<void> removeHost(String hostId) async {
    final hosts = listHosts()..removeWhere((h) => h.id == hostId);
    await _saveHosts(hosts);
    // Clean up secrets too
    await _secure.delete(key: _tokenKey(hostId));
    await _secure.delete(key: _fpKey(hostId));
  }

  Future<void> _saveHosts(List<Host> hosts) async {
    await _prefs.setStringList(
      _kHostListKey,
      hosts.map((h) => jsonEncode(h.toJson())).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Device token (sensitive)
  // ---------------------------------------------------------------------------

  Future<String?> getToken(String hostId) =>
      _secure.read(key: _tokenKey(hostId));

  Future<void> setToken(String hostId, String token) =>
      _secure.write(key: _tokenKey(hostId), value: token);

  // ---------------------------------------------------------------------------
  // Cert fingerprint (sensitive; mirrors host.certFingerprint for quick lookup)
  // ---------------------------------------------------------------------------

  Future<String?> getFingerprint(String hostId) =>
      _secure.read(key: _fpKey(hostId));

  Future<void> setFingerprint(String hostId, String fingerprint) =>
      _secure.write(key: _fpKey(hostId), value: fingerprint);
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final hostStoreProvider = FutureProvider<HostStore>((ref) => HostStore.create());
