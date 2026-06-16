import '../models/app_release.dart';

/// Pure version comparison — true when [release] is newer than the installed
/// build number. Kept free of plugins so it is unit-testable.
bool isUpdateAvailable({
  required int installedBuild,
  required AppRelease? release,
}) {
  if (release == null) return false;
  return release.versionCode > installedBuild;
}

/// Whether [release] should be surfaced in the passive auto-update banner,
/// given the highest version code the user has already dismissed
/// ([dismissedCode]).
///
/// Returns false for a null release or one at/below the dismissed code, so a
/// dismissal sticks until an even-newer build appears. Pure (no plugins) so it
/// is unit-testable. Note this does NOT re-check "newer than installed" — the
/// caller passes a [release] already filtered by [isUpdateAvailable].
bool shouldSurfaceUpdate({
  required AppRelease? release,
  required int dismissedCode,
}) {
  if (release == null) return false;
  return release.versionCode > dismissedCode;
}
