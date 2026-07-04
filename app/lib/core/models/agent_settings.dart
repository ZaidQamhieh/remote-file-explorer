/// Mirror of the agent's GET/PATCH /v1/settings payload.
class AgentSettings {
  const AgentSettings({
    required this.readOnly,
    required this.roots,
    required this.agentName,
    this.allowSharing = false,
    this.photoBackupRoot = '',
  });

  final bool readOnly;
  final List<String> roots;
  final String agentName;

  /// Host-level gate for R1 one-time share links (default false).
  final bool allowSharing;

  /// PC-side destination folder for phone photo backup, set from the web
  /// companion only. Empty means the PC owner hasn't configured one yet.
  final String photoBackupRoot;

  factory AgentSettings.fromJson(Map<String, dynamic> json) => AgentSettings(
    readOnly: json['readOnly'] as bool? ?? false,
    roots:
        (json['roots'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
    agentName: json['agentName'] as String? ?? '',
    allowSharing: json['allowSharing'] as bool? ?? false,
    photoBackupRoot: json['photoBackupRoot'] as String? ?? '',
  );

  AgentSettings copyWith({
    bool? readOnly,
    List<String>? roots,
    String? agentName,
    bool? allowSharing,
    String? photoBackupRoot,
  }) => AgentSettings(
    readOnly: readOnly ?? this.readOnly,
    roots: roots ?? this.roots,
    agentName: agentName ?? this.agentName,
    allowSharing: allowSharing ?? this.allowSharing,
    photoBackupRoot: photoBackupRoot ?? this.photoBackupRoot,
  );
}
