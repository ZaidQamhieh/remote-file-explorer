/// Response from `POST /pair`.
class PairResponse {
  const PairResponse({
    required this.deviceToken,
    required this.deviceId,
    required this.agentName,
    this.certFingerprint,
  });

  final String deviceToken;
  final String deviceId;
  final String agentName;

  /// SHA-256 of the agent TLS cert (for pinning after TOFU).
  final String? certFingerprint;

  factory PairResponse.fromJson(Map<String, dynamic> json) => PairResponse(
        deviceToken: json['deviceToken'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        agentName: json['agentName'] as String? ?? '',
        certFingerprint: json['certFingerprint'] as String?,
      );
}
