/// Response from the authenticated `/status` endpoint.
class AgentStatus {
  const AgentStatus({
    required this.version,
    required this.platform,
    required this.uptimeSeconds,
    required this.freeBytes,
    required this.totalBytes,
  });

  final String version;
  final String platform;
  final int uptimeSeconds;
  final int freeBytes;
  final int totalBytes;

  factory AgentStatus.fromJson(Map<String, dynamic> json) => AgentStatus(
    version: json['version'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    uptimeSeconds: json['uptimeSeconds'] as int? ?? 0,
    freeBytes: json['freeBytes'] as int? ?? 0,
    totalBytes: json['totalBytes'] as int? ?? 0,
  );
}
