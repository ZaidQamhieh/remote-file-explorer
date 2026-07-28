/// One security-relevant event from GET /v1/audit.
///
/// The agent records account/device/share events only — pairing, login,
/// device revocation, share links, restarts — never per-file operations.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.action,
    this.actor = '',
    this.target = '',
    this.detail = '',
  });

  /// Cursor for paging: pass the last entry's id as `before`.
  final int id;
  final DateTime at;

  /// Machine-readable event name, e.g. `login_failed`, `share_created`.
  final String action;

  /// Device label or username responsible, as recorded when the event
  /// happened — it survives the device or account being deleted afterwards.
  final String actor;
  final String target;
  final String detail;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
    id: (json['id'] as num?)?.toInt() ?? 0,
    at: DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    action: json['action'] as String? ?? '',
    actor: json['actor'] as String? ?? '',
    target: json['target'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
  );
}
