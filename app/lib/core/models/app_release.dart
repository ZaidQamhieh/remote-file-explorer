/// Mirror of the agent's GET /v1/app/latest payload, also used to represent
/// the `latest.json` manifest published to GitHub Releases.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.size,
    this.url,
    this.sha256,
  });

  final String versionName;
  final int versionCode;
  final int size;

  /// Direct APK download URL (from GitHub Releases' `latest.json`). `null`
  /// for the agent's `/v1/app/latest` payload, which doesn't include it (the
  /// APK is fetched from `/v1/app/download` on the same host instead).
  final String? url;

  /// Hex-encoded SHA-256 of the APK, published in `latest.json` by
  /// `.github/workflows/release.yml` (PR-25). `null` for a release published
  /// before this field existed, or for the agent's payload (which doesn't
  /// carry one) — callers fall back to a size-only check in that case.
  final String? sha256;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    versionName: json['versionName'] as String? ?? '',
    versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
    size: (json['size'] as num?)?.toInt() ?? 0,
    url: json['url'] as String?,
    sha256: json['sha256'] as String?,
  );
}
