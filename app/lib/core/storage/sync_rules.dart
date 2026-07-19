import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A rule mapping a remote path on a host to a local download folder.
class SyncRule {
  const SyncRule({
    required this.id,
    required this.hostId,
    required this.remotePath,
    required this.localPath,
    this.enabled = true,
    this.lastSync,
  });

  final String id;
  final String hostId;
  final String remotePath;
  final String localPath;
  final bool enabled;
  final DateTime? lastSync;

  factory SyncRule.fromJson(Map<String, dynamic> json) => SyncRule(
    id: json['id'] as String,
    hostId: json['hostId'] as String,
    remotePath: json['remotePath'] as String,
    localPath: json['localPath'] as String,
    enabled: json['enabled'] as bool? ?? true,
    lastSync:
        json['lastSync'] == null
            ? null
            : DateTime.parse(json['lastSync'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'hostId': hostId,
    'remotePath': remotePath,
    'localPath': localPath,
    'enabled': enabled,
    if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
  };

  SyncRule copyWith({bool? enabled, DateTime? lastSync}) => SyncRule(
    id: id,
    hostId: hostId,
    remotePath: remotePath,
    localPath: localPath,
    enabled: enabled ?? this.enabled,
    lastSync: lastSync ?? this.lastSync,
  );
}

const _kSyncRulesKey = 'rfe_sync_rules_v1';

/// Persists [SyncRule]s in [SharedPreferences] as a JSON string list.
class SyncRuleStore {
  SyncRuleStore(this._prefs);
  final SharedPreferences _prefs;

  List<SyncRule> listRules() {
    final raw = _prefs.getStringList(_kSyncRulesKey) ?? [];
    final rules = <SyncRule>[];
    for (final s in raw) {
      try {
        rules.add(SyncRule.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // Skip one corrupt/legacy entry rather than bricking sync rules
        // entirely (PR-54).
      }
    }
    return rules;
  }

  Future<void> saveRule(SyncRule rule) async {
    final rules = listRules()..removeWhere((r) => r.id == rule.id);
    rules.add(rule);
    await _prefs.setStringList(
      _kSyncRulesKey,
      rules.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  Future<void> deleteRule(String id) async {
    final rules = listRules()..removeWhere((r) => r.id == id);
    await _prefs.setStringList(
      _kSyncRulesKey,
      rules.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }
}
