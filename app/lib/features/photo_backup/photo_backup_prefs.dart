import 'package:shared_preferences/shared_preferences.dart';

/// User configuration for photo backup, persisted in SharedPreferences under
/// `rfe_photo_backup_*` keys (so it's covered by the app's config backup/restore).
class PhotoBackupPrefs {
  const PhotoBackupPrefs({
    this.enabled = false,
    this.hostId,
    this.deviceName,
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.albumIds = const [],
  });

  /// Master on/off. When off nothing backs up — the manual "Back up now"
  /// action and all other options are disabled too.
  final bool enabled;

  /// Target host id (a paired PC). The destination *folder* is decided by
  /// that PC (web companion Settings → Photo backup destination), fetched
  /// live at backup time — never a phone-side setting.
  final String? hostId;

  /// User-editable label for this phone's destRoot subfolder (e.g. "Zaid's
  /// Phone"), so backups from several phones onto one shared destRoot stay
  /// tellable apart. Null/empty falls back to a short device-id.
  final String? deviceName;

  /// Which photo albums to back up, by album id. Empty means "all photos"
  /// (the whole library) — the backward-compatible default.
  final List<String> albumIds;

  /// Only back up while on Wi-Fi / while charging.
  final bool wifiOnly;
  final bool chargingOnly;

  bool get isConfigured => hostId != null && hostId!.isNotEmpty;

  PhotoBackupPrefs copyWith({
    bool? enabled,
    String? hostId,
    String? deviceName,
    bool? wifiOnly,
    bool? chargingOnly,
    List<String>? albumIds,
  }) => PhotoBackupPrefs(
    enabled: enabled ?? this.enabled,
    hostId: hostId ?? this.hostId,
    deviceName: deviceName ?? this.deviceName,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    chargingOnly: chargingOnly ?? this.chargingOnly,
    albumIds: albumIds ?? this.albumIds,
  );
}

/// Loads/saves [PhotoBackupPrefs] and the set of already-backed-up photo asset
/// ids (the dedupe record) in SharedPreferences.
class PhotoBackupStore {
  PhotoBackupStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kEnabled = 'rfe_photo_backup_enabled';
  static const _kHostId = 'rfe_photo_backup_host';
  static const _kDeviceName = 'rfe_photo_backup_device_name';
  static const _kWifiOnly = 'rfe_photo_backup_wifi_only';
  static const _kChargingOnly = 'rfe_photo_backup_charging_only';
  static const _kAlbums = 'rfe_photo_backup_albums';
  static const _kDone = 'rfe_photo_backup_done';

  static Future<PhotoBackupStore> open() async =>
      PhotoBackupStore(await SharedPreferences.getInstance());

  PhotoBackupPrefs load() => PhotoBackupPrefs(
    enabled: _prefs.getBool(_kEnabled) ?? false,
    hostId: _prefs.getString(_kHostId),
    deviceName: _prefs.getString(_kDeviceName),
    wifiOnly: _prefs.getBool(_kWifiOnly) ?? true,
    chargingOnly: _prefs.getBool(_kChargingOnly) ?? false,
    albumIds: _prefs.getStringList(_kAlbums) ?? const [],
  );

  Future<void> save(PhotoBackupPrefs p) async {
    await _prefs.setBool(_kEnabled, p.enabled);
    await _prefs.setBool(_kWifiOnly, p.wifiOnly);
    await _prefs.setBool(_kChargingOnly, p.chargingOnly);
    await _prefs.setStringList(_kAlbums, p.albumIds);
    if (p.hostId != null) await _prefs.setString(_kHostId, p.hostId!);
    if (p.deviceName != null) {
      await _prefs.setString(_kDeviceName, p.deviceName!);
    }
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
