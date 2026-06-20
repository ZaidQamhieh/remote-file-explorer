/// Mirror of the agent's GET/PUT /v1/settings/bandwidth payload.
class BandwidthSettings {
  const BandwidthSettings({
    this.maxUploadBytesPerSec = 0,
    this.maxDownloadBytesPerSec = 0,
  });

  /// Upload throttle in bytes/sec. 0 = unlimited.
  final int maxUploadBytesPerSec;

  /// Download throttle in bytes/sec. 0 = unlimited.
  final int maxDownloadBytesPerSec;

  factory BandwidthSettings.fromJson(Map<String, dynamic> json) =>
      BandwidthSettings(
        maxUploadBytesPerSec:
            (json['maxUploadBytesPerSec'] as num?)?.toInt() ?? 0,
        maxDownloadBytesPerSec:
            (json['maxDownloadBytesPerSec'] as num?)?.toInt() ?? 0,
      );

  BandwidthSettings copyWith({
    int? maxUploadBytesPerSec,
    int? maxDownloadBytesPerSec,
  }) => BandwidthSettings(
    maxUploadBytesPerSec: maxUploadBytesPerSec ?? this.maxUploadBytesPerSec,
    maxDownloadBytesPerSec:
        maxDownloadBytesPerSec ?? this.maxDownloadBytesPerSec,
  );
}
