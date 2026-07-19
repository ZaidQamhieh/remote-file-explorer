import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/host.dart';
import '../../core/storage/download_saver.dart';
import '../../core/storage/host_store.dart';
import '../../core/storage/transfer_journal.dart';
import '../../core/storage/transfer_queue_store.dart';
import '../../core/ui/feedback.dart';
import 'chunk_planner.dart';

// ---------------------------------------------------------------------------
// Task id generation
// ---------------------------------------------------------------------------

/// Monotonic counter used to make task ids unique even when several tasks are
/// created within the same microsecond (e.g. a multi-select "upload all").
int _taskIdCounter = 0;

/// Returns an id that is unique for the lifetime of the process: a
/// timestamp for rough ordering plus a monotonically increasing sequence
/// number to break ties.
String _nextTaskId() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final seq = _taskIdCounter++;
  return '$ts-$seq';
}

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
    this.savedLocation,
    this.overwrite = false,
    this.verified = false,
    this.sha256,
  });

  /// [overwrite] is forwarded to [AgentClient.openUploadSession] when the
  /// session is opened — set when the user resolved a pre-flight name
  /// collision (see `explorer_screen.dart`'s `_pickAndUpload`) with
  /// "Overwrite".
  factory TransferTask.upload({
    required String localPath,
    required String remotePath,
    required Host host,
    bool overwrite = false,
  }) => TransferTask._(
    id: _nextTaskId(),
    kind: TransferKind.upload,
    localPath: localPath,
    remotePath: remotePath,
    host: host,
    overwrite: overwrite,
  );

  factory TransferTask.download({
    required String remotePath,
    required String localPath,
    required Host host,
  }) => TransferTask._(
    id: _nextTaskId(),
    kind: TransferKind.download,
    localPath: localPath,
    remotePath: remotePath,
    host: host,
  );

  /// Restores a task persisted by [TransferQueueStore] — see [toJson].
  factory TransferTask.fromJson(Map<String, dynamic> j) => TransferTask._(
    id: j['id'] as String,
    kind: TransferKind.values.byName(j['kind'] as String),
    localPath: j['localPath'] as String,
    remotePath: j['remotePath'] as String,
    host: Host.fromJson(j['host'] as Map<String, dynamic>),
    totalBytes: j['totalBytes'] as int? ?? 0,
    transferredBytes: j['transferredBytes'] as int? ?? 0,
    status: TransferStatus.values.byName(j['status'] as String),
    error: j['error'] as String?,
    uploadSessionId: j['uploadSessionId'] as String?,
    savedLocation: j['savedLocation'] as String?,
    overwrite: j['overwrite'] as bool? ?? false,
    verified: j['verified'] as bool? ?? false,
    sha256: j['sha256'] as String?,
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

  /// Where a completed download was saved (e.g. "Downloads/report.pdf").
  final String? savedLocation;

  /// For uploads: whether to overwrite an existing file at [remotePath]
  /// (passed to [AgentClient.openUploadSession]). Ignored for downloads.
  final bool overwrite;

  /// For completed uploads: whether the agent confirmed the whole-file
  /// SHA-256 matches on `POST /transfers/{id}/complete`
  /// ([AgentClient.completeUpload]'s `verified` field). Always `false` for
  /// downloads and for non-completed tasks.
  final bool verified;

  /// For completed, [verified] uploads: the verified whole-file SHA-256
  /// (hex), as reported by the agent's complete response. `null` otherwise.
  final String? sha256;

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  String get displayName => remotePath.split(RegExp(r'[/\\]')).last;

  /// Serializes this task for [TransferQueueStore]. Completed tasks are
  /// never persisted (see `TransferQueueNotifier._persist`), so this is only
  /// ever called for queued/running/paused/failed tasks.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'localPath': localPath,
    'remotePath': remotePath,
    'host': host.toJson(),
    'totalBytes': totalBytes,
    'transferredBytes': transferredBytes,
    'status': status.name,
    'error': error,
    'uploadSessionId': uploadSessionId,
    'savedLocation': savedLocation,
    'overwrite': overwrite,
    'verified': verified,
    'sha256': sha256,
  };

  TransferTask copyWith({
    int? totalBytes,
    int? transferredBytes,
    TransferStatus? status,
    Object? error = _sentinel,
    Object? uploadSessionId = _sentinel,
    String? savedLocation,
    bool? verified,
    String? sha256,
  }) => TransferTask._(
    id: id,
    kind: kind,
    localPath: localPath,
    remotePath: remotePath,
    host: host,
    totalBytes: totalBytes ?? this.totalBytes,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    status: status ?? this.status,
    error: error == _sentinel ? this.error : error as String?,
    uploadSessionId:
        uploadSessionId == _sentinel
            ? this.uploadSessionId
            : uploadSessionId as String?,
    savedLocation: savedLocation ?? this.savedLocation,
    overwrite: overwrite,
    verified: verified ?? this.verified,
    sha256: sha256 ?? this.sha256,
  );
}

