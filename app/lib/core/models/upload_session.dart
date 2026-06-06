/// A resumable upload session returned by `POST /transfers` or
/// `GET /transfers/{id}`.
class UploadSession {
  const UploadSession({
    required this.id,
    required this.path,
    required this.size,
    required this.chunkSize,
    required this.totalChunks,
    required this.receivedChunks,
    required this.status,
  });

  final String id;
  final String path;
  final int size;
  final int chunkSize;
  final int totalChunks;

  /// Chunk indices that the server has already stored.
  final List<int> receivedChunks;

  /// `open`, `completed`, or `failed`.
  final String status;

  factory UploadSession.fromJson(Map<String, dynamic> json) => UploadSession(
        id: json['id'] as String? ?? '',
        path: json['path'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        chunkSize: json['chunkSize'] as int? ?? 0,
        totalChunks: json['totalChunks'] as int? ?? 0,
        receivedChunks: (json['receivedChunks'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
        status: json['status'] as String? ?? 'open',
      );
}
