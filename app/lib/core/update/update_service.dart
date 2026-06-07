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
