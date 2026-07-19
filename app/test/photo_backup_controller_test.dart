import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/photo_backup/photo_backup_controller.dart';
import 'package:remote_file_explorer/features/photo_backup/photo_backup_prefs.dart';
import 'package:remote_file_explorer/features/transfers/transfer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// `onTasks` never touches `ref`, so a throwaway container's `Ref` is
  /// enough to construct the controller under test.
  Ref buildRef() {
    final refProvider = Provider<Ref>((ref) => ref);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(refProvider);
  }

  test('a completion recorded after a simulated restart still marks the '
      'asset done — the task→asset mapping survives via the store, not '
      'just the (now-fresh) controller instance\'s memory (PR-30)', () async {
    final task = TransferTask.upload(
      localPath: '/local/asset-1.jpg',
      remotePath: '/remote/asset-1.jpg',
      host: _testHost,
    );

    // Simulate a PRIOR controller instance (before the "restart") having
    // enqueued this upload and persisted its mapping.
    final priorStore = await PhotoBackupStore.open();
    await priorStore.saveTaskToAsset({task.id: 'asset-1'});

    // A brand new controller instance — its in-memory cache starts empty,
    // same as after a process restart.
    final controller = PhotoBackupController(buildRef());

    final completedTask = task.copyWith(status: TransferStatus.completed);
    await controller.onTasks([completedTask]);

    final store = await PhotoBackupStore.open();
    expect(store.doneIds(), contains('asset-1'));
    expect(store.loadTaskToAsset(), isNot(contains(task.id)));
  });

  test(
    'a failed task is forgotten (not marked done) so it retries next run',
    () async {
      final task = TransferTask.upload(
        localPath: '/local/asset-1.jpg',
        remotePath: '/remote/asset-1.jpg',
        host: _testHost,
      );
      final priorStore = await PhotoBackupStore.open();
      await priorStore.saveTaskToAsset({task.id: 'asset-1'});

      final controller = PhotoBackupController(buildRef());
      final failedTask = task.copyWith(status: TransferStatus.failed);

      await controller.onTasks([failedTask]);

      final store = await PhotoBackupStore.open();
      expect(store.doneIds(), isNot(contains('asset-1')));
      expect(store.loadTaskToAsset(), isNot(contains(task.id)));
    },
  );

  test('an unrelated task id in the queue is ignored', () async {
    final controller = PhotoBackupController(buildRef());
    final task = TransferTask.upload(
      localPath: '/local/other.jpg',
      remotePath: '/remote/other.jpg',
      host: _testHost,
    );
    final completedTask = task.copyWith(status: TransferStatus.completed);

    await controller.onTasks([completedTask]);

    final store = await PhotoBackupStore.open();
    expect(store.doneIds(), isEmpty);
  });
}
