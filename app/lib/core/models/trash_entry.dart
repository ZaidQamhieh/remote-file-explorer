/// An item in the agent's trash store, returned by `GET /v1/trash`.
class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.name,
    required this.originalPath,
    this.deletedAt,
    this.size,
    this.isDir = false,
  });

  /// Opaque id used by `/trash/restore` and `DELETE /trash`.
  final String id;
  final String name;

  /// Where the item will be restored to.
  final String originalPath;
  final DateTime? deletedAt;
  final int? size;
  final bool isDir;

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    originalPath: json['originalPath'] as String? ?? '',
    deletedAt:
        json['deletedAt'] == null
            ? null
            : DateTime.tryParse(json['deletedAt'] as String),
    size: json['size'] as int?,
    isDir: json['isDir'] as bool? ?? false,
  );
}
