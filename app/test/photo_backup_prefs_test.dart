import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/photo_backup/photo_backup_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save/load round-trips all fields', () async {
    final store = await PhotoBackupStore.open();
    const prefs = PhotoBackupPrefs(
      enabled: true,
      hostId: 'h1',
      deviceName: "Zaid's Phone",
      wifiOnly: false,
      chargingOnly: true,
      albumIds: ['alb-1', 'alb-2'],
    );
    await store.save(prefs);

    final reopened = await PhotoBackupStore.open();
    final loaded = reopened.load();
    expect(loaded.enabled, isTrue);
    expect(loaded.hostId, 'h1');
    expect(loaded.deviceName, "Zaid's Phone");
    expect(loaded.wifiOnly, isFalse);
    expect(loaded.chargingOnly, isTrue);
    expect(loaded.albumIds, ['alb-1', 'alb-2']);
    expect(loaded.isConfigured, isTrue);
  });

  test('defaults are sane when nothing is stored', () async {
    final store = await PhotoBackupStore.open();
    final p = store.load();
    expect(p.enabled, isFalse);
    expect(p.wifiOnly, isTrue); // wifi-only on by default
    expect(p.albumIds, isEmpty); // empty = all photos (backward compatible)
    expect(p.isConfigured, isFalse);
  });

  test('done-ids accumulate and reset', () async {
    final store = await PhotoBackupStore.open();
    await store.markDone(['a', 'b']);
    await store.markDone(['b', 'c']);
    expect(store.doneIds(), {'a', 'b', 'c'});
    await store.resetDone();
    final reopened = await PhotoBackupStore.open();
    expect(reopened.doneIds(), isEmpty);
  });

  group('taskToAsset (PR-30)', () {
    test('round-trips through a fresh store instance', () async {
      final store = await PhotoBackupStore.open();
      await store.saveTaskToAsset({'task-1': 'asset-1', 'task-2': 'asset-2'});

      final reopened = await PhotoBackupStore.open();
      expect(reopened.loadTaskToAsset(), {
        'task-1': 'asset-1',
        'task-2': 'asset-2',
      });
    });

    test('is empty when nothing was ever saved', () async {
      final store = await PhotoBackupStore.open();
      expect(store.loadTaskToAsset(), isEmpty);
    });

    test('corrupt stored JSON is treated as empty, not a crash', () async {
      SharedPreferences.setMockInitialValues({
        'rfe_photo_backup_task_to_asset': 'not valid json{{{',
      });
      final store = await PhotoBackupStore.open();
      expect(store.loadTaskToAsset(), isEmpty);
    });
  });
}
