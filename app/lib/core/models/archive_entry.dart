/// An entry inside an archive, returned by the archive peek endpoint.
class ArchiveEntry {
  const ArchiveEntry({
    required this.path,
    required this.size,
    required this.modified,
    required this.isDir,
  });

  final String path;
  final int size;
  final DateTime modified;
  final bool isDir;

  factory ArchiveEntry.fromJson(Map<String, dynamic> json) => ArchiveEntry(
    path: json['path'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    modified:
        json['modified'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.parse(json['modified'] as String),
    isDir: json['isDir'] as bool? ?? false,
  );
}
