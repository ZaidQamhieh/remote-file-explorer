import 'package:shared_preferences/shared_preferences.dart';

/// User configuration for photo backup, persisted in SharedPreferences under
/// `rfe_photo_backup_*` keys (so it's covered by the app's config backup/restore).
class PhotoBackupPrefs {
  const PhotoBackupPrefs({
    this.enabled = false,
    this.hostId,
    this.destRoot,
    this.wifiOnly = true,
    this.chargingOnly = false,
  });

  /// Master on/off. When off, "Back up now" still works manually but nothing
  /// is implied to run on its own.
  final bool enabled;

  /// Target host id (a paired PC) and the destination root folder on it.
  final String? hostId;
  final String? destRoot;

  /// Only back up while on Wi-Fi / while charging.
  final bool wifiOnly;
  final bool chargingOnly;

  bool get isConfigured =>
      hostId != null &&
      hostId!.isNotEmpty &&
      destRoot != null &&
      destRoot!.isNotEmpty;

  PhotoBackupPrefs copyWith({
    bool? enabled,
    String? hostId,
    String? destRoot,
    bool? wifiOnly,
    bool? chargingOnly,
  }) => PhotoBackupPrefs(
    enabled: enabled ?? this.enabled,
    hostId: hostId ?? this.hostId,
    destRoot: destRoot ?? this.destRoot,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    chargingOnly: chargingOnly ?? this.chargingOnly,
  );
}

/// Loads/saves [PhotoBackupPrefs] and the set of already-backed-up photo asset
/// ids (the dedupe record) in SharedPreferences.
class PhotoBackupStore {
  PhotoBackupStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kEnabled = 'rfe_photo_backup_enabled';
  static const _kHostId = 'rfe_photo_backup_host';
  static const _kDestRoot = 'rfe_photo_backup_dest';
  static const _kWifiOnly = 'rfe_photo_backup_wifi_only';
  static const _kChargingOnly = 'rfe_photo_backup_charging_only';
  static const _kDone = 'rfe_photo_backup_done';

  static Future<PhotoBackupStore> open() async =>
      PhotoBackupStore(await SharedPreferences.getInstance());

  PhotoBackupPrefs load() => PhotoBackupPrefs(
    enabled: _prefs.getBool(_kEnabled) ?? false,
    hostId: _prefs.getString(_kHostId),
    destRoot: _prefs.getString(_kDestRoot),
    wifiOnly: _prefs.getBool(_kWifiOnly) ?? true,
    chargingOnly: _prefs.getBool(_kChargingOnly) ?? false,
  );

  Future<void> save(PhotoBackupPrefs p) async {
    await _prefs.setBool(_kEnabled, p.enabled);
    await _prefs.setBool(_kWifiOnly, p.wifiOnly);
    await _prefs.setBool(_kChargingOnly, p.chargingOnly);
    if (p.hostId != null) await _prefs.setString(_kHostId, p.hostId!);
    if (p.destRoot != null) await _prefs.setString(_kDestRoot, p.destRoot!);
  }

  /// The set of photo asset ids already backed up (the dedupe record).
  Set<String> doneIds() => (_prefs.getStringList(_kDone) ?? const []).toSet();

  Future<void> markDone(Iterable<String> ids) async {
    final set = doneIds()..addAll(ids);
    await _prefs.setStringList(_kDone, set.toList());
  }

  /// Forgets the backed-up record so the next run re-backs-up everything
  /// (e.g. after switching destination host/folder).
  Future<void> resetDone() async => _prefs.remove(_kDone);
}
