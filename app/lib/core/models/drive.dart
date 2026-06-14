/// A drive or mount point returned by `/system/drives`.
class Drive {
  const Drive({
    required this.path,
    this.label,
    this.totalBytes,
    this.freeBytes,
    this.isOS = false,
  });

  final String path;
  final String? label;
  final int? totalBytes;
  final int? freeBytes;

  /// Whether this drive contains the operating system.
  final bool isOS;

  factory Drive.fromJson(Map<String, dynamic> json) => Drive(
    path: json['path'] as String? ?? '',
    label: json['label'] as String?,
    totalBytes: json['totalBytes'] as int?,
    freeBytes: json['freeBytes'] as int?,
    isOS: json['isOS'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    if (label != null) 'label': label,
    if (totalBytes != null) 'totalBytes': totalBytes,
    if (freeBytes != null) 'freeBytes': freeBytes,
    if (isOS) 'isOS': isOS,
  };
}
