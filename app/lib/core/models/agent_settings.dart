/// Mirror of the agent's GET/PATCH /v1/settings payload.
class AgentSettings {
  const AgentSettings({
    required this.readOnly,
    required this.roots,
    required this.agentName,
    this.allowSharing = false,
  });

  final bool readOnly;
  final List<String> roots;
  final String agentName;

  /// Host-level gate for R1 one-time share links (default false).
  final bool allowSharing;

  factory AgentSettings.fromJson(Map<String, dynamic> json) => AgentSettings(
    readOnly: json['readOnly'] as bool? ?? false,
    roots:
        (json['roots'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
    agentName: json['agentName'] as String? ?? '',
    allowSharing: json['allowSharing'] as bool? ?? false,
  );

  AgentSettings copyWith({
    bool? readOnly,
    List<String>? roots,
    String? agentName,
    bool? allowSharing,
  }) => AgentSettings(
    readOnly: readOnly ?? this.readOnly,
    roots: roots ?? this.roots,
    agentName: agentName ?? this.agentName,
    allowSharing: allowSharing ?? this.allowSharing,
  );
}
