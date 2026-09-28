/// An app entry exposed by a paired host's supported app catalog.
///
/// [id] is an opaque server-issued identifier. It must never be treated as a
/// filesystem path or command line; launch requests send only this value.
class HostApp {
  const HostApp({
    required this.id,
    required this.name,
    required this.launchable,
    this.description,
    this.icon,
  });

  final String id;
  final String name;

  /// Whether the host has a supported native action for starting this entry.
  /// The server checks this again against its current catalog when launching.
  final bool launchable;

  /// Optional plain-text metadata. UI surfaces should avoid exposing paths or
  /// command details from the host.
  final String? description;

  /// Optional safe icon key, interpreted through a client-side allowlist.
  final String? icon;

  factory HostApp.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      throw const FormatException('Invalid host app catalog entry.');
    }
    return HostApp(
      id: id,
      name: name,
      // Older agents returned only entries their native adapter could launch.
      launchable: json['launchable'] as bool? ?? true,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
    );
  }
}

/// The installed, approved app catalog for one host.
class HostAppCatalog {
  const HostAppCatalog({
    required this.platform,
    required this.apps,
    required this.launchAllowed,
  });

  final String platform;
  final List<HostApp> apps;

  /// Whether the current paired device is allowed to start catalog apps.
  /// Missing values from older agents default to false for safe UI behavior.
  final bool launchAllowed;

  factory HostAppCatalog.fromJson(Map<String, dynamic> json) {
    final rawApps = json['apps'];
    if (rawApps is! List) {
      throw const FormatException('Invalid host app catalog response.');
    }
    return HostAppCatalog(
      platform: json['platform'] as String? ?? '',
      launchAllowed: json['launchAllowed'] as bool? ?? false,
      apps: rawApps
          .map((entry) => HostApp.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
