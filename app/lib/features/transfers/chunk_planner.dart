/// Chunk planning helpers for resumable uploads.
///
/// Kept in a separate file so it can be unit-tested without pulling in
/// Flutter/Riverpod platform-channel code.
library;

const _defaultChunkSize = 4 * 1024 * 1024; // 4 MB

/// Human-readable label for [_defaultChunkSize] (e.g. "4 MB") — display-only,
/// for settings screens that show the real (fixed, not user-configurable)
/// chunk size rather than fabricating a control for it.
String describeDefaultChunkSize() => '${_defaultChunkSize ~/ (1024 * 1024)} MB';

/// Returns the chunk plan for a file of [fileSize] bytes.
///
/// Each chunk has exactly [chunkSize] bytes, except the last which may be
/// smaller. An empty file still gets 1 chunk (the server must handle it).
({int chunkSize, int totalChunks}) planChunks(
  int fileSize, {
  int chunkSize = _defaultChunkSize,
}) {
  if (fileSize == 0) return (chunkSize: chunkSize, totalChunks: 1);
  final total = (fileSize / chunkSize).ceil();
  return (chunkSize: chunkSize, totalChunks: total);
}
