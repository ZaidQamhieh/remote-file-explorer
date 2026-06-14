/// Response from `POST /pair`.
class PairResponse {
  const PairResponse({
    required this.deviceToken,
    required this.deviceId,
    required this.agentName,
    this.certFingerprint,
    this.address,
    this.tailscaleAddress,
  });

  final String deviceToken;
  final String deviceId;
  final String agentName;

  /// SHA-256 of the agent TLS cert (for pinning after TOFU).
  final String? certFingerprint;

  /// The agent's self-reported LAN and Tailscale addresses (Wave 2), so a
  /// freshly paired host is immediately known under both.
  final String? address;
  final String? tailscaleAddress;

  factory PairResponse.fromJson(Map<String, dynamic> json) => PairResponse(
    deviceToken: json['deviceToken'] as String? ?? '',
    deviceId: json['deviceId'] as String? ?? '',
    agentName: json['agentName'] as String? ?? '',
    certFingerprint: json['certFingerprint'] as String?,
    address: _nonEmpty(json['address'] as String?),
    tailscaleAddress: _nonEmpty(json['tailscaleAddress'] as String?),
  );
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
