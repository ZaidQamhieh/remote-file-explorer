/// Passive auto-update check: once per app session the app asks GitHub
/// Releases whether a newer APK exists and, if so, surfaces a dismissible
/// banner on the home screen. The actual download/install still happens in the
/// App Settings [UpdateTile] — this only removes the need to manually tap
/// "Check for updates".
///
/// Android-only (the only platform with the installer flow). All network/HTTP
/// errors are swallowed into "no update" so a failed check never nags the user.
library;

import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_release.dart';
import 'github_update_source.dart';
import 'update_service.dart';

const _kDismissedKey = 'rfe_update_dismissed_code_v1';

/// Installed build (versionCode). Overridable in tests.
final installedBuildProvider = FutureProvider<int>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
});

/// The GitHub Releases update source. Overridable in tests with a fake.
final githubUpdateSourceProvider = Provider<GithubUpdateSource>(
  (ref) => GithubUpdateSource(),
);

/// Fetches the latest published release and returns it only when it is newer
/// than the installed build; otherwise (up-to-date, non-Android, or any check
/// failure) returns null. Runs once per session (provider is cached), so a
/// relaunch re-checks but in-session navigation does not.
final latestUpdateProvider = FutureProvider<AppRelease?>((ref) async {
  if (!Platform.isAndroid) return null;
  try {
    final source = ref.watch(githubUpdateSourceProvider);
    final latest = await source.latestRelease();
    final installed = await ref.watch(installedBuildProvider.future);
    return isUpdateAvailable(installedBuild: installed, release: latest)
        ? latest
        : null;
  } catch (_) {
    return null;
  }
});

/// The highest version code the user has dismissed, persisted across launches
/// so a dismissal sticks until an even-newer build appears. 0 = nothing
/// dismissed yet.
class DismissedUpdateNotifier extends AsyncNotifier<int> {
  SharedPreferences? _prefs;

  @override
  Future<int> build() async {
    _prefs = await SharedPreferences.getInstance();
    return _prefs!.getInt(_kDismissedKey) ?? 0;
  }

  /// Records [versionCode] as dismissed (monotonic — never lowers the stored
  /// value) and updates state so the banner hides immediately.
  Future<void> dismiss(int versionCode) async {
    final current = state.valueOrNull ?? 0;
    if (versionCode <= current) return;
    await _prefs?.setInt(_kDismissedKey, versionCode);
    state = AsyncData(versionCode);
  }
}

final dismissedUpdateProvider =
    AsyncNotifierProvider<DismissedUpdateNotifier, int>(
      DismissedUpdateNotifier.new,
    );

/// Where a downloaded APK for [versionCode] is cached — shared by the silent
/// background pre-download below and [UpdateTile]'s manual flow so both
/// agree on the same file (and a background download that only got partway
/// resumes cleanly from the manual flow instead of restarting).
Future<File> apkCacheFileFor(int versionCode) async {
  // getExternalCacheDirectories() throws on non-Android platforms — only
  // call it where it's actually supported; everywhere else (including
  // tests, which run on the host OS) falls back to getTemporaryDirectory().
  final dirs = Platform.isAndroid ? await getExternalCacheDirectories() : null;
  final base =
      (dirs != null && dirs.isNotEmpty)
          ? dirs.first
          : await getTemporaryDirectory();
  return File('${base.path}/update-$versionCode.apk');
}

/// True when a complete, size-matched APK for [release] is already cached —
/// the install flow can skip straight to the installer instead of
/// downloading (or resuming) it again.
Future<bool> isApkReadyToInstall(AppRelease release) async {
  if (release.size <= 0) return false;
  final file = await apkCacheFileFor(release.versionCode);
  return await file.exists() && await file.length() == release.size;
}

/// Tracks the in-flight APK download for a given [AppRelease.versionCode], if
/// any. Both [backgroundApkDownloadProvider] and [UpdateTile]'s manual flow
/// target the same cached file ([apkCacheFileFor]) — without this, a manual
/// check that lands while the silent background download is still running
/// would start a *second* concurrent write to that file, corrupting it.
/// Android then refuses to parse the resulting APK ("There was a problem
/// with the app file") even though the file appears complete by size.
final _activeApkDownloads = <int, _SharedApkDownload>{};

class _SharedApkDownload {
  _SharedApkDownload(this.future, this.cancelToken);
  final Future<void> future;
  final CancelToken cancelToken;
  final _listeners = <void Function(int received, int total)>[];

  void _notify(int received, int total) {
    for (final l in _listeners) {
      l(received, total);
    }
  }
}

/// Downloads [release]'s APK to [localFile] (resuming from whatever is
/// already on disk), joining an already in-flight download for the same
/// [AppRelease.versionCode] instead of starting a second concurrent writer.
Future<void> sharedDownloadApk({
  required GithubUpdateSource source,
  required AppRelease release,
  required File localFile,
  void Function(int received, int total)? onProgress,
}) {
  final existing = _activeApkDownloads[release.versionCode];
  if (existing != null) {
    if (onProgress != null) existing._listeners.add(onProgress);
    return existing.future;
  }

  final token = CancelToken();
  late final _SharedApkDownload entry;
  Future<void> start() async {
    final startByte = await localFile.exists() ? await localFile.length() : 0;
    await source.downloadApk(
      release: release,
      localFile: localFile,
      startByte: startByte,
      cancelToken: token,
      onProgress: (received, total) => entry._notify(received, total),
    );
  }

  final future = start().whenComplete(
    () => _activeApkDownloads.remove(release.versionCode),
  );
  entry = _SharedApkDownload(future, token);
  if (onProgress != null) entry._listeners.add(onProgress);
  _activeApkDownloads[release.versionCode] = entry;
  return future;
}

/// Cancels the in-flight download for [versionCode], if any. Safe to call
/// even if there is none, or if it already finished.
void cancelApkDownload(int versionCode) {
  _activeApkDownloads[versionCode]?.cancelToken.cancel();
}

/// Silently pre-downloads the APK for the currently-available update (if
/// any) as soon as it's detected, so tapping "Update" later is instant
/// instead of waiting through the full download. Runs once per session
/// (kept alive by [RemoteFileExplorerApp] watching it for the app's
/// lifetime), best-effort — any failure (no network, storage full, killed
/// mid-download) is swallowed; [UpdateTile]'s manual flow joins this same
/// download via [sharedDownloadApk] rather than racing it.
final backgroundApkDownloadProvider = FutureProvider<void>((ref) async {
  if (!Platform.isAndroid) return;
  final release = await ref.watch(latestUpdateProvider.future);
  if (release == null) return;
  if (await isApkReadyToInstall(release)) return;

  final file = await apkCacheFileFor(release.versionCode);
  try {
    await sharedDownloadApk(
      source: ref.watch(githubUpdateSourceProvider),
      release: release,
      localFile: file,
    );
  } catch (_) {
    // Best effort — see doc comment above.
  }
});
