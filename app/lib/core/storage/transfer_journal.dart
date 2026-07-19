import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kJournalKey = 'rfe_transfer_journal_v1';
const _maxEntries = 200;

class TransferRecord {
  const TransferRecord({
    required this.fileName,
    required this.remotePath,
    required this.hostLabel,
    required this.kind,
    required this.bytes,
    required this.completedAt,
  });

  final String fileName;
  final String remotePath;
  final String hostLabel;
  final String kind; // 'upload' or 'download'
  final int bytes;
  final DateTime completedAt;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'remotePath': remotePath,
    'hostLabel': hostLabel,
    'kind': kind,
    'bytes': bytes,
    'completedAt': completedAt.toIso8601String(),
  };

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
    fileName: json['fileName'] as String? ?? '',
    remotePath: json['remotePath'] as String? ?? '',
    hostLabel: json['hostLabel'] as String? ?? '',
    kind: json['kind'] as String? ?? 'download',
    bytes: json['bytes'] as int? ?? 0,
    completedAt: DateTime.parse(
      json['completedAt'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );
}

class TransferJournalNotifier extends AsyncNotifier<List<TransferRecord>> {
  SharedPreferences? _prefs;

  @override
  Future<List<TransferRecord>> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kJournalKey);
    if (raw == null) return [];
    final List list;
    try {
      list = jsonDecode(raw) as List;
    } catch (_) {
      // The whole persisted blob is corrupt — better to lose journal
      // history than brick the feature that reads it (PR-54).
      return [];
    }
    final records = <TransferRecord>[];
    for (final e in list) {
      try {
        records.add(TransferRecord.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        // Skip one corrupt entry rather than dropping the whole journal.
      }
    }
    return records;
  }

  Future<void> _persist(List<TransferRecord> records) async {
    await _prefs?.setString(
      _kJournalKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
    state = AsyncData(records);
  }

  Future<void> add(TransferRecord record) async {
    var current = List<TransferRecord>.from(state.valueOrNull ?? []);
    current.insert(0, record);
    if (current.length > _maxEntries) {
      current = current.sublist(0, _maxEntries);
    }
    await _persist(current);
  }

  Future<void> clear() async {
    await _persist([]);
  }
}

final transferJournalProvider =
    AsyncNotifierProvider<TransferJournalNotifier, List<TransferRecord>>(
      TransferJournalNotifier.new,
    );
