import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/app_release.dart';
import 'package:remote_file_explorer/core/update/update_service.dart';

void main() {
  group('isUpdateAvailable', () {
    test('true when release code is higher than installed', () {
      final rel = const AppRelease(
        versionName: '1.2.0',
        versionCode: 12,
        size: 1,
      );
      expect(isUpdateAvailable(installedBuild: 11, release: rel), isTrue);
    });
    test('false when equal', () {
      final rel = const AppRelease(
        versionName: '1.2.0',
        versionCode: 12,
        size: 1,
      );
      expect(isUpdateAvailable(installedBuild: 12, release: rel), isFalse);
    });
    test('false when installed is newer', () {
      final rel = const AppRelease(
        versionName: '1.2.0',
        versionCode: 12,
        size: 1,
      );
      expect(isUpdateAvailable(installedBuild: 13, release: rel), isFalse);
    });
    test('false when release is null', () {
      expect(isUpdateAvailable(installedBuild: 5, release: null), isFalse);
    });
  });
}
