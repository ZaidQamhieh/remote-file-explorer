import 'dart:io';

import '../../core/api/agent_client.dart';
import '../../core/models/entry.dart';
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

/// Whether [remote] needs to be (re)downloaded to keep the local replica
/// current. Same-size files used to be assumed unchanged, so a file edited
/// in place without changing length silently never re-synced (PR-31); a
/// remote [Entry.modified] newer than the local file's own mtime now also
/// triggers a re-download. Kept pure/File-free so it's directly unit
/// testable.
bool needsSync(
  Entry remote, {
  required bool localExists,
  int? localSize,
  DateTime? localModified,
}) {
  if (!localExists) return true;
  if (localSize != (remote.size ?? 0)) return true;
  final remoteModified = remote.modified;
  if (remoteModified != null && localModified != null) {
    return remoteModified.isAfter(localModified);
  }
  return false;
}

/// Executes a single [SyncRule]: lists the remote directory, then downloads
/// files that are missing, size-changed, or modified more recently remotely
/// than the local replica.
class SyncRunner {
  /// Runs the sync and returns the number of files actually downloaded.
  Future<int> run(
    AgentClient client,
    SyncRule rule, {
    void Function(SyncProgress)? onProgress,
  }) async {
    // Page through the entire remote listing — a single page silently
    // truncated large folders (PR-31).
    final files = <Entry>[];
    String? cursor;
    do {
      final listing = await client.list(rule.remotePath, cursor: cursor);
      files.addAll(listing.entries.where((e) => !e.isDir));
      cursor = listing.nextCursor;
    } while (cursor != null);

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
      final stat = await localFile.stat();
      final exists = stat.type != FileSystemEntityType.notFound;
      if (needsSync(
        entry,
        localExists: exists,
        localSize: exists ? stat.size : null,
        localModified: exists ? stat.modified : null,
      )) {
        await localFile.parent.create(recursive: true);
        // Download into a temp file and rename into place, so an
        // interrupted transfer never leaves a corrupt file that looks
        // "synced" (right name, wrong/partial contents) to the next run.
        final tempFile = File('${localFile.path}.rfe-sync-tmp');
        await client.downloadFile(remotePath: entry.path, localFile: tempFile);
        await tempFile.rename(localFile.path);
        synced++;
      }
    }
    return synced;
  }
}
