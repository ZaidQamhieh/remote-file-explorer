/// A paired host agent the app can connect to, over LAN or Tailscale.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    this.certFingerprint,
    this.tailscaleName,
  });

  final String id;
  final String label;

  /// Base address without scheme, e.g. `192.168.1.20:8765` or
  /// `mypc.tailnet.ts.net:8765`.
  final String address;

  /// SHA-256 of the agent's TLS certificate, pinned at pairing time (TOFU).
  final String? certFingerprint;

  /// Tailscale MagicDNS name, used when off the local network.
  final String? tailscaleName;

  Uri get baseUri => Uri.parse('https://$address/v1');

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'] as String,
        label: json['label'] as String,
        address: json['address'] as String,
        certFingerprint: json['certFingerprint'] as String?,
        tailscaleName: json['tailscaleName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        if (certFingerprint != null) 'certFingerprint': certFingerprint,
        if (tailscaleName != null) 'tailscaleName': tailscaleName,
      };

  Host copyWith({
    String? id,
    String? label,
    String? address,
    String? certFingerprint,
    String? tailscaleName,
  }) =>
      Host(
        id: id ?? this.id,
        label: label ?? this.label,
        address: address ?? this.address,
        certFingerprint: certFingerprint ?? this.certFingerprint,
        tailscaleName: tailscaleName ?? this.tailscaleName,
      );
}
