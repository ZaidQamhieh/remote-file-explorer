/// Response from the agent's unauthenticated `/health` endpoint.
class Health {
  const Health({
    required this.status,
    required this.name,
    required this.version,
    required this.os,
    required this.readOnly,
  });

  final String status;
  final String name;
  final String version;
  final String os;
  final bool readOnly;

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        status: json['status'] as String? ?? 'unknown',
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        os: json['os'] as String? ?? '',
        readOnly: json['readOnly'] as bool? ?? false,
      );
}
