/// Mirror of the agent's GET/PATCH /v1/settings payload.
class AgentSettings {
  const AgentSettings({
    required this.readOnly,
    required this.roots,
    required this.agentName,
  });

  final bool readOnly;
  final List<String> roots;
  final String agentName;

  factory AgentSettings.fromJson(Map<String, dynamic> json) => AgentSettings(
    readOnly: json['readOnly'] as bool? ?? false,
    roots:
        (json['roots'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
    agentName: json['agentName'] as String? ?? '',
  );

  AgentSettings copyWith({
    bool? readOnly,
    List<String>? roots,
    String? agentName,
  }) => AgentSettings(
    readOnly: readOnly ?? this.readOnly,
    roots: roots ?? this.roots,
    agentName: agentName ?? this.agentName,
  );
}
