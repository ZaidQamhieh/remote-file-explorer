import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/app_release.dart';
import 'package:remote_file_explorer/core/update/auto_update.dart';
import 'package:remote_file_explorer/core/update/github_update_source.dart';

/// Counts calls and simulates a slow download so two overlapping
/// [sharedDownloadApk] calls have a window to race if the join fails.
class _CountingUpdateSource extends GithubUpdateSource {
  int downloadCalls = 0;

  @override
  Future<void> downloadApk({
    required AppRelease release,
    required File localFile,
    int startByte = 0,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloadCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await localFile.writeAsBytes(List.filled(release.size, 0));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('apk_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            switch (call.method) {
              case 'getTemporaryDirectory':
                return tempDir.path;
              case 'getExternalCacheDirectories':
                return null; // force the getTemporaryDirectory fallback
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('apkCacheFileFor names the file after the version code', () async {
    final file = await apkCacheFileFor(42);
    expect(file.path, endsWith('update-42.apk'));
  });

  test('isApkReadyToInstall is false when nothing is cached', () async {
    const release = AppRelease(versionName: '1.0.0', versionCode: 1, size: 100);
    expect(await isApkReadyToInstall(release), isFalse);
  });

  test('isApkReadyToInstall is false for a partial download', () async {
    const release = AppRelease(versionName: '1.0.0', versionCode: 2, size: 100);
    final file = await apkCacheFileFor(2);
    await file.writeAsBytes(List.filled(50, 0));
    expect(await isApkReadyToInstall(release), isFalse);
  });

  test(
    'isApkReadyToInstall is true once the file matches the release size',
    () async {
      const release = AppRelease(
        versionName: '1.0.0',
        versionCode: 3,
        size: 100,
      );
      final file = await apkCacheFileFor(3);
      await file.writeAsBytes(List.filled(100, 0));
      expect(await isApkReadyToInstall(release), isTrue);
    },
  );

  test(
    'isApkReadyToInstall is false when the release reports no size',
    () async {
      const release = AppRelease(versionName: '1.0.0', versionCode: 4, size: 0);
      final file = await apkCacheFileFor(4);
      await file.writeAsBytes(const []);
      expect(await isApkReadyToInstall(release), isFalse);
    },
  );

  test('sharedDownloadApk joins an overlapping call instead of downloading '
      'the same release twice (the background pre-download / manual "Update" '
      'race that corrupted the cached APK)', () async {
    const release = AppRelease(versionName: '1.0.0', versionCode: 5, size: 10);
    final file = await apkCacheFileFor(5);
    final source = _CountingUpdateSource();

    final results = await Future.wait([
      sharedDownloadApk(source: source, release: release, localFile: file),
      sharedDownloadApk(source: source, release: release, localFile: file),
    ]);

    expect(results.length, 2);
    expect(source.downloadCalls, 1);
  });
}
