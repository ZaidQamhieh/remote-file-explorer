// Tests for requireSaved, the pure decision behind DownloadSaver's PR-57
// fix: a null native save result must never be turned into an invented
// success, and the staging file must not be deleted in that case (deletion
// only happens after requireSaved returns normally — see saveToDownloads).
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/download_saver.dart';

void main() {
  group('requireSaved', () {
    test('returns the destination when the native side confirmed one', () {
      expect(
        requireSaved('Downloads/report.pdf', 'report.pdf'),
        'Downloads/report.pdf',
      );
    });

    test('throws DownloadSaveCancelled on a null result instead of '
        'inventing a destination', () {
      expect(
        () => requireSaved(null, 'report.pdf'),
        throwsA(isA<DownloadSaveCancelled>()),
      );
    });
  });
}
