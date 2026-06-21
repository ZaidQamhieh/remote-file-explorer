/// A file-system entry (file or directory) returned by the agent.
class Entry {
  const Entry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.mimeType,
    this.mode,
    this.modified,
    this.created,
    this.isSymlink = false,
    this.symlinkTarget,
  });

  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final String? mimeType;

  /// POSIX-style permission string (e.g. `-rw-r--r--`).
  final String? mode;

  final DateTime? modified;
  final DateTime? created;
  final bool isSymlink;

  /// Absolute path the symlink points to (only present when isSymlink is true).
  final String? symlinkTarget;

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    isDir: json['isDir'] as bool? ?? false,
    size: json['size'] as int?,
    mimeType: json['mimeType'] as String?,
    mode: json['mode'] as String?,
    modified:
        json['modified'] == null
            ? null
            : DateTime.parse(json['modified'] as String),
    created:
        json['created'] == null
            ? null
            : DateTime.parse(json['created'] as String),
    isSymlink: json['isSymlink'] as bool? ?? false,
    symlinkTarget: json['symlinkTarget'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'isDir': isDir,
    if (size != null) 'size': size,
    if (mimeType != null) 'mimeType': mimeType,
    if (mode != null) 'mode': mode,
    if (modified != null) 'modified': modified!.toIso8601String(),
    if (created != null) 'created': created!.toIso8601String(),
    'isSymlink': isSymlink,
    if (symlinkTarget != null) 'symlinkTarget': symlinkTarget,
  };
}
