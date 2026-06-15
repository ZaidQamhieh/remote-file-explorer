import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/batch_rename.dart';

void main() {
  group('computeBatchRenames — pattern', () {
    test('appends a zero-padded sequence and preserves extensions', () {
      final out = computeBatchRenames(
        names: ['a.jpg', 'b.png', 'c.gif'],
        mode: BatchRenameMode.pattern,
        base: 'Trip',
      );
      expect(out, ['Trip 1.jpg', 'Trip 2.png', 'Trip 3.gif']);
    });

    test('pads to the width of the largest index', () {
      final names = List.generate(12, (i) => 'p$i.jpg');
      final out = computeBatchRenames(
        names: names,
        mode: BatchRenameMode.pattern,
        base: 'Trip',
      );
      expect(out.first, 'Trip 01.jpg');
      expect(out.last, 'Trip 12.jpg');
    });

    test('substitutes the {n} placeholder when present', () {
      final out = computeBatchRenames(
        names: ['x.txt', 'y.txt'],
        mode: BatchRenameMode.pattern,
        base: 'IMG_{n}_final',
        startNumber: 5,
      );
      expect(out, ['IMG_5_final.txt', 'IMG_6_final.txt']);
    });

    test('extensionless names get no spurious dot', () {
      final out = computeBatchRenames(
        names: ['README', 'LICENSE'],
        mode: BatchRenameMode.pattern,
        base: 'doc',
      );
      expect(out, ['doc 1', 'doc 2']);
    });
  });

  group('computeBatchRenames — find/replace', () {
    test('replaces all occurrences in each name', () {
      final out = computeBatchRenames(
        names: ['IMG_001.jpg', 'IMG_002.jpg'],
        mode: BatchRenameMode.findReplace,
        find: 'IMG',
        replace: 'Photo',
      );
      expect(out, ['Photo_001.jpg', 'Photo_002.jpg']);
    });

    test('empty find leaves names unchanged', () {
      final names = ['a.txt', 'b.txt'];
      final out = computeBatchRenames(
        names: names,
        mode: BatchRenameMode.findReplace,
        find: '',
        replace: 'x',
      );
      expect(out, names);
    });
  });

  group('splitNameExt', () {
    test('splits a normal name', () {
      final r = splitNameExt('photo.jpg');
      expect(r.stem, 'photo');
      expect(r.ext, '.jpg');
    });
    test('treats a dotfile as all-stem', () {
      expect(splitNameExt('.bashrc').ext, '');
    });
  });
}