const _sentinel = Object();

/// Internal signal thrown by `_run*` helpers when they notice the task has
/// been paused or removed and should stop without being marked completed or
/// failed. Caught by [TransferQueueNotifier._execute].
class _TaskStopped implements Exception {}

/// Thrown by [TransferQueueNotifier._runDownload] when the fully-downloaded
/// file's SHA-256 doesn't match the agent's checksum for the remote file —
/// the corrupt/stale staging copy has already been deleted.
class DownloadIntegrityException implements Exception {
  DownloadIntegrityException(this.fileName);
  final String fileName;

  @override
  String toString() => 'Downloaded file "$fileName" failed integrity check';
}

/// Computes the SHA-256 of the file at [path] by streaming it in fixed-size
/// chunks, so the whole file never has to fit in memory.
///
/// Designed to be run via [compute] (a background isolate) so hashing a
/// large file doesn't jank the UI.
Future<String> hashFileSha256(String path) async {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  await for (final chunk in File(path).openRead()) {
    input.add(chunk);
  }
  input.close();
  return sink.digest.toString();
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

// ---------------------------------------------------------------------------
// Queue notifier (Riverpod 3.x Notifier)
// ---------------------------------------------------------------------------

class TransferQueueNotifier extends Notifier<List<TransferTask>> {
  TransferQueueNotifier({
    AgentClient Function(Host host, {String? deviceToken})? clientFactory,
    TransferQueueStore? store,
  }) : _clientFactory = clientFactory ?? AgentClient.new,
       _store = store ?? TransferQueueStore();

  /// Builds the [AgentClient] used to run a transfer. Overridable so tests
  /// can substitute a fake client without spinning up real Dio/TLS/network.
  final AgentClient Function(Host host, {String? deviceToken}) _clientFactory;

  final TransferQueueStore _store;

  /// Chains persistence writes so they always apply in call order. Each
  /// `_persist()` call snapshots the *current* state and only starts its
  /// write once the previous one has finished — without this, two
  /// fire-and-forget `_store.save()` calls could resolve out of order and
  /// let an older snapshot silently overwrite a newer one on disk (PR-58).
  Future<void> _writeChain = Future.value();

  @override
  List<TransferTask> build() {
    // Restore unfinished tasks from a prior session (best effort — see
    // `TransferQueueStore`). `Notifier.build()` must return synchronously, so
    // the queue starts empty and this fills it in once storage resolves,
    // same pattern as `ExplorerNotifier`'s `Future.microtask(_load)`.
    Future.microtask(_hydrate);
    return [];
  }

  Future<void> _hydrate() async {
    final raw = await _store.load();
    if (raw.isEmpty) return;
    final restored =
        raw
            .map((j) {
              try {
                return TransferTask.fromJson(j);
              } catch (_) {
                return null; // drop anything corrupt rather than crash.
              }
            })
            .whereType<TransferTask>()
            // A task persisted mid-flight was actually killed along with the
            // process — it isn't really running, so surface it as paused
            // (user taps Resume) instead of claiming false progress.
            .map(
              (t) =>
                  t.status == TransferStatus.running
                      ? t.copyWith(status: TransferStatus.paused)
                      : t,
            )
            .toList();
    if (restored.isEmpty) return;
    state = [...state, ...restored];
    _runNext();
  }

  /// Cancel tokens for tasks currently executing, keyed by task id. Used by
  /// [pause] and [remove] to actually interrupt in-flight HTTP calls.
  final Map<String, CancelToken> _cancelTokens = {};

  void enqueue(TransferTask task) {
    state = [...state, task];
    _persist();
    _runNext();
  }

  Future<void> retry(String id) async {
    _updateById(
      id,
      (t) => t.copyWith(status: TransferStatus.queued, error: null),
      persist: true,
    );
    _runNext();
  }

  /// Pauses a queued or running task.
  ///
  /// If the task is currently running, its in-flight HTTP request is
  /// canceled so the underlying connection actually stops; [_execute] sees
  /// the cancellation, notices the task is already marked [TransferStatus.paused]
  /// and leaves it alone (rather than marking it failed or completed).
  void pause(String id) {
    final idx = state.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final current = state[idx];
    if (current.status != TransferStatus.running &&
        current.status != TransferStatus.queued) {
      return;
    }
    _updateById(
      id,
      (t) => t.copyWith(status: TransferStatus.paused),
      persist: true,
    );
    _cancelTokens[id]?.cancel('paused');
  }

  /// Removes a task from the queue, canceling it first if it's running.
  void remove(String id) {
    _cancelTokens[id]?.cancel('removed');
    state = state.where((t) => t.id != id).toList();
    _persist();
  }

  // ---------------------------------------------------------------------------

  /// Saves the unfinished (non-completed) tasks so [_hydrate] can restore
  /// them after a restart. Fire-and-forget — [TransferQueueStore.save] is
  /// itself best-effort and never throws.
  void _persist() {
    final snapshot =
        state
            .where((t) => t.status != TransferStatus.completed)
            .map((t) => t.toJson())
            .toList();
    _writeChain = _writeChain.then((_) => _store.save(snapshot));
  }

  /// [persist] should be `true` for status transitions and other fields a
  /// resume needs (e.g. `uploadSessionId`) — not for high-frequency,
  /// non-critical progress ticks (`transferredBytes`/`totalBytes`), which
  /// would otherwise write to disk on every chunk/byte callback.
  void _updateById(
    String id,
    TransferTask Function(TransferTask) fn, {
    bool persist = false,
  }) {
    final idx = state.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final list = List<TransferTask>.from(state);
    list[idx] = fn(list[idx]);
    state = list;
    if (persist) _persist();
  }

  /// Throws [_TaskStopped] if [id] is no longer running (paused or removed),
  /// so `_run*` loops can bail out cleanly between chunks/requests.
  void _checkStillRunning(String id) {
    final current = state.firstWhereOrNull((t) => t.id == id);
    if (current == null || current.status != TransferStatus.running) {
      throw _TaskStopped();
    }
  }

  void _runNext() {
    final running = state.where((t) => t.status == TransferStatus.running);
    if (running.isNotEmpty) return; // one at a time (foreground)
    final next =
        state.where((t) => t.status == TransferStatus.queued).firstOrNull;
    if (next == null) return;
    _execute(next.id);
  }

  Future<void> _execute(String id) async {
    _updateById(
      id,
      (t) => t.copyWith(status: TransferStatus.running),
      persist: true,
    );

    final task = state.firstWhere((t) => t.id == id);
    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;
    AgentClient? client;

    try {
      String? token;
      try {
        final store = await ref.read(hostStoreProvider.future);
        token = await store.getToken(task.host.id);
      } catch (_) {
        // Token lookup is best-effort: if secure storage is unavailable the
        // request will simply go out unauthenticated and the agent will
        // reject it with a normal (catchable) 401, rather than aborting the
        // transfer before it even starts.
        token = null;
      }
      client = _clientFactory(task.host, deviceToken: token);

      if (task.kind == TransferKind.download) {
        await _runDownload(id, task, client, cancelToken);
      } else {
        await _runUpload(id, task, client, cancelToken);
      }

      // Only mark completed if nothing paused/removed it while the last
      // await above was settling.
      final current = state.firstWhereOrNull((t) => t.id == id);
      if (current != null && current.status == TransferStatus.running) {
        _updateById(
          id,
          (t) => t.copyWith(status: TransferStatus.completed),
          persist: true,
        );
        _logToJournal(task);
      }
    } on _TaskStopped {
      // pause()/remove() already updated (or removed) the task; nothing
      // further to do here.
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Same as above: pause()/remove() already handled the status.
      } else {
        // Defense in depth: AgentClient normally converts non-cancel
        // DioExceptions to AgentApiException (caught below), but handle a
        // raw DioException too in case that ever changes.
        _updateById(
          id,
          (t) => t.copyWith(
            status: TransferStatus.failed,
            error: humanizeError(e),
          ),
          persist: true,
        );
      }
    } on AgentApiException catch (e) {
      // Safety net: a collision that wasn't caught by the pre-flight check in
      // `_pickAndUpload` (e.g. another upload landed between pick time and
      // session-open) surfaces here as 409 CONFLICT — give it a clearer
      // message than the raw exception's.
      _updateById(
        id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          error:
              e.code == 'CONFLICT'
                  ? '${t.displayName} already exists at the destination'
                  : humanizeError(e),
        ),
        persist: true,
      );
    } catch (e) {
      _updateById(
        id,
        (t) =>
            t.copyWith(status: TransferStatus.failed, error: humanizeError(e)),
        persist: true,
      );
    } finally {
      client?.close();
      _cancelTokens.remove(id);
      _runNext();
    }
  }

  // ---- Download ----

  Future<void> _runDownload(
    String id,
    TransferTask task,
    AgentClient client,
    CancelToken cancelToken,
  ) async {
    // Stage into a file scoped to this task's id, not the bare destination
    // name — task.localPath is shared by every download of a same-named
    // file (e.g. a retry after a cancelled download, or two files with the
    // same name from different folders/hosts), and the old code trusted any
    // bytes already sitting at that path as a resumable partial (PR-24).
    final stagingFile = File('${task.localPath}.rfe-part-${task.id}');

    var mimeType = 'application/octet-stream';
    try {
      final meta = await client.meta(task.remotePath);
      if (meta.size != null) {
        _updateById(id, (t) => t.copyWith(totalBytes: meta.size));
      }
      if (meta.mimeType != null && meta.mimeType!.isNotEmpty) {
        mimeType = meta.mimeType!;
      }
    } catch (_) {}

    Future<void> doDownload(int startByte) => client.downloadFile(
      remotePath: task.remotePath,
      localFile: stagingFile,
      startByte: startByte,
      cancelToken: cancelToken,
      onProgress: (received, total) {
        _updateById(
          id,
          (t) => t.copyWith(
            transferredBytes: startByte + received,
            totalBytes: total > 0 ? total : t.totalBytes,
          ),
        );
      },
    );

    var startByte = stagingFile.existsSync() ? stagingFile.lengthSync() : 0;
    try {
      await doDownload(startByte);
    } on RangeNotSatisfiedException {
      // The server didn't honor our Range request; agent_client already
      // deleted the (now-corrupt) partial file. Restart from scratch.
      startByte = 0;
      _updateById(id, (t) => t.copyWith(transferredBytes: 0));
      await doDownload(startByte);
    }

    // Verify the fully-received bytes against the agent's own checksum
    // before trusting the download — otherwise a remote file that changed
    // mid-transfer, or corruption in transit, is silently marked complete.
    final remoteHash = await client.checksum(task.remotePath);
    final localHash = await compute(hashFileSha256, stagingFile.path);
    if (remoteHash.toLowerCase() != localHash.toLowerCase()) {
      await stagingFile.delete();
      throw DownloadIntegrityException(task.displayName);
    }

    // Only now — verified good — does it take the real destination name,
    // replacing any stale file left there by a previous attempt.
    final localFile = await stagingFile.rename(task.localPath);

    // The file streamed to app-private storage; move it into the public
    // Downloads collection so it shows up in the phone's Files app.
    final saved = await DownloadSaver.saveToDownloads(
      localFile,
      task.displayName,
      mimeType,
    );
    _updateById(id, (t) => t.copyWith(savedLocation: saved));
  }

  // ---- Upload ----

  Future<void> _runUpload(
    String id,
    TransferTask task,
    AgentClient client,
    CancelToken cancelToken,
  ) async {
    final file = File(task.localPath);
    final fileSize = await file.length();
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
      // Hash the whole file in a background isolate — for large files this
      // can take seconds and must not block the UI thread.
      final wholeHash = await compute(hashFileSha256, task.localPath);
      _checkStillRunning(id);

      final session = await client.openUploadSession(
        path: task.remotePath,
        size: fileSize,
        sha256Hex: wholeHash,
        chunkSize: plan.chunkSize,
        overwrite: task.overwrite,
      );
      sessionId = session.id;
      _updateById(
        id,
        (t) => t.copyWith(uploadSessionId: sessionId),
        persist: true,
      );
    }

    int bytesSent = received.fold(0, (acc, ci) {
      final start = ci * plan.chunkSize;
      final end = (start + plan.chunkSize).clamp(0, fileSize);
      return acc + (end - start);
    });
    _updateById(id, (t) => t.copyWith(transferredBytes: bytesSent));

    final raf = await file.open();
    try {
      for (int ci = 0; ci < plan.totalChunks; ci++) {
        // Bail out cleanly if paused/removed since the last chunk.
        _checkStillRunning(id);

        if (received.contains(ci)) continue;

        final start = ci * plan.chunkSize;
        final end = (start + plan.chunkSize).clamp(0, fileSize);
        final length = end - start;

        await raf.setPosition(start);
        final chunkBytes = await raf.read(length);
        // Chunk-sized (<= a few MB) hash; cheap enough for the UI isolate,
        // unlike the whole-file hash above.
        final chunkHash = sha256.convert(chunkBytes).toString();
        final contentRange = 'bytes $start-${end - 1}/$fileSize';

        await client.uploadChunk(
          sessionId: sessionId,
          chunkIndex: ci,
          data: chunkBytes,
          contentRange: contentRange,
          chunkSha256: chunkHash,
          cancelToken: cancelToken,
          onProgress: (sent, _) {
            _updateById(
              id,
              (t) => t.copyWith(transferredBytes: bytesSent + sent),
            );
          },
        );
        bytesSent += chunkBytes.length;
        _updateById(id, (t) => t.copyWith(transferredBytes: bytesSent));
      }
    } finally {
      await raf.close();
    }

    // The agent verifies the whole-file SHA-256 on complete and reports the
    // result via `verified`/`sha256` (older agents omit both — parsed as
    // verified: false, sha256: null — see UploadCompleteResult.fromJson).
    final result = await client.completeUpload(sessionId);
    _updateById(
      id,
      (t) => t.copyWith(verified: result.verified, sha256: result.sha256),
    );
  }

  void _logToJournal(TransferTask task) {
    final fileName = task.remotePath.split('/').last.split('\\').last;
    final record = TransferRecord(
      fileName: fileName,
      remotePath: task.remotePath,
      hostLabel: task.host.label,
      kind: task.kind.name,
      bytes: task.totalBytes,
      completedAt: DateTime.now(),
    );
    // Fire-and-forget: wait for the async notifier to be ready, then add.
    final sub = ref.read(transferJournalProvider);
    if (sub.hasValue) {
      ref.read(transferJournalProvider.notifier).add(record);
    }
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

final transferQueueProvider =
    NotifierProvider<TransferQueueNotifier, List<TransferTask>>(
      TransferQueueNotifier.new,
    );
