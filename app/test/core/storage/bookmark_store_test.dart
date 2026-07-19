import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add / isBookmarked / remove round-trip', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Wait for the AsyncNotifier to initialise from SharedPreferences.
    await container.read(bookmarkStoreProvider.future);
    final notifier = container.read(bookmarkStoreProvider.notifier);

    const b = Bookmark(hostId: 'h1', remotePath: '/foo/bar.txt', tag: 'work');

    expect(notifier.isBookmarked('h1', '/foo/bar.txt'), isFalse);

    await notifier.addBookmark(b);
    expect(notifier.isBookmarked('h1', '/foo/bar.txt'), isTrue);
    expect(notifier.bookmarksForHost('h1'), hasLength(1));
    expect(notifier.bookmarksForHost('h1').first.tag, equals('work'));

    await notifier.removeBookmark('h1', '/foo/bar.txt');
    expect(notifier.isBookmarked('h1', '/foo/bar.txt'), isFalse);
    expect(notifier.allBookmarks(), isEmpty);
  });

  test('addBookmark replaces existing entry for the same path', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(bookmarkStoreProvider.future);
    final notifier = container.read(bookmarkStoreProvider.notifier);

    await notifier.addBookmark(
      const Bookmark(hostId: 'h1', remotePath: '/a', tag: 'old'),
    );
    await notifier.addBookmark(
      const Bookmark(hostId: 'h1', remotePath: '/a', tag: 'new'),
    );

    // Must update, not duplicate.
    expect(notifier.allBookmarks(), hasLength(1));
    expect(notifier.allBookmarks().first.tag, equals('new'));
  });

  test('bookmarksForHost scopes by hostId', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(bookmarkStoreProvider.future);
    final notifier = container.read(bookmarkStoreProvider.notifier);

    await notifier.addBookmark(const Bookmark(hostId: 'h1', remotePath: '/a'));
    await notifier.addBookmark(const Bookmark(hostId: 'h2', remotePath: '/b'));

    expect(notifier.bookmarksForHost('h1'), hasLength(1));
    expect(notifier.bookmarksForHost('h2'), hasLength(1));
    expect(notifier.allBookmarks(), hasLength(2));
  });

  test('one corrupt persisted entry is skipped instead of bricking bookmarks '
      '(PR-54)', () async {
    SharedPreferences.setMockInitialValues({
      'bookmarks_v1': [
        jsonEncode(const Bookmark(hostId: 'h1', remotePath: '/a').toJson()),
        'not valid json',
        jsonEncode(const Bookmark(hostId: 'h2', remotePath: '/b').toJson()),
      ],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final bookmarks = await container.read(bookmarkStoreProvider.future);

    expect(bookmarks, hasLength(2));
    expect(bookmarks.map((b) => b.hostId), containsAll(<String>['h1', 'h2']));
  });
}
