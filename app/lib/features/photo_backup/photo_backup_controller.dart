import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../transfers/transfer_state.dart';
import 'photo_backup_logic.dart';
import 'photo_backup_prefs.dart';

/// Outcome of a [PhotoBackupController.backupNow] run.
enum PhotoBackupOutcome {
  enqueued,
  upToDate,
  notConfigured,
  permissionDenied,
  skipped,
  disabled,
}

class PhotoBackupRunResult {
  const PhotoBackupRunResult(this.outcome, {this.enqueued = 0, this.message});
  final PhotoBackupOutcome outcome;
  final int enqueued;
  final String? message;
}

/// Drives one-way photo backup (DCIM → a PC). Scanning the device's photos,
/// permission, and the Wi-Fi/charging checks live here, behind small wrappers,
/// so the path/dedupe logic in [photo_backup_logic] stays plugin-free.
///
/// Photos are uploaded through the existing transfer queue (so the foreground
/// service from #9 keeps them alive in the background), and an asset is only
/// recorded as backed-up once its upload **completes** — a failed upload is
/// retried on the next run rather than silently skipped.
class PhotoBackupController {
  PhotoBackupController(this._ref);

  final Ref _ref;

  /// transfer-task id → photo asset id, for the tasks this controller created.
  final Map<String, String> _taskToAsset = {};

  /// Serializes the read-modify-write of the backed-up record so concurrent
  /// completions can't lose each other's updates.
  Future<void> _persistChain = Future<void>.value();

  /// Called (via the provider's ref.listen) whenever the transfer queue
  /// changes; records completed uploads into the dedupe set.
  Future<void> onTasks(List<TransferTask> tasks) async {
    if (_taskToAsset.isEmpty) return;
    final completed = <String>[];
    for (final t in tasks) {
      final assetId = _taskToAsset[t.id];
      if (assetId == null) continue;
      if (t.status == TransferStatus.completed) {
        completed.add(assetId);
        _taskToAsset.remove(t.id);
      } else if (t.status == TransferStatus.failed) {
        _taskToAsset.remove(t.id); // leave unmarked → retried next run
      }
    }
    if (completed.isNotEmpty) {
      _persistChain = _persistChain.then((_) async {
        final store = await PhotoBackupStore.open();
        await store.markDone(completed);
      });
      await _persistChain;
    }
  }

  Future<PhotoBackupRunResult> backupNow() async {
    final store = await PhotoBackupStore.open();
    final prefs = store.load();
    // Master switch: off means nothing backs up (manual runs included).
    if (!prefs.enabled) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.disabled);
    }
    if (!prefs.isConfigured) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.notConfigured);
    }
    if (prefs.wifiOnly && !await _onWifi()) {
      return const PhotoBackupRunResult(
        PhotoBackupOutcome.skipped,
        message: 'Waiting for Wi-Fi',
      );
    }
    if (prefs.chargingOnly && !await _charging()) {
      return const PhotoBackupRunResult(
        PhotoBackupOutcome.skipped,
        message: 'Waiting for charging',
      );
    }

    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth && !perm.hasAccess) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.permissionDenied);
    }

    final hostStore = await _ref.read(hostStoreProvider.future);
    Host? host;
    for (final h in hostStore.listHosts()) {
      if (h.id == prefs.hostId) {
        host = h;
        break;
      }
    }
    if (host == null) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.notConfigured);
    }

    final selected = prefs.albumIds.toSet();
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: selected.isEmpty,
    );
    // Filter to the user's chosen albums (empty selection = all photos, in
    // which case onlyAll above already returned the single merged album).
    final keep = albumsToScan([for (final a in albums) a.id], selected).toSet();
    final chosen = albums.where((a) => keep.contains(a.id)).toList();
    if (chosen.isEmpty) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.upToDate);
    }
    // Gather assets across all chosen albums, de-duplicated by asset id (one
    // photo can live in several albums).
    final seen = <String>{};
    final assets = <AssetEntity>[];
    for (final album in chosen) {
      final count = await album.assetCountAsync;
      final range = await album.getAssetListRange(start: 0, end: count);
      for (final a in range) {
        if (seen.add(a.id)) assets.add(a);
      }
    }

    final done = store.doneIds();
    final pending = assets.where((a) => !done.contains(a.id)).toList();
    if (pending.isEmpty) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.upToDate);
    }

    final queue = _ref.read(transferQueueProvider.notifier);
    var enqueued = 0;
    for (final a in pending) {
      try {
        final file = await a.originFile ?? await a.file;
        if (file == null) continue;
        // Skip a file that's still being written (e.g. cloud-sync still
        // downloading the original under photo_manager's feet) — its length
        // is checked twice a beat apart and must agree (and be non-zero).
        // Skipped assets aren't marked done, so they're retried next run.
        if (!await isFileStable(file.length)) continue;
        final title = await a.titleAsync;
        final name = title.isNotEmpty ? title : '${a.id}.jpg';
        final remote = backupRemotePath(
          destRoot: prefs.destRoot!,
          created: a.createDateTime,
          name: name,
        );
        final task = TransferTask.upload(
          localPath: file.path,
          remotePath: remote,
          host: host,
          overwrite: false,
        );
        _taskToAsset[task.id] = a.id;
        queue.enqueue(task);
        enqueued++;
      } catch (_) {
        // Skip an asset we can't materialize (limited access, deleted under
        // us, unsupported) rather than aborting the whole backup run.
        continue;
      }
    }
    return PhotoBackupRunResult(
      PhotoBackupOutcome.enqueued,
      enqueued: enqueued,
    );
  }

  Future<bool> _onWifi() async {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  Future<bool> _charging() async {
    final state = await Battery().batteryState;
    return state == BatteryState.charging || state == BatteryState.full;
  }
}

/// Provides the controller and wires the completion listener (kept alive for
/// the app session so backups marked-done even while the backup screen is closed).
final photoBackupControllerProvider = Provider<PhotoBackupController>((ref) {
  final controller = PhotoBackupController(ref);
  ref.listen<List<TransferTask>>(
    transferQueueProvider,
    (_, tasks) => controller.onTasks(tasks),
  );
  return controller;
});
