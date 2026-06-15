import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/meta_sheet.dart';

void main() {
  group('isExtractableArchive', () {
    test('recognises supported formats (case-insensitive)', () {
      expect(isExtractableArchive('photos.zip'), isTrue);
      expect(isExtractableArchive('PHOTOS.ZIP'), isTrue);
      expect(isExtractableArchive('bundle.tar.gz'), isTrue);
      expect(isExtractableArchive('bundle.TGZ'), isTrue);
    });

    test('rejects non-archives and unsupported formats', () {
      expect(isExtractableArchive('notes.txt'), isFalse);
      expect(isExtractableArchive('archive.rar'), isFalse);
      expect(isExtractableArchive('archive.7z'), isFalse);
      expect(isExtractableArchive('zip'), isFalse);
      expect(isExtractableArchive('a.gz'), isFalse); // plain gzip, not tar.gz
    });
  });
}
