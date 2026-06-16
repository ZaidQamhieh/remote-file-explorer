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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
