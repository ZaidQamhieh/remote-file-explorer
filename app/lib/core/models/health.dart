/// Response from the agent's unauthenticated `/health` endpoint.
class Health {
  const Health({
    required this.status,
    required this.name,
    required this.version,
    required this.os,
    required this.readOnly,
    this.address,
    this.tailscaleAddress,
    this.macAddress,
  });

  final String status;
  final String name;
  final String version;
  final String os;
  final bool readOnly;

  /// The agent's self-reported addresses (added in Wave 2). Lets an
  /// already-paired app learn a host's Tailscale (or LAN) address it didn't
  /// capture at pairing time, just by reaching it successfully.
  final String? address;
  final String? tailscaleAddress;

  /// MAC address of the host's LAN interface (e.g. "aa:bb:cc:dd:ee:ff").
  /// Cached by the app for Wake-on-LAN when the host is asleep. Absent on
  /// older agents that predate WOL support.
  final String? macAddress;

  factory Health.fromJson(Map<String, dynamic> json) => Health(
    status: json['status'] as String? ?? 'unknown',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
    os: json['os'] as String? ?? '',
    readOnly: json['readOnly'] as bool? ?? false,
    address: _nonEmpty(json['address'] as String?),
    tailscaleAddress: _nonEmpty(json['tailscaleAddress'] as String?),
    macAddress: _nonEmpty(json['macAddress'] as String?),
  );
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
