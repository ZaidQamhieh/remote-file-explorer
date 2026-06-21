import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/type_treemap_screen.dart';

void main() {
  group('extensionOf', () {
    test('extracts extension with dot', () {
      expect(extensionOf('photo.jpg'), '.jpg');
    });

    test('extracts last extension for double extensions', () {
      expect(extensionOf('archive.tar.gz'), '.gz');
    });

    test('returns empty for no extension', () {
      expect(extensionOf('Makefile'), '');
    });

    test('returns empty for dot-only name', () {
      expect(extensionOf('.'), '');
    });

    test('returns empty for hidden file without ext', () {
      expect(extensionOf('.gitignore'), '');
    });

    test('handles hidden file with extension', () {
      expect(extensionOf('.env.local'), '.local');
    });

    test('returns empty for trailing dot', () {
      expect(extensionOf('file.'), '');
    });
  });

  group('categoryFor', () {
    test('classifies image extensions', () {
      expect(categoryFor('.jpg'), FileCategory.image);
      expect(categoryFor('.png'), FileCategory.image);
      expect(categoryFor('.webp'), FileCategory.image);
    });

    test('classifies video extensions', () {
      expect(categoryFor('.mp4'), FileCategory.video);
      expect(categoryFor('.mkv'), FileCategory.video);
    });

    test('classifies audio extensions', () {
      expect(categoryFor('.mp3'), FileCategory.audio);
      expect(categoryFor('.flac'), FileCategory.audio);
    });

    test('classifies document extensions', () {
      expect(categoryFor('.pdf'), FileCategory.document);
      expect(categoryFor('.txt'), FileCategory.document);
    });

    test('classifies archive extensions', () {
      expect(categoryFor('.zip'), FileCategory.archive);
      expect(categoryFor('.tar'), FileCategory.archive);
    });

    test('classifies code extensions', () {
      expect(categoryFor('.dart'), FileCategory.code);
      expect(categoryFor('.go'), FileCategory.code);
      expect(categoryFor('.py'), FileCategory.code);
    });

    test('returns other for unknown extensions', () {
      expect(categoryFor('.xyz'), FileCategory.other);
      expect(categoryFor('.abc'), FileCategory.other);
    });

    test('is case-insensitive', () {
      expect(categoryFor('.JPG'), FileCategory.image);
      expect(categoryFor('.Dart'), FileCategory.code);
    });
  });

  group('aggregateByExtension', () {
    test('empty list gives zero totals', () {
      final r = aggregateByExtension([]);
      expect(r.totalSize, 0);
      expect(r.totalFiles, 0);
      expect(r.sizeByExt, isEmpty);
      expect(r.countByExt, isEmpty);
    });

    test('single file', () {
      final r = aggregateByExtension([(ext: '.jpg', size: 1024)]);
      expect(r.totalFiles, 1);
      expect(r.totalSize, 1024);
      expect(r.sizeByExt['.jpg'], 1024);
      expect(r.countByExt['.jpg'], 1);
    });

    test('multiple files same extension aggregate correctly', () {
      final r = aggregateByExtension([
        (ext: '.jpg', size: 100),
        (ext: '.jpg', size: 200),
        (ext: '.jpg', size: 300),
      ]);
      expect(r.totalFiles, 3);
      expect(r.totalSize, 600);
      expect(r.sizeByExt['.jpg'], 600);
      expect(r.countByExt['.jpg'], 3);
    });

    test('different extensions are grouped separately', () {
      final r = aggregateByExtension([
        (ext: '.jpg', size: 100),
        (ext: '.png', size: 200),
        (ext: '.mp4', size: 5000),
        (ext: '.jpg', size: 50),
      ]);
      expect(r.totalFiles, 4);
      expect(r.totalSize, 5350);
      expect(r.sizeByExt['.jpg'], 150);
      expect(r.countByExt['.jpg'], 2);
      expect(r.sizeByExt['.png'], 200);
      expect(r.countByExt['.png'], 1);
      expect(r.sizeByExt['.mp4'], 5000);
      expect(r.countByExt['.mp4'], 1);
    });

    test('files without extension grouped as "(no ext)"', () {
      final r = aggregateByExtension([
        (ext: '', size: 50),
        (ext: '', size: 30),
      ]);
      expect(r.sizeByExt['(no ext)'], 80);
      expect(r.countByExt['(no ext)'], 2);
    });

    test('extensions are lowercased', () {
      final r = aggregateByExtension([
        (ext: '.JPG', size: 100),
        (ext: '.jpg', size: 200),
      ]);
      expect(r.sizeByExt['.jpg'], 300);
      expect(r.countByExt['.jpg'], 2);
    });

    test('zero-size files are counted', () {
      final r = aggregateByExtension([
        (ext: '.txt', size: 0),
        (ext: '.txt', size: 0),
      ]);
      expect(r.totalFiles, 2);
      expect(r.totalSize, 0);
      expect(r.countByExt['.txt'], 2);
      expect(r.sizeByExt['.txt'], 0);
    });
  });
}
