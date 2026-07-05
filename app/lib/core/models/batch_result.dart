/// A single item's outcome within a batch filesystem operation
/// (copy/move/delete/restoreTrash/rename) — matches the agent's `BatchResult`
/// response envelope (see `protocol/openapi.yaml`).
class BatchItemResult {
  const BatchItemResult({
    required this.path,
    required this.ok,
    this.errorCode,
    this.errorMessage,
  });

  final String path;
  final bool ok;
  final String? errorCode;
  final String? errorMessage;

  factory BatchItemResult.fromJson(Map<String, dynamic> j) {
    final err = j['error'];
    return BatchItemResult(
      path: j['path'] as String? ?? '',
      ok: j['ok'] == true,
      errorCode: err is Map ? err['code'] as String? : null,
      errorMessage: err is Map ? err['message'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'ok': ok,
    if (errorCode != null || errorMessage != null)
      'error': {'code': errorCode, 'message': errorMessage},
  };
}

/// Per-item results for a batch filesystem operation — replaces the
/// untyped `Map<String, dynamic>` the client used to hand back raw from
/// `/fs/copy`, `/fs/move`, `/fs` (delete) and `/trash/restore`.
class BatchResult {
  const BatchResult({required this.results});

  final List<BatchItemResult> results;

  factory BatchResult.fromJson(Map<String, dynamic> j) => BatchResult(
    results:
        ((j['results'] as List?) ?? const [])
            .map((e) => BatchItemResult.fromJson(e as Map<String, dynamic>))
            .toList(),
  );

  List<BatchItemResult> get failed => results.where((r) => !r.ok).toList();
}
