import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import 'chunk_planner.dart';

// ---------------------------------------------------------------------------
// Transfer task model
// ---------------------------------------------------------------------------

enum TransferKind { upload, download }

enum TransferStatus { queued, running, paused, completed, failed }

class TransferTask {
  TransferTask._({
    required this.id,
    required this.kind,
    required this.localPath,
    required this.remotePath,
    required this.host,
    this.totalBytes = 0,
    this.transferredBytes = 0,
    this.status = TransferStatus.queued,
    this.error,
    this.uploadSessionId,
  });

  factory TransferTask.upload({
    required String localPath,
    required String remotePath,
    required Host host,
  }) =>
      TransferTask._(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: TransferKind.upload,
        localPath: localPath,
        remotePath: remotePath,
        host: host,
      );

  factory TransferTask.download({
    required String remotePath,
    required String localPath,
    required Host host,
  }) =>
      TransferTask._(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: TransferKind.download,
        localPath: localPath,
        remotePath: remotePath,
        host: host,
      );

  final String id;
  final TransferKind kind;
  final String localPath;
  final String remotePath;
  final Host host;

  final int totalBytes;
  final int transferredBytes;
  final TransferStatus status;
  final String? error;

  /// Session ID for resumable uploads.
  final String? uploadSessionId;

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  String get displayName => remotePath.split(RegExp(r'[/\\]')).last;

  TransferTask copyWith({
    int? totalBytes,
    int? transferredBytes,
    TransferStatus? status,
    Object? error = _sentinel,
    Object? uploadSessionId = _sentinel,
  }) =>
      TransferTask._(
        id: id,
        kind: kind,
        localPath: localPath,
        remotePath: remotePath,
        host: host,
        totalBytes: totalBytes ?? this.totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        status: status ?? this.status,
        error: error == _sentinel ? this.error : error as String?,
        uploadSessionId: uploadSessionId == _sentinel
            ? this.uploadSessionId
            : uploadSessionId as String?,
      );
}

const _sentinel = Object();

// ---------------------------------------------------------------------------
// Queue notifier (Riverpod 3.x Notifier)
// ---------------------------------------------------------------------------

class TransferQueueNotifier extends Notifier<List<TransferTask>> {
  @override
  List<TransferTask> build() => [];

  void enqueue(TransferTask task) {
    state = [...state, task];
    _runNext();
  }

  Future<void> retry(String id) async {
    _updateById(id, (t) => t.copyWith(
          status: TransferStatus.queued,
          transferredBytes: 0,
          error: null,
        ));
    _runNext();
  }

  void pause(String id) {
    _updateById(id, (t) => t.copyWith(status: TransferStatus.paused));
  }

  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  // ---------------------------------------------------------------------------

  void _updateById(String id, TransferTask Function(TransferTask) fn) {
    final idx = state.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final list = List<TransferTask>.from(state);
    list[idx] = fn(list[idx]);
    state = list;
  }

  void _runNext() {
    final running =
        state.where((t) => t.status == TransferStatus.running);
    if (running.isNotEmpty) return; // one at a time (foreground)
    final next =
        state.where((t) => t.status == TransferStatus.queued).firstOrNull;
    if (next == null) return;
    _execute(next.id);
  }

  Future<void> _execute(String id) async {
    _updateById(id, (t) => t.copyWith(status: TransferStatus.running));

    final task = state.firstWhere((t) => t.id == id);
    try {
      final store = await ref.read(hostStoreProvider.future);
      final token = await store.getToken(task.host.id);
      final client = AgentClient(task.host, deviceToken: token);

      if (task.kind == TransferKind.download) {
        await _runDownload(id, task, client);
      } else {
        await _runUpload(id, task, client);
      }
      _updateById(id, (t) => t.copyWith(status: TransferStatus.completed));
    } catch (e) {
      _updateById(
          id,
          (t) => t.copyWith(
                status: TransferStatus.failed,
                error: e.toString(),
              ));
    } finally {
      _runNext();
    }
  }

  // ---- Download ----

  Future<void> _runDownload(
      String id, TransferTask task, AgentClient client) async {
    final localFile = File(task.localPath);
    final startByte = localFile.existsSync() ? localFile.lengthSync() : 0;

    try {
      final meta = await client.meta(task.remotePath);
      if (meta.size != null) {
        _updateById(id, (t) => t.copyWith(totalBytes: meta.size));
      }
    } catch (_) {}

    await client.downloadFile(
      remotePath: task.remotePath,
      localFile: localFile,
      startByte: startByte,
      onProgress: (received, total) {
        _updateById(
            id,
            (t) => t.copyWith(
                  transferredBytes: startByte + received,
                  totalBytes: total > 0 ? total : t.totalBytes,
                ));
      },
    );
  }

  // ---- Upload ----

  Future<void> _runUpload(
      String id, TransferTask task, AgentClient client) async {
    final file = File(task.localPath);
    final fileBytes = await file.readAsBytes();
    final fileSize = fileBytes.length;

    final wholeHash = sha256.convert(fileBytes).toString();
    final plan = planChunks(fileSize);

    _updateById(id, (t) => t.copyWith(totalBytes: fileSize));

    String sessionId;
    List<int> received = [];

    final existingSessionId =
        state.firstWhere((t) => t.id == id).uploadSessionId;

    if (existingSessionId != null) {
      final session = await client.getUploadSession(existingSessionId);
      sessionId = session.id;
      received = session.receivedChunks;
    } else {
      final session = await client.openUploadSession(
        path: task.remotePath,
        size: fileSize,
        sha256Hex: wholeHash,
        chunkSize: plan.chunkSize,
      );
      sessionId = session.id;
      _updateById(id, (t) => t.copyWith(uploadSessionId: sessionId));
    }

    int bytesSent = received.fold(0, (acc, ci) {
      final start = ci * plan.chunkSize;
      final end = (start + plan.chunkSize).clamp(0, fileSize);
      return acc + (end - start);
    });

    for (int ci = 0; ci < plan.totalChunks; ci++) {
      // Check if task was paused
      final current = state.firstWhere(
        (t) => t.id == id,
        orElse: () => task.copyWith(status: TransferStatus.paused),
      );
      if (current.status == TransferStatus.paused) return;

      if (received.contains(ci)) continue;

      final start = ci * plan.chunkSize;
      final end = (start + plan.chunkSize).clamp(0, fileSize);
      final chunkBytes = Uint8List.sublistView(fileBytes, start, end);
      final chunkHash = sha256.convert(chunkBytes).toString();
      final contentRange = 'bytes $start-${end - 1}/$fileSize';

      await client.uploadChunk(
        sessionId: sessionId,
        chunkIndex: ci,
        data: chunkBytes,
        contentRange: contentRange,
        chunkSha256: chunkHash,
        onProgress: (sent, _) {
          _updateById(
              id, (t) => t.copyWith(transferredBytes: bytesSent + sent));
        },
      );
      bytesSent += chunkBytes.length;
      _updateById(id, (t) => t.copyWith(transferredBytes: bytesSent));
    }

    await client.completeUpload(sessionId);
  }
}

final transferQueueProvider =
    NotifierProvider<TransferQueueNotifier, List<TransferTask>>(
  TransferQueueNotifier.new,
);
