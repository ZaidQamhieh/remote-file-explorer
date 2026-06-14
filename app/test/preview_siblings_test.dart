import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/features/preview/preview.dart';

// Unit tests for the pure previewable-sibling filtering + start-index logic
// that drives whether `openPreview` pushes a swipeable pager and where it
// starts. No widgets / no host — just the function contract.

Entry _file(String name, {String? mime}) =>
    Entry(name: name, path: '/dir/$name', isDir: false, mimeType: mime);

Entry _dir(String name) => Entry(name: name, path: '/dir/$name', isDir: true);

void main() {
  group('previewableSiblings', () {
    test('filters to previewable entries and finds the tapped index', () {
      final img1 = _file('a.png');
      final doc = _file('readme.txt');
      final dir = _dir('sub');
      final blob = _file('data.bin'); // not previewable
      final img2 = _file('b.jpg');

      final listing = [img1, doc, dir, blob, img2];

      final r = previewableSiblings(listing, doc);

      // Directory + unknown blob dropped; order preserved.
      expect(r.entries.map((e) => e.name), ['a.png', 'readme.txt', 'b.jpg']);
      expect(r.index, 1); // readme.txt is the 2nd previewable entry
    });

    test('returns index -1 when the entry is not previewable', () {
      final blob = _file('data.bin');
      final img = _file('a.png');
      final r = previewableSiblings([img, blob], blob);
      expect(r.index, -1);
    });

    test('matches by path, not identity (re-fetched copy of tapped entry)', () {
      final original = _file('a.png');
      final refetched = Entry(
        name: 'a.png',
        path: '/dir/a.png',
        isDir: false,
        size: 1234, // different instance, richer metadata, same path
      );
      final r = previewableSiblings([original, _file('b.jpg')], refetched);
      expect(r.index, 0);
    });

    test('empty listing yields empty + index -1', () {
      final r = previewableSiblings(const [], _file('a.png'));
      expect(r.entries, isEmpty);
      expect(r.index, -1);
    });
  });
}
