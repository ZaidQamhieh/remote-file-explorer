/// Mirror of the agent's GET /v1/app/latest payload.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.size,
  });

  final String versionName;
  final int versionCode;
  final int size;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        versionName: json['versionName'] as String? ?? '',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}
