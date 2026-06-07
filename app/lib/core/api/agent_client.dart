import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/drive.dart';
import '../models/entry.dart';
import '../models/health.dart';
import '../models/host.dart';
import '../models/listing.dart';
import '../models/pair_response.dart';
import '../models/upload_session.dart';

/// Thrown when an agent's TLS certificate does not match the pinned fingerprint.
class CertPinMismatch implements Exception {
  CertPinMismatch(this.expected, this.actual);
  final String expected;
  final String actual;
  @override
  String toString() => 'Certificate fingerprint mismatch '
      '(expected $expected, got $actual)';
}

/// Thrown when an API call returns an HTTP error.
class AgentApiException implements Exception {
  AgentApiException(this.statusCode, this.code, this.message);
  final int statusCode;
  final String code;
  final String message;
  @override
  String toString() => 'AgentApiException($statusCode): $code — $message';
}

/// HTTPS client for a single host agent.
///
/// The agent uses a self-signed certificate, so standard CA validation is
/// bypassed and replaced with **fingerprint pinning**: if [Host.certFingerprint]
/// is set, the leaf certificate's SHA-256 must match it. When it is null we are
/// pairing for the first time (trust on first use) and the caller captures the
/// fingerprint via [lastSeenFingerprint].
class AgentClient {
  AgentClient(this.host, {String? deviceToken}) {
    final adapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) {
          final fp = sha256.convert(cert.der).toString();
          lastSeenFingerprint = fp;
          final pinned = this.host.certFingerprint;
          if (pinned == null) return true; // TOFU: accept and capture
          if (fp == pinned) return true;
          throw CertPinMismatch(pinned, fp);
        };
        return client;
      },
    );

    _dio = Dio(
      BaseOptions(
        baseUrl: host.baseUri.toString(),
        connectTimeout: const Duration(seconds: 10),
        headers: deviceToken == null
            ? null
            : {'Authorization': 'Bearer $deviceToken'},
      ),
    )..httpClientAdapter = adapter;
  }

  final Host host;
  late final Dio _dio;

  /// Fingerprint observed on the most recent TLS handshake (for TOFU capture).
  String? lastSeenFingerprint;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static AgentApiException _apiError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return AgentApiException(
        e.response?.statusCode ?? 0,
        data['code'] as String? ?? 'UNKNOWN',
        data['message'] as String? ?? e.message ?? '',
      );
    }
    return AgentApiException(
      e.response?.statusCode ?? 0,
      'UNKNOWN',
      e.message ?? e.toString(),
    );
  }

  Future<T> _get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final res = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return res.data as T;
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  Future<T> _post<T>(String path, {dynamic data, Options? options}) async {
    try {
      final res = await _dio.post<T>(path, data: data, options: options);
      return res.data as T;
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  Future<T> _patch<T>(String path, {dynamic data}) async {
    try {
      final res = await _dio.patch<T>(path, data: data);
      return res.data as T;
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  Future<T> _delete<T>(String path,
      {Map<String, dynamic>? queryParameters, dynamic data}) async {
    try {
      final res = await _dio.delete<T>(path,
          queryParameters: queryParameters, data: data);
      return res.data as T;
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Unauthenticated endpoints
  // ---------------------------------------------------------------------------

  /// Calls the unauthenticated `/health` endpoint.
  Future<Health> health() async {
    final data =
        await _get<Map<String, dynamic>>('/health');
    return Health.fromJson(data);
  }

  /// Pair this device with the agent.
  ///
  /// Returns the [PairResponse] which contains the device token. The caller
  /// should capture [lastSeenFingerprint] (TOFU) immediately after and verify
  /// it against any fingerprint obtained via QR.
  Future<PairResponse> pair({
    required String pairingCode,
    required String deviceLabel,
    required String clientPublicKey,
  }) async {
    final data = await _post<Map<String, dynamic>>('/pair', data: {
      'pairingCode': pairingCode,
      'deviceLabel': deviceLabel,
      'clientPublicKey': clientPublicKey,
    });
    return PairResponse.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — read
  // ---------------------------------------------------------------------------

  /// List available drives / mount points.
  Future<List<Drive>> drives() async {
    final data = await _get<List<dynamic>>('/system/drives');
    return data
        .map((e) => Drive.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// List a directory at [path].
  ///
  /// Pass [cursor] to page through large directories.
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    final data = await _get<Map<String, dynamic>>('/fs', queryParameters: {
      'path': path,
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    return Listing.fromJson(data);
  }

  /// Fetch detailed metadata for a single entry.
  Future<Entry> meta(String path) async {
    final data = await _get<Map<String, dynamic>>(
      '/fs/meta',
      queryParameters: {'path': path},
    );
    return Entry.fromJson(data);
  }

  /// Search for files and folders whose name contains [q] (case-insensitive).
  ///
  /// If [root] is provided the search is constrained to that subtree;
  /// otherwise the agent searches every allowed root. [limit] caps the
  /// number of results returned (server-side capped too).
  Future<List<Entry>> search({
    required String q,
    String? root,
    int limit = 100,
  }) async {
    final data = await _get<List<dynamic>>('/search', queryParameters: {
      'q': q,
      if (root != null) 'root': root,
      'limit': limit,
    });
    return data
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Filesystem — write
  // ---------------------------------------------------------------------------

  Future<Entry> createFolder(String path) async {
    final data =
        await _post<Map<String, dynamic>>('/fs/folder', data: {'path': path});
    return Entry.fromJson(data);
  }

  Future<Entry> createFile(String path) async {
    final data =
        await _post<Map<String, dynamic>>('/fs/file', data: {'path': path});
    return Entry.fromJson(data);
  }

  Future<Entry> rename(String src, String dst) async {
    final data = await _patch<Map<String, dynamic>>(
      '/fs/rename',
      data: {'src': src, 'dst': dst},
    );
    return Entry.fromJson(data);
  }

  Future<Map<String, dynamic>> copy(
    List<String> sources,
    String destDir, {
    bool duplicate = false,
  }) async {
    return _post<Map<String, dynamic>>('/fs/copy', data: {
      'sources': sources,
      'destDir': destDir,
      'duplicate': duplicate,
    });
  }

  Future<Map<String, dynamic>> move(
    List<String> sources,
    String destDir,
  ) async {
    return _post<Map<String, dynamic>>('/fs/move', data: {
      'sources': sources,
      'destDir': destDir,
    });
  }

  Future<Map<String, dynamic>> delete(
    List<String> paths, {
    bool permanent = false,
  }) async {
    return _delete<Map<String, dynamic>>(
      '/fs',
      data: {'paths': paths, 'permanent': permanent},
    );
  }

  // ---------------------------------------------------------------------------
  // Download (ranged / streamed to local file with progress)
  // ---------------------------------------------------------------------------

  /// Download the file at [remotePath] to [localFile], reporting [onProgress]
  /// as bytes received / total bytes.
  ///
  /// Supports HTTP Range resumption: pass [startByte] to skip already-received
  /// data (set to 0 or omit for a fresh download).
  Future<void> downloadFile({
    required String remotePath,
    required File localFile,
    int startByte = 0,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final headers = <String, dynamic>{};
      if (startByte > 0) {
        headers['Range'] = 'bytes=$startByte-';
      }
      await _dio.download(
        '/content',
        localFile.path,
        queryParameters: {'path': remotePath},
        options: Options(headers: headers, responseType: ResponseType.stream),
        deleteOnError: false,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Resumable upload
  // ---------------------------------------------------------------------------

  /// Open a new resumable upload session.
  Future<UploadSession> openUploadSession({
    required String path,
    required int size,
    required String sha256Hex,
    required int chunkSize,
    bool overwrite = false,
  }) async {
    final data = await _post<Map<String, dynamic>>('/transfers', data: {
      'path': path,
      'size': size,
      'sha256': sha256Hex,
      'chunkSize': chunkSize,
      'overwrite': overwrite,
    });
    return UploadSession.fromJson(data);
  }

  /// Get the current status of an upload session (for resume).
  Future<UploadSession> getUploadSession(String id) async {
    final data =
        await _get<Map<String, dynamic>>('/transfers/$id');
    return UploadSession.fromJson(data);
  }

  /// Upload a single chunk.
  ///
  /// [chunkIndex] is the 0-based chunk number.
  /// [data] is the raw chunk bytes.
  /// [contentRange] is the `Content-Range` header value, e.g. `bytes 0-1023/4096`.
  /// [chunkSha256] is the hex SHA-256 of the chunk bytes.
  Future<void> uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required Uint8List data,
    required String contentRange,
    required String chunkSha256,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.put<void>(
        '/transfers/$sessionId/chunks/$chunkIndex',
        data: Stream.fromIterable([data]),
        options: Options(
          headers: {
            'Content-Range': contentRange,
            'X-Chunk-Sha256': chunkSha256,
            'Content-Type': 'application/octet-stream',
          },
          requestEncoder: (_, __) => data,
        ),
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  /// Finalise the upload session (verify whole-file hash, atomic rename).
  Future<Entry> completeUpload(String sessionId) async {
    final data =
        await _post<Map<String, dynamic>>('/transfers/$sessionId/complete');
    return Entry.fromJson(data);
  }
}
