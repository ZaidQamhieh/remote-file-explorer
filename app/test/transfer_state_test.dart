import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/upload_session.dart';
import 'package:remote_file_explorer/core/storage/transfer_queue_store.dart';
import 'package:remote_file_explorer/features/transfers/chunk_planner.dart';
import 'package:remote_file_explorer/features/transfers/transfer_state.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

/// Polls [predicate] until it's true or [timeout] elapses.
Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // Bug 6 — unique task ids
  // ---------------------------------------------------------------------
  group('TransferTask id generation', () {
    test('rapid creation in a tight loop yields unique ids', () {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        ids.add(
          TransferTask.upload(
            localPath: '/tmp/f$i',
            remotePath: '/remote/f$i',
            host: _testHost,
          ).id,
        );
      }
      expect(ids.length, 200, reason: 'all ids must be unique');
    });

    test('upload and download factories never collide', () {
      final upload = TransferTask.upload(
        localPath: '/tmp/a',
        remotePath: '/remote/a',
        host: _testHost,
      );
      final download = TransferTask.download(
        remotePath: '/remote/a',
        localPath: '/tmp/a',
        host: _testHost,
      );
      expect(upload.id, isNot(equals(download.id)));
    });
  });

  // ---------------------------------------------------------------------
  // Bug 2 — streaming whole-file SHA-256
  // ---------------------------------------------------------------------
  group('hashFileSha256', () {
    test('matches sha256.convert on the full bytes for a small file', () async {
      final dir = await Directory.systemTemp.createTemp('hash_small_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/small.bin');
      final bytes = Uint8List.fromList(
        List<int>.generate(1000, (i) => i % 256),
      );
      await file.writeAsBytes(bytes);

      final streamed = await hashFileSha256(file.path);
      final expected = sha256.convert(bytes).toString();

      expect(streamed, expected);
    });

    test('matches sha256.convert across a multi-chunk file', () async {
      final dir = await Directory.systemTemp.createTemp('hash_large_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/large.bin');
      // A few MB so the streaming reader sees multiple internal chunks.
      final bytes = Uint8List.fromList(
        List<int>.generate(3 * 1024 * 1024 + 17, (i) => i % 256),
      );
      await file.writeAsBytes(bytes);

      final streamed = await hashFileSha256(file.path);
      final expected = sha256.convert(bytes).toString();

      expect(streamed, expected);
    });

    test('matches sha256.convert for an empty file', () async {
      final dir = await Directory.systemTemp.createTemp('hash_empty_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/empty.bin');
      await file.writeAsBytes(const []);

      final streamed = await hashFileSha256(file.path);
      final expected = sha256.convert(const <int>[]).toString();

      expect(streamed, expected);
    });
  });

  // ---------------------------------------------------------------------
  // Bug 2 — chunk read planning via RandomAccessFile (no full-file buffer)
  // ---------------------------------------------------------------------
  group('chunk read planning', () {
    test('reading chunks via RandomAccessFile reconstructs the file and '
        'matches per-chunk hashes', () async {
      final dir = await Directory.systemTemp.createTemp('chunks_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/data.bin');
      final bytes = Uint8List.fromList(
        List<int>.generate(100, (i) => i),
      ); // 100 bytes
      await file.writeAsBytes(bytes);

      const chunkSize = 30; // forces 4 chunks: 30,30,30,10
      final plan = planChunks(bytes.length, chunkSize: chunkSize);
      expect(plan.totalChunks, 4);

      final raf = await file.open();
      final reconstructed = BytesBuilder();
      try {
        for (var ci = 0; ci < plan.totalChunks; ci++) {
          final start = ci * plan.chunkSize;
          final end = (start + plan.chunkSize).clamp(0, bytes.length);
          final length = end - start;

          await raf.setPosition(start);
          final chunk = await raf.read(length);

          expect(chunk.length, length);
          expect(
            sha256.convert(chunk).toString(),
            sha256.convert(bytes.sublist(start, end)).toString(),
          );
          reconstructed.add(chunk);
        }
      } finally {
        await raf.close();
      }

      expect(reconstructed.toBytes(), bytes);
    });

    test('empty file plans exactly one zero-length chunk', () async {
      final dir = await Directory.systemTemp.createTemp('chunks_empty_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/empty.bin');
      await file.writeAsBytes(const []);

      final plan = planChunks(0);
      expect(plan.totalChunks, 1);

      final raf = await file.open();
      try {
        const start = 0;
        final end = (start + plan.chunkSize).clamp(0, 0);
        final chunk = await raf.read(end - start);
        expect(chunk, isEmpty);
      } finally {
        await raf.close();
      }
    });
  });

  // ---------------------------------------------------------------------
  // Bug 3/4 — pause must stop the run and leave status `paused`, not
  // `completed`/`failed`, and must not let _runNext start another task
  // while the paused one is still "in flight".
  // ---------------------------------------------------------------------
  group('pause semantics', () {
    test(
      'pausing a running download leaves status paused, not completed',
      () async {
        final dir = await Directory.systemTemp.createTemp('pause_dl_');
        addTearDown(() => dir.delete(recursive: true));
        final localPath = '${dir.path}/out.bin';

        final downloadStarted = Completer<void>();
        final client = _FakeAgentClient(
          host: _testHost,
          onDownload: (_, cancelToken) async {
            downloadStarted.complete();
            // Block until canceled, like a real in-flight HTTP stream.
            await cancelToken.whenCancel;
            throw DioException(
              requestOptions: RequestOptions(path: '/content'),
              type: DioExceptionType.cancel,
            );
          },
        );

        final container = ProviderContainer(
          overrides: [
            transferQueueProvider.overrideWith(
              () => TransferQueueNotifier(
                clientFactory: (host, {deviceToken}) => client,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(transferQueueProvider.notifier);
        final task = TransferTask.download(
          remotePath: '/remote/file.bin',
          localPath: localPath,
          host: _testHost,
        );
        notifier.enqueue(task);

        await downloadStarted.future;
        // Task should now be running.
        expect(
          container
              .read(transferQueueProvider)
              .firstWhere((t) => t.id == task.id)
              .status,
          TransferStatus.running,
        );

        notifier.pause(task.id);

        await _waitUntil(
          () =>
              container
                  .read(transferQueueProvider)
                  .firstWhere((t) => t.id == task.id)
                  .status !=
              TransferStatus.running,
        );

        final finalTask = container
            .read(transferQueueProvider)
            .firstWhere((t) => t.id == task.id);
        expect(finalTask.status, TransferStatus.paused);
      },
    );

    test(
      'pausing a still-queued task marks it paused without ever running',
      () async {
        final blocking = Completer<void>();
        final blockingClient = _FakeAgentClient(
          host: _testHost,
          onDownload: (_, cancelToken) async {
            await blocking.future; // never completes in this test
          },
        );
        // The "first" task below blocks forever, so _execute never reaches its
        // `finally` block to close this client itself — close it explicitly so
        // its underlying HttpClient doesn't linger past the test.
        addTearDown(blockingClient.close);

        final container = ProviderContainer(
          overrides: [
            transferQueueProvider.overrideWith(
              () => TransferQueueNotifier(
                clientFactory: (host, {deviceToken}) => blockingClient,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(transferQueueProvider.notifier);

        final first = TransferTask.download(
          remotePath: '/remote/a.bin',
          localPath: '/tmp/a.bin',
          host: _testHost,
        );
        final second = TransferTask.download(
          remotePath: '/remote/b.bin',
          localPath: '/tmp/b.bin',
          host: _testHost,
        );
        // Enqueueing `first` immediately starts it (and it blocks forever),
        // so `second` stays queued — exactly the "one at a time" queue.
        notifier.enqueue(first);
        notifier.enqueue(second);

        await _waitUntil(
          () =>
              container
                  .read(transferQueueProvider)
                  .firstWhere((t) => t.id == first.id)
                  .status ==
              TransferStatus.running,
        );

        final secondBefore = container
            .read(transferQueueProvider)
            .firstWhere((t) => t.id == second.id);
        expect(secondBefore.status, TransferStatus.queued);

        notifier.pause(second.id);

        final secondAfter = container
            .read(transferQueueProvider)
            .firstWhere((t) => t.id == second.id);
        expect(secondAfter.status, TransferStatus.paused);
      },
    );
  });

  // ---------------------------------------------------------------------
  // Bug 1/5 — resumed download: RangeNotSatisfiedException restarts from 0
  // ---------------------------------------------------------------------
  group('download resume fallback', () {
    test('RangeNotSatisfiedException causes a restart from byte 0', () async {
      final dir = await Directory.systemTemp.createTemp('resume_');
      addTearDown(() => dir.delete(recursive: true));
      final localPath = '${dir.path}/out.bin';

      final task = TransferTask.download(
        remotePath: '/remote/file.bin',
        localPath: localPath,
        host: _testHost,
      );

      // Simulate a partial file already on disk from a previous attempt, at
      // the task-scoped staging path _runDownload actually resumes from
      // (PR-24 — resuming from the bare destination path let an unrelated
      // same-name file be mistaken for a partial).
      final stagingPath = '$localPath.rfe-part-${task.id}';
      await File(stagingPath).writeAsBytes(List<int>.filled(50, 1));

      final startBytesSeen = <int>[];
      final client = _FakeAgentClient(
        host: _testHost,
        onDownloadWithStart: (localFile, startByte) async {
          startBytesSeen.add(startByte);
          if (startByte > 0) {
            // Server ignored our Range header.
            throw RangeNotSatisfiedException();
          }
          // Successful full download from scratch.
          await localFile.writeAsBytes(List<int>.filled(100, 2));
        },
      );

      final container = ProviderContainer(
        overrides: [
          transferQueueProvider.overrideWith(
            () => TransferQueueNotifier(
              clientFactory: (host, {deviceToken}) => client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transferQueueProvider.notifier);
      notifier.enqueue(task);

      await _waitUntil(() {
        final t = container
            .read(transferQueueProvider)
            .firstWhere((x) => x.id == task.id);
        return t.status == TransferStatus.completed ||
            t.status == TransferStatus.failed;
      });

      final finalTask = container
          .read(transferQueueProvider)
          .firstWhere((t) => t.id == task.id);

      expect(
        startBytesSeen.first,
        50,
        reason: 'first attempt should resume from the existing partial',
      );
      expect(
        startBytesSeen.last,
        0,
        reason: 'after RangeNotSatisfiedException it must restart from 0',
      );
      expect(finalTask.status, TransferStatus.completed);
    });
  });

  // ---------------------------------------------------------------------
  // PR-24 — completed downloads are verified against the agent's checksum
  // ---------------------------------------------------------------------
  group('download integrity verification', () {
    test(
      'a checksum mismatch fails the task and deletes the staging file',
      () async {
        final dir = await Directory.systemTemp.createTemp('integrity_');
        addTearDown(() => dir.delete(recursive: true));
        final localPath = '${dir.path}/out.bin';

        final client = _FakeAgentClient(
          host: _testHost,
          onDownloadWithStart: (localFile, startByte) async {
            await localFile.writeAsBytes(List<int>.filled(10, 7));
          },
          checksumOverride: (path) async => '0' * 64, // never matches
        );

        final container = ProviderContainer(
          overrides: [
            transferQueueProvider.overrideWith(
              () => TransferQueueNotifier(
                clientFactory: (host, {deviceToken}) => client,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(transferQueueProvider.notifier);
        final task = TransferTask.download(
          remotePath: '/remote/file.bin',
          localPath: localPath,
          host: _testHost,
        );
        notifier.enqueue(task);

        await _waitUntil(
          () =>
              container
                  .read(transferQueueProvider)
                  .firstWhere((x) => x.id == task.id)
                  .status ==
              TransferStatus.failed,
        );

        final finalTask = container
            .read(transferQueueProvider)
            .firstWhere((t) => t.id == task.id);
        expect(finalTask.error, contains('integrity check'));
        expect(
          await File('$localPath.rfe-part-${task.id}').exists(),
          isFalse,
          reason: 'the corrupt/mismatched staging file must not be kept',
        );
        expect(
          await File(localPath).exists(),
          isFalse,
          reason: 'a failed verification must never publish to the real path',
        );
      },
    );

    test(
      'an unrelated file already at the destination is never resumed into',
      () async {
        final dir = await Directory.systemTemp.createTemp('collision_');
        addTearDown(() => dir.delete(recursive: true));
        final localPath = '${dir.path}/out.bin';

        // An unrelated file happens to already sit at the exact destination
        // path (e.g. left by an unrelated earlier download of a same-named
        // file). Before PR-24 this file's length was trusted as a resumable
        // partial for this task.
        await File(localPath).writeAsBytes(List<int>.filled(999, 9));

        final startBytesSeen = <int>[];
        final client = _FakeAgentClient(
          host: _testHost,
          onDownloadWithStart: (localFile, startByte) async {
            startBytesSeen.add(startByte);
            await localFile.writeAsBytes(List<int>.filled(10, 7));
          },
        );

        final container = ProviderContainer(
          overrides: [
            transferQueueProvider.overrideWith(
              () => TransferQueueNotifier(
                clientFactory: (host, {deviceToken}) => client,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(transferQueueProvider.notifier);
        final task = TransferTask.download(
          remotePath: '/remote/file.bin',
          localPath: localPath,
          host: _testHost,
        );
        notifier.enqueue(task);

        await _waitUntil(() {
          final t = container
              .read(transferQueueProvider)
              .firstWhere((x) => x.id == task.id);
          return t.status == TransferStatus.completed ||
              t.status == TransferStatus.failed;
        });

        expect(
          startBytesSeen.single,
          0,
          reason:
              'the unrelated file at the destination path must never be '
              'treated as a resumable partial for this task',
        );
        final finalTask = container
            .read(transferQueueProvider)
            .firstWhere((t) => t.id == task.id);
        expect(finalTask.status, TransferStatus.completed);
      },
    );
  });

  // ---------------------------------------------------------------------
  // retry() state transitions
  // ---------------------------------------------------------------------
  group('retry()', () {
    test('retrying a failed task clears the error before re-running', () async {
      var attempt = 0;
      final client = _FakeAgentClient(
        host: _testHost,
        onDownload: (_, cancelToken) async {
          attempt++;
          throw Exception('network down (attempt $attempt)');
        },
      );

      final container = ProviderContainer(
        overrides: [
          transferQueueProvider.overrideWith(
            () => TransferQueueNotifier(
              clientFactory: (host, {deviceToken}) => client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transferQueueProvider.notifier);
      final task = TransferTask.download(
        remotePath: '/remote/file.bin',
        localPath: '/tmp/retry_test.bin',
        host: _testHost,
      );
      notifier.enqueue(task);

      await _waitUntil(
        () =>
            container
                .read(transferQueueProvider)
                .firstWhere((x) => x.id == task.id)
                .status ==
            TransferStatus.failed,
      );

      var current = container
          .read(transferQueueProvider)
          .firstWhere((t) => t.id == task.id);
      expect(current.status, TransferStatus.failed);
      expect(current.error, contains('attempt 1'));

      await notifier.retry(task.id);

      // It must run again (attempt 2) and fail again with a *new* error,
      // never getting stuck `queued` or wrongly marked `completed`.
      await _waitUntil(() => attempt >= 2);
      await _waitUntil(
        () =>
            container
                .read(transferQueueProvider)
                .firstWhere((x) => x.id == task.id)
                .status ==
            TransferStatus.failed,
      );

      current = container
          .read(transferQueueProvider)
          .firstWhere((t) => t.id == task.id);
      expect(current.status, TransferStatus.failed);
      expect(current.error, contains('attempt 2'));
    });

    test(
      'retrying a paused download resumes from the existing partial',
      () async {
        final dir = await Directory.systemTemp.createTemp('retry_resume_');
        addTearDown(() => dir.delete(recursive: true));
        final localPath = '${dir.path}/out.bin';

        final task = TransferTask.download(
          remotePath: '/remote/file.bin',
          localPath: localPath,
          host: _testHost,
        );
        final stagingPath = '$localPath.rfe-part-${task.id}';
        await File(stagingPath).writeAsBytes(List<int>.filled(40, 1));

        final startBytesSeen = <int>[];
        final downloadStarted = Completer<void>();
        var firstCall = true;
        final client = _FakeAgentClient(
          host: _testHost,
          onDownload: (_, cancelToken) async {
            if (firstCall) {
              firstCall = false;
              downloadStarted.complete();
              await cancelToken.whenCancel;
              throw DioException(
                requestOptions: RequestOptions(path: '/content'),
                type: DioExceptionType.cancel,
              );
            }
          },
          onDownloadWithStart: (localFile, startByte) async {
            startBytesSeen.add(startByte);
            if (!firstCall) {
              await localFile.writeAsBytes(List<int>.filled(100, 2));
            }
          },
        );

        final container = ProviderContainer(
          overrides: [
            transferQueueProvider.overrideWith(
              () => TransferQueueNotifier(
                clientFactory: (host, {deviceToken}) => client,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(transferQueueProvider.notifier);
        notifier.enqueue(task);

        await downloadStarted.future;
        notifier.pause(task.id);

        await _waitUntil(
          () =>
              container
                  .read(transferQueueProvider)
                  .firstWhere((x) => x.id == task.id)
                  .status ==
              TransferStatus.paused,
        );

        await notifier.retry(task.id);

        await _waitUntil(() {
          final t = container
              .read(transferQueueProvider)
              .firstWhere((x) => x.id == task.id);
          return t.status == TransferStatus.completed ||
              t.status == TransferStatus.failed;
        });

        final finalTask = container
            .read(transferQueueProvider)
            .firstWhere((t) => t.id == task.id);
        expect(finalTask.status, TransferStatus.completed);
        // Both the original attempt and the retry should resume from byte 40
        // (the length of the partial file written before either attempt).
        expect(startBytesSeen, everyElement(40));
      },
    );
  });

  // ---------------------------------------------------------------------
  // Bug 2 — _runUpload streams chunks from disk on demand (no full-file
  // in-memory buffer) and the chunks reconstruct the original file.
  // ---------------------------------------------------------------------
  group('upload chunk streaming', () {
    test('uploaded chunks reconstruct the source file in order', () async {
      final dir = await Directory.systemTemp.createTemp('upload_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/upload.bin');
      final bytes = Uint8List.fromList(
        List<int>.generate(250 * 1024, (i) => i % 256),
      );
      await file.writeAsBytes(bytes);

      final receivedChunks = <Uint8List>[];
      final client = _FakeAgentClient(
        host: _testHost,
        onUploadChunk: (data) async {
          receivedChunks.add(Uint8List.fromList(data));
        },
      );

      final container = ProviderContainer(
        overrides: [
          transferQueueProvider.overrideWith(
            () => TransferQueueNotifier(
              clientFactory: (host, {deviceToken}) => client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transferQueueProvider.notifier);
      final task = TransferTask.upload(
        localPath: file.path,
        remotePath: '/remote/upload.bin',
        host: _testHost,
      );
      notifier.enqueue(task);

      await _waitUntil(() {
        final t = container
            .read(transferQueueProvider)
            .firstWhere((x) => x.id == task.id);
        return t.status == TransferStatus.completed ||
            t.status == TransferStatus.failed;
      });

      final finalTask = container
          .read(transferQueueProvider)
          .firstWhere((t) => t.id == task.id);
      expect(finalTask.status, TransferStatus.completed);
      expect(finalTask.transferredBytes, bytes.length);

      // The agent's complete response reports the verified whole-file
      // SHA-256 (Wave H3); the fake client returns verified: true.
      expect(finalTask.verified, isTrue);
      expect(finalTask.sha256, '0' * 64);

      final reconstructed = BytesBuilder();
      for (final chunk in receivedChunks) {
        reconstructed.add(chunk);
      }
      expect(reconstructed.toBytes(), bytes);
    });

    test('a download never sets verified/sha256', () async {
      final dir = await Directory.systemTemp.createTemp('download_unverified_');
      addTearDown(() => dir.delete(recursive: true));
      final localPath = '${dir.path}/out.bin';

      final client = _FakeAgentClient(
        host: _testHost,
        onDownloadWithStart: (localFile, startByte) async {
          await localFile.writeAsBytes(List<int>.filled(10, 7));
        },
      );

      final container = ProviderContainer(
        overrides: [
          transferQueueProvider.overrideWith(
            () => TransferQueueNotifier(
              clientFactory: (host, {deviceToken}) => client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transferQueueProvider.notifier);
      final task = TransferTask.download(
        remotePath: '/remote/file.bin',
        localPath: localPath,
        host: _testHost,
      );
      notifier.enqueue(task);

      await _waitUntil(() {
        final t = container
            .read(transferQueueProvider)
            .firstWhere((x) => x.id == task.id);
        return t.status == TransferStatus.completed ||
            t.status == TransferStatus.failed;
      });

      final finalTask = container
          .read(transferQueueProvider)
          .firstWhere((t) => t.id == task.id);
      expect(finalTask.status, TransferStatus.completed);
      expect(finalTask.verified, isFalse);
      expect(finalTask.sha256, isNull);
    });
  });

  // ---------------------------------------------------------------------
  // PR-58 — persistence writes must not reorder stale snapshots
  // ---------------------------------------------------------------------
  group('queue persistence write ordering', () {
    test(
      'a second persist() while the first save() is still in flight waits '
      'for it, and its snapshot reflects the latest state (not stale)',
      () async {
        final store = _RecordingStore();
        // A client whose download never resolves, so the execution engine
        // (triggered as a side effect of enqueue()) can't itself generate
        // extra persist() calls (e.g. via a failed/completed transition)
        // that would make this test racy against unrelated behavior.
        final hangingClient = _FakeAgentClient(
          host: _testHost,
          onDownloadWithStart: (_, _) => Completer<void>().future,
        );
        final container = ProviderContainer(
          overrides: [
            transferQueueProvider.overrideWith(
              () => TransferQueueNotifier(
                clientFactory: (host, {deviceToken}) => hangingClient,
                store: store,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(transferQueueProvider.notifier);

        final gate = Completer<void>();
        store.gateNext = gate;

        final t1 = TransferTask.download(
          remotePath: '/a',
          localPath: '/tmp/a',
          host: _testHost,
        );
        notifier.enqueue(t1); // save() call #1 starts and hangs on `gate`

        final t2 = TransferTask.download(
          remotePath: '/b',
          localPath: '/tmp/b',
          host: _testHost,
        );
        notifier.enqueue(t2); // triggers further persist() calls behind #1

        await Future<void>.delayed(Duration.zero);
        expect(
          store.calls.length,
          1,
          reason:
              'nothing else should have been able to write while the '
              'first save() is still in flight',
        );

        gate.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        // The execution engine itself makes further persist() calls as a
        // side effect of running (e.g. marking a task "running"), so the
        // exact call count isn't pinned — what matters is (a) save() was
        // never re-entered while a previous call was still pending
        // (checked inside _RecordingStore itself) and (b) the final
        // on-disk state reflects both enqueued tasks, proving the last
        // write wasn't a stale snapshot that lost t2.
        expect(store.calls.length, greaterThanOrEqualTo(2));
        final finalIds = store.calls.last.map((j) => j['id']).toSet();
        expect(
          finalIds,
          containsAll(<String>{t1.id, t2.id}),
          reason: 'the final persisted state must include both tasks',
        );
      },
    );
  });
}

/// Records every save() call and its argument; [gateNext], if set, makes
/// the *next* call wait on that completer before resolving — used to force
/// a controlled overlap between two persist() calls. Fails the test
/// immediately if a call starts while a previous one is still pending,
/// which is exactly the race PR-58's fix (the write chain) must prevent.
class _RecordingStore extends TransferQueueStore {
  final List<List<Map<String, dynamic>>> calls = [];
  Completer<void>? gateNext;
  bool _saving = false;

  @override
  Future<void> save(List<Map<String, dynamic>> tasks) async {
    if (_saving) {
      fail('save() was re-entered while a previous call was still pending');
    }
    _saving = true;
    calls.add(tasks);
    final gate = gateNext;
    gateNext = null;
    if (gate != null) await gate.future;
    _saving = false;
  }
}

// ---------------------------------------------------------------------------
// Fake AgentClient
// ---------------------------------------------------------------------------

/// A minimal [AgentClient] subclass that overrides only the network-touching
/// methods exercised by [TransferQueueNotifier], so the queue logic can be
/// tested without real Dio/TLS/sockets.
class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({
    required Host host,
    this.onDownload,
    this.onDownloadWithStart,
    this.onUploadChunk,
    this.checksumOverride,
  }) : super(host);

  /// Called by [downloadFile]; receives the actual staging [File] (PR-24: a
  /// task-scoped path, not the bare destination) and the [CancelToken].
  final Future<void> Function(File localFile, CancelToken cancelToken)?
  onDownload;

  /// Called by [downloadFile]; receives the staging [File] and [startByte]
  /// for resume tests.
  final Future<void> Function(File localFile, int startByte)?
  onDownloadWithStart;

  final Future<void> Function(Uint8List data)? onUploadChunk;

  /// Overrides the default checksum behavior (hashing whatever bytes the
  /// last [downloadFile] call left on disk, i.e. "the download always
  /// verifies") — set this to force an integrity-check failure in a test.
  final Future<String> Function(String remotePath)? checksumOverride;

  File? _lastDownloadFile;

  @override
  Future<Entry> meta(String path) async {
    return Entry(name: 'file.bin', path: path, isDir: false, size: 100);
  }

  @override
  Future<void> downloadFile({
    required String remotePath,
    required File localFile,
    int startByte = 0,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _lastDownloadFile = localFile;
    if (onDownload != null) {
      await onDownload!(localFile, cancelToken ?? CancelToken());
    }
    if (onDownloadWithStart != null) {
      await onDownloadWithStart!(localFile, startByte);
    }
  }

  @override
  Future<String> checksum(String path, {String algo = 'sha256'}) async {
    if (checksumOverride != null) return checksumOverride!(path);
    final file = _lastDownloadFile;
    if (file == null || !await file.exists()) return '0' * 64;
    return hashFileSha256(file.path);
  }

  @override
  Future<UploadSession> openUploadSession({
    required String path,
    required int size,
    required String sha256Hex,
    required int chunkSize,
    bool overwrite = false,
  }) async {
    return UploadSession(
      id: 'session-1',
      path: path,
      size: size,
      chunkSize: chunkSize,
      totalChunks: planChunks(size, chunkSize: chunkSize).totalChunks,
      receivedChunks: const [],
      status: 'open',
    );
  }

  @override
  Future<UploadSession> getUploadSession(String id) async {
    return UploadSession(
      id: id,
      path: '/remote/file',
      size: 0,
      chunkSize: 4 * 1024 * 1024,
      totalChunks: 1,
      receivedChunks: const [],
      status: 'open',
    );
  }

  @override
  Future<void> uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required Uint8List data,
    required String contentRange,
    required String chunkSha256,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (onUploadChunk != null) {
      await onUploadChunk!(data);
    }
  }

  @override
  Future<UploadCompleteResult> completeUpload(String sessionId) async {
    return UploadCompleteResult(
      entry: Entry(name: 'file.bin', path: '/remote/file.bin', isDir: false),
      verified: true,
      sha256: '0' * 64,
    );
  }
}
