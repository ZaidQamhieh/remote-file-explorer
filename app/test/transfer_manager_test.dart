import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/transfers/transfer_manager.dart';
import 'package:remote_file_explorer/features/transfers/transfer_speed.dart';
import 'package:remote_file_explorer/features/transfers/transfer_state.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

void main() {
  // -------------------------------------------------------------------------
  // computeSpeedEta — pure function
  // -------------------------------------------------------------------------
  group('computeSpeedEta', () {
    test('zero samples → unknown', () {
      final r = computeSpeedEta(const [], totalBytes: 1000);
      expect(r.bytesPerSecond, isNull);
      expect(r.etaSeconds, isNull);
    });

    test('one sample → unknown', () {
      final r = computeSpeedEta(const [(0, 100)], totalBytes: 1000);
      expect(r.bytesPerSecond, isNull);
      expect(r.etaSeconds, isNull);
    });

    test('steady rate computes speed and ETA', () {
      // 1000 bytes over 1000ms = 1000 B/s; 2000 bytes remain of a 3000 total.
      final r = computeSpeedEta(
        const [(0, 0), (500, 500), (1000, 1000)],
        totalBytes: 3000,
      );
      expect(r.bytesPerSecond, closeTo(1000, 0.001));
      expect(r.etaSeconds, closeTo(2.0, 0.001));
    });

    test('uses whole-window span, not just the last gap', () {
      // 3000 bytes over 3000ms = 1000 B/s even though the last gap differs.
      final r = computeSpeedEta(
        const [(0, 0), (1000, 1000), (3000, 3000)],
        totalBytes: null,
      );
      expect(r.bytesPerSecond, closeTo(1000, 0.001));
      expect(r.etaSeconds, isNull, reason: 'unknown total → no ETA');
    });

    test('unknown total → speed but no ETA', () {
      final r = computeSpeedEta(const [(0, 0), (1000, 2000)]);
      expect(r.bytesPerSecond, closeTo(2000, 0.001));
      expect(r.etaSeconds, isNull);
    });

    test('zero total → no ETA', () {
      final r = computeSpeedEta(const [(0, 0), (1000, 2000)], totalBytes: 0);
      expect(r.bytesPerSecond, closeTo(2000, 0.001));
      expect(r.etaSeconds, isNull);
    });

    test('stalled (flat bytes) → speed 0, no ETA', () {
      final r = computeSpeedEta(
        const [(0, 500), (1000, 500), (2000, 500)],
        totalBytes: 1000,
      );
      expect(r.bytesPerSecond, 0);
      expect(r.etaSeconds, isNull);
    });

    test('no elapsed time across window → unknown', () {
      final r =
          computeSpeedEta(const [(0, 100), (0, 200)], totalBytes: 1000);
      expect(r.bytesPerSecond, isNull);
      expect(r.etaSeconds, isNull);
    });

    test('past-total bytes → ETA clamps to 0', () {
      final r =
          computeSpeedEta(const [(0, 900), (1000, 1100)], totalBytes: 1000);
      expect(r.etaSeconds, 0);
    });

    test('labels render correctly', () {
      final r = computeSpeedEta(
        const [(0, 0), (1000, 12 * 1024 * 1024)],
        totalBytes: 12 * 1024 * 1024 + 90 * 12 * 1024 * 1024,
      );
      expect(r.speedLabel, '12.0 MB/s');
      // ~90s remaining at 12 MB/s.
      expect(r.etaLabel, '~1m 30s');
    });

    test('unknown reading yields null labels', () {
      expect(SpeedEta.unknown.speedLabel, isNull);
      expect(SpeedEta.unknown.etaLabel, isNull);
    });
  });

  group('formatDuration', () {
    test('seconds', () => expect(formatDuration(45), '45s'));
    test('minutes + seconds', () => expect(formatDuration(150), '2m 30s'));
    test('exact minutes', () => expect(formatDuration(120), '2m'));
    test('hours + minutes', () => expect(formatDuration(3900), '1h 5m'));
    test('exact hours', () => expect(formatDuration(7200), '2h'));
  });

  // -------------------------------------------------------------------------
  // groupTransfers — section grouping
  // -------------------------------------------------------------------------
  group('groupTransfers', () {
    TransferTask task(TransferStatus status) {
      var t = TransferTask.download(
        remotePath: '/r/${status.name}',
        localPath: '/l/${status.name}',
        host: _testHost,
      );
      // copyWith to land on the desired status (factory always starts queued).
      return t = t.copyWith(status: status);
    }

    test('maps each status to the right group', () {
      final tasks = [
        task(TransferStatus.running),
        task(TransferStatus.paused),
        task(TransferStatus.queued),
        task(TransferStatus.completed),
        task(TransferStatus.failed),
      ];
      final groups = groupTransfers(tasks);

      // running + paused fold into active.
      expect(groups[TransferGroup.active]!.length, 2);
      expect(groups[TransferGroup.queued]!.length, 1);
      expect(groups[TransferGroup.done]!.length, 1);
      expect(groups[TransferGroup.failed]!.length, 1);
    });

    test('empty input → all groups present but empty', () {
      final groups = groupTransfers(const []);
      expect(groups.keys.toSet(), TransferGroup.values.toSet());
      for (final g in TransferGroup.values) {
        expect(groups[g], isEmpty);
      }
    });

    test('preserves order within a group', () {
      final a = task(TransferStatus.running);
      final b = task(TransferStatus.running);
      final groups = groupTransfers([a, b]);
      expect(groups[TransferGroup.active]!.map((t) => t.id), [a.id, b.id]);
    });
  });

  // -------------------------------------------------------------------------
  // reenqueuableCopy — undo helper preserves the transfer intent with a fresh
  // queued id.
  // -------------------------------------------------------------------------
  group('reenqueuableCopy', () {
    test('upload copy preserves paths/host/overwrite, resets status + id', () {
      final original = TransferTask.upload(
        localPath: '/l/up.bin',
        remotePath: '/r/up.bin',
        host: _testHost,
        overwrite: true,
      ).copyWith(
        status: TransferStatus.failed,
        transferredBytes: 500,
        totalBytes: 1000,
      );

      final copy = reenqueuableCopy(original);
      expect(copy.id, isNot(original.id));
      expect(copy.kind, TransferKind.upload);
      expect(copy.localPath, '/l/up.bin');
      expect(copy.remotePath, '/r/up.bin');
      expect(copy.host.id, _testHost.id);
      expect(copy.overwrite, isTrue);
      expect(copy.status, TransferStatus.queued);
      expect(copy.transferredBytes, 0);
    });

    test('download copy preserves paths/host, resets status + id', () {
      final original = TransferTask.download(
        remotePath: '/r/down.bin',
        localPath: '/l/down.bin',
        host: _testHost,
      ).copyWith(status: TransferStatus.completed);

      final copy = reenqueuableCopy(original);
      expect(copy.id, isNot(original.id));
      expect(copy.kind, TransferKind.download);
      expect(copy.remotePath, '/r/down.bin');
      expect(copy.localPath, '/l/down.bin');
      expect(copy.status, TransferStatus.queued);
    });
  });

  // -------------------------------------------------------------------------
  // remove → undo re-enqueues into the live queue.
  // -------------------------------------------------------------------------
  group('remove + undo via the queue notifier', () {
    test('removing then re-enqueuing a copy puts the task back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(transferQueueProvider.notifier);

      // A failed download already in the queue (no network → never auto-runs).
      final task = TransferTask.download(
        remotePath: '/r/file.bin',
        localPath: '/l/file.bin',
        host: _testHost,
      ).copyWith(status: TransferStatus.failed, error: 'boom');

      // Seed the queue directly via enqueue then mark failed isn't possible
      // without running; instead capture the removal/undo contract on a task
      // we put in and take out.
      notifier.enqueue(task);
      expect(
        container.read(transferQueueProvider).any((t) => t.id == task.id),
        isTrue,
      );

      // Capture before removal (what the snackbar's Undo closure does).
      final captured = container
          .read(transferQueueProvider)
          .firstWhere((t) => t.id == task.id);
      notifier.remove(captured.id);
      expect(
        container.read(transferQueueProvider).any((t) => t.id == captured.id),
        isFalse,
        reason: 'task is gone after remove',
      );

      // Undo: re-enqueue an equivalent copy.
      notifier.enqueue(reenqueuableCopy(captured));
      final queue = container.read(transferQueueProvider);
      expect(
        queue.any((t) =>
            t.remotePath == captured.remotePath &&
            t.localPath == captured.localPath),
        isTrue,
        reason: 'an equivalent task is back in the queue after undo',
      );
    });
  });
}
