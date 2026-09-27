/// Mirror of the agent's GET/PATCH /v1/settings payload.
class AgentSettings {
  const AgentSettings({
    required this.readOnly,
    required this.roots,
    required this.agentName,
    this.isAdmin = false,
    this.isAdminKnown = false,
    this.effectiveScope = 'device',
    this.accessDenied = false,
    this.allowSharing = false,
    this.photoBackupConfigured = false,
    this.photoBackupAvailable,
    this.photoBackupRoot = '',
  });

  /// Whether the caller authenticated with the account password and may
  /// manage host-wide settings and other devices.
  final bool isAdmin;

  /// Whether the connected agent explicitly sent the `isAdmin` property.
  /// Older agents omit it; those agents keep the prior app behavior for host
  /// controls, while an explicit `false` from a current agent stays denied.
  final bool isAdminKnown;

  /// Compatibility decision for host-wide controls on pre-`isAdmin` agents.
  bool get canManageHost => isAdmin || !isAdminKnown;

  /// `global` for an admin session, or `device` for this device's effective
  /// policy after its jail and read-only restrictions are applied.
  final String effectiveScope;

  /// True when this device's configured jail falls outside every host root.
  /// An empty [roots] list otherwise means unrestricted access.
  final bool accessDenied;

  final bool readOnly;
  final List<String> roots;
  final String agentName;

  /// Host-level gate for R1 one-time share links (default false).
  final bool allowSharing;

  /// Whether the PC has a configured photo-backup destination. This boolean
  /// is available to paired clients without disclosing the destination path.
  final bool photoBackupConfigured;

  /// Whether this caller can write to the configured destination under its
  /// effective path roots and read-only policy. The eventual filesystem write
  /// can still fail because of operating-system permissions. Null means the
  /// agent predates this field.
  final bool? photoBackupAvailable;

  /// PC-side destination folder for phone photo backup, set from the web
  /// companion only. May be empty when unconfigured or not available to this
  /// caller.
  final String photoBackupRoot;

  factory AgentSettings.fromJson(Map<String, dynamic> json) => AgentSettings(
    isAdmin: json['isAdmin'] as bool? ?? false,
    isAdminKnown: json.containsKey('isAdmin'),
    effectiveScope: json['effectiveScope'] as String? ?? 'device',
    accessDenied: json['accessDenied'] as bool? ?? false,
    readOnly: json['readOnly'] as bool? ?? false,
    roots:
        (json['roots'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
    agentName: json['agentName'] as String? ?? '',
    allowSharing: json['allowSharing'] as bool? ?? false,
    photoBackupConfigured:
        json['photoBackupConfigured'] as bool? ??
        ((json['photoBackupRoot'] as String?)?.isNotEmpty ?? false),
    photoBackupAvailable: json['photoBackupAvailable'] as bool?,
    photoBackupRoot: json['photoBackupRoot'] as String? ?? '',
  );

  AgentSettings copyWith({
    bool? isAdmin,
    bool? isAdminKnown,
    String? effectiveScope,
    bool? accessDenied,
    bool? readOnly,
    List<String>? roots,
    String? agentName,
    bool? allowSharing,
    bool? photoBackupConfigured,
    bool? photoBackupAvailable,
    String? photoBackupRoot,
  }) => AgentSettings(
    isAdmin: isAdmin ?? this.isAdmin,
    isAdminKnown: isAdminKnown ?? this.isAdminKnown,
    effectiveScope: effectiveScope ?? this.effectiveScope,
    accessDenied: accessDenied ?? this.accessDenied,
    readOnly: readOnly ?? this.readOnly,
    roots: roots ?? this.roots,
    agentName: agentName ?? this.agentName,
    allowSharing: allowSharing ?? this.allowSharing,
    photoBackupConfigured: photoBackupConfigured ?? this.photoBackupConfigured,
    photoBackupAvailable: photoBackupAvailable ?? this.photoBackupAvailable,
    photoBackupRoot: photoBackupRoot ?? this.photoBackupRoot,
  );
}
