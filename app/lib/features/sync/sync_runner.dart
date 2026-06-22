import 'dart:io';

import '../../core/api/agent_client.dart';
import '../../core/storage/sync_rules.dart';

/// Reports progress during a sync run.
class SyncProgress {
  const SyncProgress({
    required this.current,
    required this.total,
    this.currentFile,
  });

  final int current;
  final int total;
  final String? currentFile;
}

/// Executes a single [SyncRule]: lists the remote directory, then downloads
/// files that are missing or have a different size locally.
class SyncRunner {
  /// Runs the sync and returns the number of files actually downloaded.
  Future<int> run(
    AgentClient client,
    SyncRule rule, {
    void Function(SyncProgress)? onProgress,
  }) async {
    final listing = await client.list(rule.remotePath);
    final files = listing.entries.where((e) => !e.isDir).toList();
    var synced = 0;
    for (var i = 0; i < files.length; i++) {
      final entry = files[i];
      final localFile = File('${rule.localPath}/${entry.name}');
      onProgress?.call(
        SyncProgress(
          current: i + 1,
          total: files.length,
          currentFile: entry.name,
        ),
      );
      if (!localFile.existsSync() ||
          (localFile.lengthSync() != (entry.size ?? 0))) {
        await localFile.parent.create(recursive: true);
        await client.downloadFile(remotePath: entry.path, localFile: localFile);
        synced++;
      }
    }
    return synced;
  }
}
