/// Mirror of the agent's GET /v1/app/latest payload, also used to represent
/// the `latest.json` manifest published to GitHub Releases.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.size,
    this.sha256,
    this.url,
  });

  final String versionName;
  final int versionCode;
  final int size;
  final String? sha256;

  bool get hasIntegrityMetadata =>
      sha256 != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256!);

  /// Direct APK download URL (from GitHub Releases' `latest.json`). `null`
  /// for the agent's `/v1/app/latest` payload, which doesn't include it (the
  /// APK is fetched from `/v1/app/download` on the same host instead).
  final String? url;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    versionName: json['versionName'] as String? ?? '',
    versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
    size: (json['size'] as num?)?.toInt() ?? 0,
    sha256: (json['sha256'] as String?)?.toLowerCase(),
    url: json['url'] as String?,
  );
}
