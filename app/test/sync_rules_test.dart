import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_file_explorer/core/storage/sync_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncRule JSON', () {
    test('roundtrip without lastSync', () {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      final json = rule.toJson();
      final restored = SyncRule.fromJson(json);
      expect(restored.id, '1');
      expect(restored.hostId, 'h1');
      expect(restored.remotePath, '/photos');
      expect(restored.localPath, '/sdcard/sync/photos');
      expect(restored.enabled, true);
      expect(restored.lastSync, isNull);
    });

    test('roundtrip with lastSync', () {
      final now = DateTime.utc(2025, 6, 15, 12, 30);
      final rule = SyncRule(
        id: '2',
        hostId: 'h2',
        remotePath: '/docs',
        localPath: '/sdcard/sync/docs',
        enabled: false,
        lastSync: now,
      );
      final json = rule.toJson();
      final restored = SyncRule.fromJson(json);
      expect(restored.enabled, false);
      expect(restored.lastSync, now);
    });

    test('defaults enabled to true when missing', () {
      final json = {
        'id': '3',
        'hostId': 'h3',
        'remotePath': '/music',
        'localPath': '/sdcard/sync/music',
      };
      final rule = SyncRule.fromJson(json);
      expect(rule.enabled, true);
    });
  });

  group('SyncRule.copyWith', () {
    test('toggles enabled', () {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/a',
        localPath: '/b',
      );
      final toggled = rule.copyWith(enabled: false);
      expect(toggled.enabled, false);
      expect(toggled.id, rule.id);
      expect(toggled.remotePath, rule.remotePath);
    });

    test('updates lastSync', () {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/a',
        localPath: '/b',
      );
      final now = DateTime.now();
      final updated = rule.copyWith(lastSync: now);
      expect(updated.lastSync, now);
    });
  });

  group('SyncRuleStore', () {
    late SyncRuleStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = SyncRuleStore(prefs);
    });

    test('starts empty', () {
      expect(store.listRules(), isEmpty);
    });

    test('saveRule adds a rule', () async {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      await store.saveRule(rule);
      final rules = store.listRules();
      expect(rules, hasLength(1));
      expect(rules.first.id, '1');
    });

    test('saveRule updates existing rule by id', () async {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      await store.saveRule(rule);
      final updated = rule.copyWith(enabled: false);
      await store.saveRule(updated);
      final rules = store.listRules();
      expect(rules, hasLength(1));
      expect(rules.first.enabled, false);
    });

    test('deleteRule removes by id', () async {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      await store.saveRule(rule);
      await store.deleteRule('1');
      expect(store.listRules(), isEmpty);
    });

    test('deleteRule is no-op for unknown id', () async {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      await store.saveRule(rule);
      await store.deleteRule('unknown');
      expect(store.listRules(), hasLength(1));
    });

    test('persists across store instances', () async {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      await store.saveRule(rule);

      // Create a new store from the same prefs.
      final prefs = await SharedPreferences.getInstance();
      final store2 = SyncRuleStore(prefs);
      final rules = store2.listRules();
      expect(rules, hasLength(1));
      expect(rules.first.remotePath, '/photos');
    });

    test('multiple rules for different hosts', () async {
      await store.saveRule(
        SyncRule(
          id: '1',
          hostId: 'h1',
          remotePath: '/photos',
          localPath: '/sdcard/sync/photos',
        ),
      );
      await store.saveRule(
        SyncRule(
          id: '2',
          hostId: 'h2',
          remotePath: '/docs',
          localPath: '/sdcard/sync/docs',
        ),
      );
      expect(store.listRules(), hasLength(2));
    });

    test('one corrupt persisted entry is skipped instead of bricking sync '
        'rules (PR-54)', () async {
      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/photos',
        localPath: '/sdcard/sync/photos',
      );
      await store.saveRule(rule);

      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getStringList('rfe_sync_rules_v1')!.toList()
            ..add('not valid json');
      await prefs.setStringList('rfe_sync_rules_v1', raw);

      final rules = store.listRules();
      expect(rules, hasLength(1));
      expect(rules.first.id, '1');
    });
  });
}
