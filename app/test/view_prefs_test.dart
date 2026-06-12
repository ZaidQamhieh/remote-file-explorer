import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ViewPrefs persistence tests — exercises SharedPreferences round-trips for
// per-host list/grid mode, density, and sort order, mirroring the patterns in
// host_store_test.dart / favorites tests (mock SharedPreferences, fresh
// ProviderContainer per test, restart simulated by reading via a new
// container/notifier instance).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewPrefs defaults', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to list view, comfortable density, name ascending sort',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final prefs = await container.read(viewPrefsProvider.future);
      expect(prefs.gridViewFor('host1'), isFalse);
      expect(prefs.density, EntryDensity.comfortable);
      expect(prefs.sort, const SortOrder());
    });
  });

  group('Per-host grid view persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setGridView persists per host and survives restart', () async {
      final container1 = ProviderContainer();
      await container1.read(viewPrefsProvider.future);
      await container1
          .read(viewPrefsProvider.notifier)
          .setGridView('host1', true);

      final prefs1 = await container1.read(viewPrefsProvider.future);
      expect(prefs1.gridViewFor('host1'), isTrue);
      expect(prefs1.gridViewFor('host2'), isFalse);
      container1.dispose();

      // Simulate restart: fresh container reads the same SharedPreferences
      // backing store.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final prefs2 = await container2.read(viewPrefsProvider.future);
      expect(prefs2.gridViewFor('host1'), isTrue);
      expect(prefs2.gridViewFor('host2'), isFalse);
    });

    test('grid view choices for different hosts are independent', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(viewPrefsProvider.future);

      final notifier = container.read(viewPrefsProvider.notifier);
      await notifier.setGridView('host1', true);
      await notifier.setGridView('host2', false);

      final prefs = container.read(viewPrefsProvider).valueOrNull!;
      expect(prefs.gridViewFor('host1'), isTrue);
      expect(prefs.gridViewFor('host2'), isFalse);
    });
  });

  group('Density persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setDensity persists and survives restart', () async {
      final container1 = ProviderContainer();
      await container1.read(viewPrefsProvider.future);
      await container1
          .read(viewPrefsProvider.notifier)
          .setDensity(EntryDensity.compact);

      final prefs1 = await container1.read(viewPrefsProvider.future);
      expect(prefs1.density, EntryDensity.compact);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final prefs2 = await container2.read(viewPrefsProvider.future);
      expect(prefs2.density, EntryDensity.compact);
    });
  });

  group('Sort order persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setSort persists field and direction, survives restart', () async {
      final container1 = ProviderContainer();
      await container1.read(viewPrefsProvider.future);
      await container1.read(viewPrefsProvider.notifier).setSort(
            const SortOrder(field: SortField.size, ascending: false),
          );

      final prefs1 = await container1.read(viewPrefsProvider.future);
      expect(prefs1.sort.field, SortField.size);
      expect(prefs1.sort.ascending, isFalse);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final prefs2 = await container2.read(viewPrefsProvider.future);
      expect(prefs2.sort.field, SortField.size);
      expect(prefs2.sort.ascending, isFalse);
    });

    test('SortOrder equality compares field and direction', () {
      const a = SortOrder(field: SortField.date, ascending: false);
      const b = SortOrder(field: SortField.date, ascending: false);
      const c = SortOrder(field: SortField.date, ascending: true);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('SortOrder.copyWith flips direction independently of field', () {
      const original = SortOrder(field: SortField.name, ascending: true);
      final flipped = original.copyWith(ascending: false);
      expect(flipped.field, SortField.name);
      expect(flipped.ascending, isFalse);
    });
  });
}
