import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/pin_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pin / isPinned / unpin round-trip', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pinStoreProvider.future);
    final notifier = container.read(pinStoreProvider.notifier);

    expect(notifier.isPinned('h1', '/docs'), isFalse);

    await notifier.pin('h1', '/docs');
    expect(notifier.isPinned('h1', '/docs'), isTrue);

    await notifier.unpin('h1', '/docs');
    expect(notifier.isPinned('h1', '/docs'), isFalse);
  });

  test('pin is idempotent — no duplicates', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pinStoreProvider.future);
    final notifier = container.read(pinStoreProvider.notifier);

    await notifier.pin('h1', '/docs');
    await notifier.pin('h1', '/docs');

    expect(notifier.pinsForHost('h1'), hasLength(1));
  });

  test('pinsForHost scopes by hostId', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pinStoreProvider.future);
    final notifier = container.read(pinStoreProvider.notifier);

    await notifier.pin('h1', '/a');
    await notifier.pin('h1', '/b');
    await notifier.pin('h2', '/c');

    expect(notifier.pinsForHost('h1'), hasLength(2));
    expect(notifier.pinsForHost('h1'), containsAll(['/a', '/b']));
    expect(notifier.pinsForHost('h2'), hasLength(1));
    expect(notifier.pinsForHost('h2').first, equals('/c'));
  });

  test('persists across ProviderContainer restart', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(pinStoreProvider.future);
    await container.read(pinStoreProvider.notifier).pin('h1', '/persisted');

    // Simulate app restart with same prefs.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    await container2.read(pinStoreProvider.future);

    expect(
      container2.read(pinStoreProvider.notifier).isPinned('h1', '/persisted'),
      isTrue,
    );
  });

  test('one corrupt persisted entry is skipped instead of bricking pins '
      '(PR-54)', () async {
    SharedPreferences.setMockInitialValues({
      'offline_pins_v1': [
        jsonEncode(const Pin(hostId: 'h1', remotePath: '/a').toJson()),
        'not valid json',
        jsonEncode(const Pin(hostId: 'h2', remotePath: '/b').toJson()),
      ],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final pins = await container.read(pinStoreProvider.future);

    expect(pins, hasLength(2));
    expect(pins.map((p) => p.hostId), containsAll(<String>['h1', 'h2']));
  });
}
