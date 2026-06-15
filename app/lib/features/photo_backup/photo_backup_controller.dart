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
      final store = await PhotoBackupStore.open();
      await store.markDone(completed);
    }
  }

  Future<PhotoBackupRunResult> backupNow() async {
    final store = await PhotoBackupStore.open();
    final prefs = store.load();
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

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.upToDate);
    }
    final all = albums.first;
    final count = await all.assetCountAsync;
    final assets = await all.getAssetListRange(start: 0, end: count);

    final done = store.doneIds();
    final pending = assets.where((a) => !done.contains(a.id)).toList();
    if (pending.isEmpty) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.upToDate);
    }

    final queue = _ref.read(transferQueueProvider.notifier);
    var enqueued = 0;
    for (final a in pending) {
      final file = await a.originFile ?? await a.file;
      if (file == null) continue;
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
