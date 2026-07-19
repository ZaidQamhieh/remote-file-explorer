import 'dart:io';

import 'package:crypto/crypto.dart';
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

  group('hashApkSha256', () {
    test('matches sha256.convert on the full bytes', () async {
      final dir = await Directory.systemTemp.createTemp('apk_hash_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.bin');
      final bytes = List<int>.generate(5000, (i) => i % 256);
      await file.writeAsBytes(bytes);

      expect(await hashApkSha256(file.path), sha256.convert(bytes).toString());
    });
  });

  group('verifyDownloadedApk (PR-25)', () {
    test('true when no sha256 was published and size matches', () async {
      const release = AppRelease(
        versionName: '1.0.0',
        versionCode: 10,
        size: 4,
      );
      final file = await apkCacheFileFor(10);
      await file.writeAsBytes([1, 2, 3, 4]);
      expect(await verifyDownloadedApk(release, file), isTrue);
    });

    test('false when the size matches but the sha256 does not', () async {
      final wrongHash = sha256.convert([9, 9, 9, 9]).toString();
      final release = AppRelease(
        versionName: '1.0.0',
        versionCode: 11,
        size: 4,
        sha256: wrongHash,
      );
      final file = await apkCacheFileFor(11);
      await file.writeAsBytes([1, 2, 3, 4]);
      expect(await verifyDownloadedApk(release, file), isFalse);
    });

    test('true when the sha256 matches exactly', () async {
      const bytes = [1, 2, 3, 4];
      final release = AppRelease(
        versionName: '1.0.0',
        versionCode: 12,
        size: 4,
        sha256: sha256.convert(bytes).toString(),
      );
      final file = await apkCacheFileFor(12);
      await file.writeAsBytes(bytes);
      expect(await verifyDownloadedApk(release, file), isTrue);
    });
  });

  group('sharedDownloadApk integrity check (PR-25)', () {
    test(
      'a downloaded APK that does not match the published sha256 is '
      'deleted and reported as a failure instead of being installed',
      () async {
        // _CountingUpdateSource writes release.size zero-bytes; publish a
        // sha256 that does NOT match that content.
        final wrongHash =
            sha256.convert([9, 9, 9, 9, 9, 9, 9, 9, 9, 9]).toString();
        final release = AppRelease(
          versionName: '1.0.0',
          versionCode: 13,
          size: 10,
          sha256: wrongHash,
        );
        final file = await apkCacheFileFor(13);
        final source = _CountingUpdateSource();

        await expectLater(
          sharedDownloadApk(source: source, release: release, localFile: file),
          throwsA(isA<ApkIntegrityException>()),
        );
        expect(
          await file.exists(),
          isFalse,
          reason: 'a failed-verification download must not be left installable',
        );
      },
    );

    test(
      'a downloaded APK matching the published sha256 is accepted',
      () async {
        final matchingHash = sha256.convert(List.filled(10, 0)).toString();
        final release = AppRelease(
          versionName: '1.0.0',
          versionCode: 14,
          size: 10,
          sha256: matchingHash,
        );
        final file = await apkCacheFileFor(14);
        final source = _CountingUpdateSource();

        await sharedDownloadApk(
          source: source,
          release: release,
          localFile: file,
        );

        expect(await file.exists(), isTrue);
        expect(await file.length(), 10);
      },
    );
  });

  group('sharedDownloadApk cross-isolate lock (PR-25)', () {
    test(
      'an existing lock file (another isolate/process already downloading) '
      'blocks a concurrent download until it is removed — '
      '_activeApkDownloads only coordinates callers within this isolate',
      () async {
        const release = AppRelease(
          versionName: '1.0.0',
          versionCode: 15,
          size: 5,
        );
        final file = await apkCacheFileFor(15);
        final lockFile = File('${file.path}.lock');
        await lockFile.create(exclusive: true);

        final source = _CountingUpdateSource();
        final future = sharedDownloadApk(
          source: source,
          release: release,
          localFile: file,
        );

        // Give the call a chance to run up to the point where it must block
        // on the lock.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          source.downloadCalls,
          0,
          reason: 'must not start downloading while the lock file exists',
        );

        await lockFile.delete();

        await future;
        expect(source.downloadCalls, 1);
      },
    );

    test('a stale lock (older than the staleness window) is cleared instead of '
        'wedging the download forever — the holder may have crashed', () async {
      const release = AppRelease(
        versionName: '1.0.0',
        versionCode: 16,
        size: 5,
      );
      final file = await apkCacheFileFor(16);
      final lockFile = File('${file.path}.lock');
      await lockFile.create(exclusive: true);
      // Back-date the lock file past the staleness window instead of
      // waiting 2 real minutes.
      await lockFile.setLastModified(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final source = _CountingUpdateSource();
      await sharedDownloadApk(
        source: source,
        release: release,
        localFile: file,
      );

      expect(source.downloadCalls, 1);
      expect(await lockFile.exists(), isFalse);
    });
  });
}
