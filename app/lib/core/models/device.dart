/// A paired device as reported by GET /v1/devices.
class Device {
  const Device({
    required this.id,
    required this.label,
    required this.created,
    required this.lastSeen,
    required this.revoked,
    required this.current,
    this.viaLogin = false,
    this.lastAddress = '',
    this.lastVersion = '',
    this.jailRoot = '',
    this.viewApps,
    this.launchApps,
  });

  final String id;
  final String label;
  final DateTime created;
  final DateTime lastSeen;
  final bool revoked;
  final bool current;

  /// True when this device authenticated with the account password. This
  /// field is present in full admin device listings only.
  final bool viaLogin;

  /// The network address (host:port or IP) the device last connected from.
  /// Empty if unknown (e.g. not seen since the agent was upgraded).
  final String lastAddress;

  /// The app version (`versionName+buildNumber`) the device last connected
  /// with, e.g. `1.10.0+18`. Empty if unknown.
  final String lastVersion;

  /// Absolute path this device is restricted to, if any. Empty = full
  /// access (within the agent's configured roots).
  final String jailRoot;

  /// Whether this device may see the host's installed-app catalog. Null when
  /// the connected agent predates per-device app capabilities.
  final bool? viewApps;

  /// Whether this device may launch approved apps. Null when the connected
  /// agent predates per-device app capabilities.
  final bool? launchApps;

  /// Older agents omit both app capability fields; hide their controls rather
  /// than presenting an inaccurate default-off state.
  bool get hasAppCapabilities => viewApps != null && launchApps != null;

  Device copyWith({bool? viewApps, bool? launchApps}) => Device(
    id: id,
    label: label,
    created: created,
    lastSeen: lastSeen,
    revoked: revoked,
    current: current,
    viaLogin: viaLogin,
    lastAddress: lastAddress,
    lastVersion: lastVersion,
    jailRoot: jailRoot,
    viewApps: viewApps ?? this.viewApps,
    launchApps: launchApps ?? this.launchApps,
  );

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    created: DateTime.fromMillisecondsSinceEpoch(
      ((json['created'] as num?)?.toInt() ?? 0) * 1000,
    ),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(
      ((json['lastSeen'] as num?)?.toInt() ?? 0) * 1000,
    ),
    revoked: json['revoked'] as bool? ?? false,
    current: json['current'] as bool? ?? false,
    viaLogin: json['viaLogin'] as bool? ?? false,
    lastAddress: json['lastAddress'] as String? ?? '',
    lastVersion: json['lastVersion'] as String? ?? '',
    jailRoot: json['jailRoot'] as String? ?? '',
    viewApps: json['viewApps'] as bool?,
    launchApps: json['launchApps'] as bool?,
  );
}
