import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/recent_searches.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Future<void> ready() async {
    container.listen(recentSearchesProvider, (_, _) {});
    await _waitUntil(
        () => container.read(recentSearchesProvider).hasValue);
  }

  test('starts empty', () async {
    await ready();
    expect(container.read(recentSearchesProvider).valueOrNull, isEmpty);
  });

  test('record adds a query to the front', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.record('foo');
    await notifier.record('bar');

    expect(
        container.read(recentSearchesProvider).valueOrNull, ['bar', 'foo']);
  });

  test('recording an existing query moves it to the front (dedup)', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.record('foo');
    await notifier.record('bar');
    await notifier.record('foo');

    expect(
        container.read(recentSearchesProvider).valueOrNull, ['foo', 'bar']);
  });

  test('empty/whitespace queries are not recorded', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.record('');
    await notifier.record('   ');

    expect(container.read(recentSearchesProvider).valueOrNull, isEmpty);
  });

  test('queries are trimmed before recording', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.record('  foo  ');

    expect(container.read(recentSearchesProvider).valueOrNull, ['foo']);
  });

  test('list is capped at kMaxRecentSearches distinct entries', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    for (var i = 0; i < kMaxRecentSearches + 5; i++) {
      await notifier.record('query$i');
    }

    final list = container.read(recentSearchesProvider).valueOrNull!;
    expect(list, hasLength(kMaxRecentSearches));
    // Most recent first.
    expect(list.first, 'query${kMaxRecentSearches + 4}');
    // Oldest entries were evicted.
    expect(list.contains('query0'), isFalse);
  });

  test('remove deletes a single query', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.record('foo');
    await notifier.record('bar');
    await notifier.remove('foo');

    expect(container.read(recentSearchesProvider).valueOrNull, ['bar']);
  });

  test('clear empties the list', () async {
    await ready();
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.record('foo');
    await notifier.record('bar');
    await notifier.clear();

    expect(container.read(recentSearchesProvider).valueOrNull, isEmpty);
  });

  test('persists across instances via SharedPreferences', () async {
    await ready();
    await container.read(recentSearchesProvider.notifier).record('foo');

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    container2.listen(recentSearchesProvider, (_, _) {});
    await _waitUntil(
        () => container2.read(recentSearchesProvider).hasValue);

    expect(container2.read(recentSearchesProvider).valueOrNull, ['foo']);
  });
}
