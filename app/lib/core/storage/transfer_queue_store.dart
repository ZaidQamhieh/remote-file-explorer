import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'transfer_queue_v1';

/// Persists the transfer queue's unfinished tasks (as raw JSON maps) across
/// app restarts, so an in-progress upload/download isn't silently forgotten
/// if the process dies mid-transfer (the previous behavior — the queue was
/// in-memory only). `TransferQueueNotifier` owns encoding/decoding individual
/// tasks (`TransferTask.toJson`/`fromJson`); this just stores the resulting
/// list. Both operations are best-effort: any failure (secure storage
/// unavailable, corrupt data) is swallowed rather than crashing a transfer.
class TransferQueueStore {
  Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Map<String, dynamic>> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(tasks));
    } catch (_) {
      // Best effort — a future restart just resumes from the last
      // successfully saved snapshot.
    }
  }
}
