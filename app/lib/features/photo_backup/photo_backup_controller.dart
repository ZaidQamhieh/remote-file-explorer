import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/api/providers.dart';
import '../../core/models/host.dart';
import '../../core/security/device_identity.dart';
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

  /// The PC hasn't set a photo-backup destination in its web companion
  /// Settings yet — the phone never picks its own path, so this is a hard
  /// stop rather than a fallback.
  serverNotConfigured,
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

    // The destination folder is the PC's call (web companion Settings), not
    // the phone's — fetched fresh every run rather than cached, so a change
    // on the PC takes effect on the very next backup without a phone update.
    String photoBackupRoot;
    final client = await buildClientForHost(_ref.read, host.id);
    try {
      photoBackupRoot = (await client.getSettings()).photoBackupRoot;
    } catch (e) {
      return PhotoBackupRunResult(
        PhotoBackupOutcome.skipped,
        message: 'Could not reach ${host.label} to check backup settings',
      );
    } finally {
      client.close();
    }
    if (photoBackupRoot.isEmpty) {
      return const PhotoBackupRunResult(PhotoBackupOutcome.serverNotConfigured);
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

    // Scopes this phone's uploads to their own subfolder under destRoot, so
    // two phones backing up to the same host+folder don't interleave photos.
    // Prefers the user's nickname (so "which phone is which" stays readable
    // at the 3-8-device scale this app targets) and falls back to a stable
    // per-install id only when nothing's been set.
    final nickname = prefs.deviceName?.trim();
    final deviceSegment =
        (nickname != null && nickname.isNotEmpty)
            ? _sanitizeSegment(nickname)
            : await _deviceSegment();

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
        // Use the asset id (stable, filesystem-agnostic) plus an extension
        // sniffed from the title, rather than the title itself — a synced or
        // renamed photo's title is untrusted input and, unlike a bare
        // extension, could carry `../` or platform-invalid characters into
        // the remote path built below (PR-15).
        final name = '${a.id}${_safeExtension(await a.titleAsync)}';
        final remote = backupRemotePath(
          destRoot: photoBackupRoot,
          created: a.createDateTime,
          name: name,
          deviceSegment: deviceSegment,
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

  /// Short, stable per-install id derived from this device's pairing keypair
  /// (already generated/persisted by [DeviceIdentity] — no new device-name
  /// plugin needed). Used as a destRoot subfolder so backups from different
  /// phones don't collide.
  Future<String> _deviceSegment() async {
    final pubKey = await DeviceIdentity.instance.publicKeyBase64();
    return sha256.convert(utf8.encode(pubKey)).toString().substring(0, 8);
  }

  /// Keeps a user-typed device nickname safe as a single path segment: no
  /// separators/reserved characters, no leading/trailing dots or spaces (a
  /// bare `.`/`..` or a Windows-invalid trailing dot could otherwise land as
  /// a literal remote path segment), no control characters, bounded length.
  /// Falls back to the per-install id shape if sanitization empties it out.
  static String _sanitizeSegment(String name) {
    var s = name.replaceAll(RegExp(r'[\x00-\x1f\\/:*?"<>|]'), '_');
    s = s.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (s.length > 64) s = s.substring(0, 64);
    return s.isEmpty ? 'device' : s;
  }

  /// Extracts a short, safe extension (`.` + up to 5 alnum chars) from an
  /// asset title, or `.jpg` if the title has none — never returns the title
  /// itself (see [name] above, PR-15).
  static String _safeExtension(String title) {
    final match = RegExp(r'\.([A-Za-z0-9]{1,5})$').firstMatch(title);
    return match == null ? '.jpg' : '.${match.group(1)}';
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
