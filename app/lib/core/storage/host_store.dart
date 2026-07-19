import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/host.dart';
import 'listing_cache.dart';
import 'offline_body_cache.dart';

/// Keys used in SharedPreferences and FlutterSecureStorage.
const _kHostListKey = 'rfe_hosts_v1';
String _tokenKey(String hostId) => 'rfe_token_$hostId';
String _fpKey(String hostId) => 'rfe_fp_$hostId';
String _lastSeenKey(String hostId) => 'rfe_last_seen_$hostId';

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
    final hosts = <Host>[];
    for (final s in raw) {
      try {
        hosts.add(Host.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // One corrupt/legacy entry must not brick the whole host list — the
        // app becomes unusable if every host disappears behind a single
        // bad record (PR-54).
      }
    }
    return hosts;
  }

  Future<void> addHost(Host host) async {
    final hosts = listHosts()..removeWhere((h) => h.id == host.id);
    hosts.add(host);
    await _saveHosts(hosts);
  }

  /// Commits a freshly-paired [host] plus its [token] and (if TOFU pinned)
  /// [fingerprint] as one unit (PR-37).
  ///
  /// Every pairing flow (QR/manual/login/register) used to call
  /// [addHost]/[setToken]/[setFingerprint] as three separate awaits; a
  /// failure between them (e.g. secure-storage write failure) left a host
  /// visible in the list with no token — unusable — or no pinned
  /// fingerprint — TOFU silently lost. Delegates to [commitPairingSteps] so
  /// the rollback ordering is unit-testable without a real secure storage.
  Future<void> commitPairing(
    Host host, {
    required String token,
    String? fingerprint,
  }) => commitPairingSteps(
    addHost: () => addHost(host),
    setToken: () => setToken(host.id, token),
    setFingerprint:
        fingerprint == null ? null : () => setFingerprint(host.id, fingerprint),
    removeHost: () => removeHost(host.id),
  );

  /// Moves [hostId] to the front of the list — used to promote whichever host
  /// was most recently opened to the "focused" hero slot at the top of the
  /// Servers screen.
  Future<void> touchHost(String hostId) async {
    final hosts = listHosts();
    final index = hosts.indexWhere((h) => h.id == hostId);
    if (index <= 0) return;
    hosts.insert(0, hosts.removeAt(index));
    await _saveHosts(hosts);
  }

  Future<void> removeHost(String hostId) async {
    final hosts = listHosts()..removeWhere((h) => h.id == hostId);
    await _saveHosts(hosts);
    // Clean up secrets too
    await _secure.delete(key: _tokenKey(hostId));
    await _secure.delete(key: _fpKey(hostId));
    await _prefs.remove(_lastSeenKey(hostId));
    // A forgotten host shouldn't keep serving its cached listings/files.
    await ListingCache().evictHost(hostId);
    await OfflineBodyCache().evictHost(hostId);
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

  // ---------------------------------------------------------------------------
  // Last-seen timestamp (non-sensitive, used for the "last seen" label on
  // offline hosts)
  // ---------------------------------------------------------------------------

  /// The last time a successful `/health` ping was recorded for [hostId], or
  /// `null` if the host has never been seen online.
  DateTime? getLastSeen(String hostId) {
    final millis = _prefs.getInt(_lastSeenKey(hostId));
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Records [at] (defaults to now) as the last time [hostId] answered
  /// `/health` successfully.
  Future<void> setLastSeen(String hostId, [DateTime? at]) => _prefs.setInt(
    _lastSeenKey(hostId),
    (at ?? DateTime.now()).millisecondsSinceEpoch,
  );
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final hostStoreProvider = FutureProvider<HostStore>(
  (ref) => HostStore.create(),
);

/// Runs [addHost] then [setToken] and (if given) [setFingerprint]; if either
/// of the latter two throws, runs [removeHost] before rethrowing (PR-37).
///
/// Extracted as a pure function of its side-effecting steps — rather than
/// inlined in [HostStore.commitPairing] — so the rollback ordering is
/// unit-testable with fakes, without needing a real `FlutterSecureStorage`.
Future<void> commitPairingSteps({
  required Future<void> Function() addHost,
  required Future<void> Function() setToken,
  required Future<void> Function()? setFingerprint,
  required Future<void> Function() removeHost,
}) async {
  await addHost();
  try {
    await setToken();
    if (setFingerprint != null) await setFingerprint();
  } catch (_) {
    await removeHost();
    rethrow;
  }
}
