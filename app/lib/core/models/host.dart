/// A paired host agent the app can connect to, over LAN or Tailscale.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    this.certFingerprint,
    this.tailscaleName,
    this.tailscaleAddress,
  });

  final String id;
  final String label;

  /// Primary base address without scheme, e.g. `192.168.1.20:8765`. Usually
  /// the LAN address captured at pairing time.
  final String address;

  /// SHA-256 of the agent's TLS certificate, pinned at pairing time (TOFU).
  final String? certFingerprint;

  /// Tailscale MagicDNS name (currently unused; reserved for future discovery).
  final String? tailscaleName;

  /// Secondary address reachable over Tailscale, e.g. `100.x.y.z:8765`.
  /// Captured at pairing time or learned later from a successful `/health`
  /// call — lets the app reach this host both at home (LAN) and away
  /// (Tailscale) without the user managing two separate entries.
  final String? tailscaleAddress;

  /// Candidate addresses in connection-attempt order: primary first, then
  /// the Tailscale fallback (deduplicated).
  List<String> get addresses => [
    address,
    if (tailscaleAddress != null && tailscaleAddress != address)
      tailscaleAddress!,
  ];

  Uri get baseUri => Uri.parse('https://$address/v1');

  factory Host.fromJson(Map<String, dynamic> json) => Host(
    id: json['id'] as String,
    label: json['label'] as String,
    address: json['address'] as String,
    certFingerprint: json['certFingerprint'] as String?,
    tailscaleName: json['tailscaleName'] as String?,
    tailscaleAddress: json['tailscaleAddress'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    if (certFingerprint != null) 'certFingerprint': certFingerprint,
    if (tailscaleName != null) 'tailscaleName': tailscaleName,
    if (tailscaleAddress != null) 'tailscaleAddress': tailscaleAddress,
  };

  Host copyWith({
    String? id,
    String? label,
    String? address,
    String? certFingerprint,
    String? tailscaleName,
    String? tailscaleAddress,
  }) => Host(
    id: id ?? this.id,
    label: label ?? this.label,
    address: address ?? this.address,
    certFingerprint: certFingerprint ?? this.certFingerprint,
    tailscaleName: tailscaleName ?? this.tailscaleName,
    tailscaleAddress: tailscaleAddress ?? this.tailscaleAddress,
  );
}
