import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/agent_settings.dart';
import '../models/app_release.dart';
import '../models/device.dart';
import '../models/drive.dart';
import '../models/entry.dart';
import '../models/health.dart';
import '../models/host.dart';
import '../models/listing.dart';
import '../models/pair_response.dart';
import '../models/search_result.dart';
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

/// Thrown by [AgentClient.downloadFile] when a resumed download (a Range
/// request with `startByte > 0`) was answered with a full `200 OK` instead
/// of a `206 Partial Content`.
///
/// This means the server ignored (or didn't honor) the `Range` header and
/// streamed the *entire* file, which — combined with append-mode writing —
/// would have produced a corrupted local file (stale partial bytes followed
/// by the full file). [downloadFile] deletes the partial file before
/// throwing this; callers should restart the download from scratch
/// (`startByte = 0`).
class RangeNotSatisfiedException implements Exception {
  @override
  String toString() =>
      'RangeNotSatisfiedException: server returned full content for a '
      'ranged request; partial file deleted, restart from 0';
}

/// HTTPS client for a single host agent.
///
/// The agent uses a self-signed certificate, so standard CA validation is
/// bypassed and replaced with **fingerprint pinning**: if [Host.certFingerprint]
/// is set, the leaf certificate's SHA-256 must match it. When it is null we are
/// pairing for the first time (trust on first use) and the caller captures the
/// fingerprint via [lastSeenFingerprint].
class AgentClient {
  AgentClient(this.host, {String? deviceToken})
      : _addresses = host.addresses {
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

    // Start from whichever address worked last time for this host (e.g. LAN
    // at home, Tailscale away) so reconnects don't pay the fallback latency.
    _addrIndex = (_lastGoodAddrIndex[host.id] ?? 0).clamp(0, _addresses.length - 1);

    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrlFor(_addresses[_addrIndex]),
        connectTimeout: const Duration(seconds: 10),
        headers: deviceToken == null
            ? null
            : {'Authorization': 'Bearer $deviceToken'},
      ),
    )..httpClientAdapter = adapter;

    // Dual-address fallback: if the active address is unreachable (e.g. the
    // LAN address while we're away from home), retry the same request against
    // the next candidate (typically the Tailscale address) and, on success,
    // stick with it for the rest of this client's life.
    _dio.interceptors.add(InterceptorsWrapper(onError: (e, handler) async {
      final isConnectionFailure = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout;
      if (!isConnectionFailure || _addrIndex + 1 >= _addresses.length) {
        return handler.next(e);
      }
      _addrIndex++;
      final newBase = _baseUrlFor(_addresses[_addrIndex]);
      _dio.options.baseUrl = newBase;
      try {
        final retried = await _dio.fetch(e.requestOptions..baseUrl = newBase);
        _lastGoodAddrIndex[host.id] = _addrIndex;
        return handler.resolve(retried);
      } on DioException catch (e2) {
        return handler.next(e2);
      }
    }));
  }

  /// Releases the underlying HTTP client's connections.
  ///
  /// Safe to call multiple times. Callers that create short-lived
  /// [AgentClient]s (e.g. one per transfer attempt) should call this once the
  /// client is no longer needed so idle sockets don't linger.
  void close() => _dio.close(force: true);

  static String _baseUrlFor(String address) => 'https://$address/v1';

  /// Remembers, per host id, which candidate address last succeeded — so the
  /// next [AgentClient] for that host starts there instead of probing again.
  static final Map<String, int> _lastGoodAddrIndex = {};

  final Host host;
  late final Dio _dio;
  late final List<String> _addresses;
  late int _addrIndex;

  /// Fingerprint observed on the most recent TLS handshake (for TOFU capture).
  String? lastSeenFingerprint;

  /// The address (`host:port`, no scheme) this client is currently talking
  /// to — initially whichever candidate worked last time, and updated if a
  /// request falls back to the next candidate (see the retry interceptor in
  /// the constructor). Used by the UI to show "LAN" vs "Tailscale".
  String get activeAddress => _addresses[_addrIndex];

  /// Whether [activeAddress] is the host's Tailscale address (as opposed to
  /// its primary/LAN address).
  bool get isActiveAddressTailscale =>
      host.tailscaleAddress != null && activeAddress == host.tailscaleAddress;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Best-effort extraction of the `code` field from an error response body,
  /// regardless of whether Dio parsed it as JSON (`Map`) or left it as raw
  /// bytes (`List<int>`, e.g. when the request used `ResponseType.bytes`).
  static String? _errorCode(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['code'] as String?;
    }
    if (data is List<int>) {
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map<String, dynamic>) {
          return decoded['code'] as String?;
        }
      } catch (_) {
        // Not JSON — ignore.
      }
    }
    return null;
  }

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

  /// Converts [e] to an [AgentApiException] and throws it — *unless* [e] is
  /// a cancellation (from a [CancelToken] passed in by the caller), in which
  /// case the original [DioException] is rethrown unchanged so callers can
  /// distinguish "user paused/canceled" from a real API/network failure.
  static Never _throwTransferError(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      throw e;
    }
    throw _apiError(e);
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
    String? deviceId,
  }) async {
    final data = await _post<Map<String, dynamic>>('/pair', data: {
      'pairingCode': pairingCode,
      'deviceLabel': deviceLabel,
      'clientPublicKey': clientPublicKey,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
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

  /// Search for files and folders whose name contains [q] (case-insensitive),
  /// or matches it as a case-insensitive glob if [q] contains `*` or `?`.
  ///
  /// If [root] is provided the search is constrained to that subtree;
  /// otherwise the agent searches every allowed root. [limit] caps the
  /// number of results returned (server-side capped too).
  ///
  /// Optional AND-combined filters:
  /// - [types]: entry categories, e.g. `folder`, `image`, `video`, `audio`,
  ///   `document`, `archive`, `other`.
  /// - [ext]: file extensions, without the leading dot.
  /// - [minSize] / [maxSize]: size bounds in bytes.
  /// - [modifiedAfter] / [modifiedBefore]: modification-time bounds, sent as
  ///   RFC3339 timestamps.
  ///
  /// Pass [cancelToken] to allow canceling an in-flight search (e.g. when the
  /// user types again or leaves the screen). A cancellation surfaces as a
  /// [DioException] with [DioExceptionType.cancel] rather than
  /// [AgentApiException].
  ///
  /// The returned [SearchResult] also reports whether the server truncated
  /// the result list ([SearchResult.truncated]) or hit its walk time budget
  /// ([SearchResult.timeBudgetHit]).
  Future<SearchResult> search({
    required String q,
    String? root,
    int limit = 100,
    List<String>? types,
    List<String>? ext,
    int? minSize,
    int? maxSize,
    DateTime? modifiedAfter,
    DateTime? modifiedBefore,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>('/search', queryParameters: {
        'q': q,
        if (root != null) 'root': root,
        'limit': limit,
        if (types != null && types.isNotEmpty) 'types': types.join(','),
        if (ext != null && ext.isNotEmpty) 'ext': ext.join(','),
        if (minSize != null) 'minSize': minSize,
        if (maxSize != null) 'maxSize': maxSize,
        if (modifiedAfter != null)
          'modifiedAfter': modifiedAfter.toUtc().toIso8601String(),
        if (modifiedBefore != null)
          'modifiedBefore': modifiedBefore.toUtc().toIso8601String(),
      }, cancelToken: cancelToken);
      return SearchResult.fromResponse(res.data ?? const [], res.headers.map);
    } on DioException catch (e) {
      _throwTransferError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Settings & device management
  // ---------------------------------------------------------------------------

  Future<AgentSettings> getSettings() async {
    final data = await _get<Map<String, dynamic>>('/settings');
    return AgentSettings.fromJson(data);
  }

  Future<AgentSettings> updateSettings({
    bool? readOnly,
    List<String>? roots,
    String? agentName,
  }) async {
    final data = await _patch<Map<String, dynamic>>('/settings', data: {
      if (readOnly != null) 'readOnly': readOnly,
      if (roots != null) 'roots': roots,
      if (agentName != null) 'agentName': agentName,
    });
    return AgentSettings.fromJson(data);
  }

  Future<List<Device>> listDevices() async {
    final data = await _get<List<dynamic>>('/devices');
    return data
        .map((e) => Device.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeDevice(String id) async {
    await _delete<void>('/devices/$id');
  }

  /// Permanently removes a device row (used to clear revoked devices). The
  /// agent refuses to remove the device making the request.
  Future<void> deleteDevice(String id) async {
    await _delete<void>('/devices/$id',
        queryParameters: {'purge': 'true'});
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

  /// Permanently and recursively deletes [paths]. There is no "trash" or
  /// undo — the agent removes the files/directories immediately.
  Future<Map<String, dynamic>> delete(List<String> paths) async {
    return _delete<Map<String, dynamic>>(
      '/fs',
      data: {'paths': paths},
    );
  }

  // ---------------------------------------------------------------------------
  // Thumbnails
  // ---------------------------------------------------------------------------

  /// Fetches a server-rendered JPEG thumbnail for the file at [remotePath],
  /// resized so its longest side is roughly [size] px.
  ///
  /// Returns `null` when the agent has no thumbnail for this file (e.g. a
  /// non-image, or a format it can't decode — reported as a 404 with code
  /// `NOT_AVAILABLE`); callers should fall back to a generic icon in that
  /// case rather than treating it as an error.
  Future<Uint8List?> thumbnail(String remotePath, {int size = 256}) async {
    try {
      final res = await _dio.get<List<int>>(
        '/thumb',
        queryParameters: {'path': remotePath, 'size': size},
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || _errorCode(e.response?.data) == 'NOT_AVAILABLE') {
        return null;
      }
      throw _apiError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Download (ranged / streamed to local file with progress)
  // ---------------------------------------------------------------------------

  /// Download the file at [remotePath] to [localFile], reporting [onProgress]
  /// as bytes received / total bytes.
  ///
  /// Supports HTTP Range resumption: pass [startByte] to skip already-received
  /// data (set to 0 or omit for a fresh download). When resuming, bytes are
  /// *appended* to [localFile] (it must already contain exactly [startByte]
  /// bytes); a fresh download (`startByte == 0`) overwrites/truncates it.
  ///
  /// If the server responds to a ranged request (`startByte > 0`) with a
  /// full `200 OK` instead of `206 Partial Content`, the partial file is
  /// deleted and [RangeNotSatisfiedException] is thrown so the caller can
  /// restart the download from scratch.
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
      final response = await _dio.download(
        '/content',
        localFile.path,
        queryParameters: {'path': remotePath},
        options: Options(headers: headers, responseType: ResponseType.stream),
        deleteOnError: false,
        cancelToken: cancelToken,
        fileAccessMode:
            startByte > 0 ? FileAccessMode.append : FileAccessMode.write,
        onReceiveProgress: onProgress,
      );

      if (startByte > 0 && response.statusCode != 206) {
        // Server ignored our Range header and sent the full file, which we
        // just appended onto the existing partial — the file is now
        // corrupt (stale bytes + full file). Delete it and signal the
        // caller to restart from 0.
        if (await localFile.exists()) {
          await localFile.delete();
        }
        throw RangeNotSatisfiedException();
      }
    } on DioException catch (e) {
      _throwTransferError(e);
    }
  }

  /// Fetch the full contents of [remotePath] into memory as raw bytes.
  ///
  /// Intended for small-ish files (previews of images/text/PDFs). Callers
  /// should check [Entry.size] via [meta] first and avoid calling this for
  /// very large files — there is no size cap enforced here.
  Future<Uint8List> fetchBytes(String remotePath, {CancelToken? cancelToken}) async {
    try {
      final res = await _dio.get<List<int>>(
        '/content',
        queryParameters: {'path': remotePath},
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is Uint8List) return data;
      return Uint8List.fromList(data ?? const []);
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
            Headers.contentLengthHeader: data.length,
          },
        ),
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      _throwTransferError(e);
    }
  }

  /// Finalise the upload session (verify whole-file hash, atomic rename).
  Future<Entry> completeUpload(String sessionId) async {
    final data =
        await _post<Map<String, dynamic>>('/transfers/$sessionId/complete');
    return Entry.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // In-app updates
  // ---------------------------------------------------------------------------

  /// Returns the latest APK the agent offers, or `null` when none (204).
  Future<AppRelease?> latestRelease() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/app/latest');
      final data = res.data;
      if (res.statusCode == 204 || data == null) return null;
      return AppRelease.fromJson(data);
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  /// Downloads the latest APK to [localFile], reporting [onProgress].
  ///
  /// Pass [cancelToken] to allow aborting an in-flight download (e.g. the
  /// user taps Cancel on the update progress dialog). A cancellation surfaces
  /// as a [DioException] with [DioExceptionType.cancel] rather than
  /// [AgentApiException], matching [search] and [downloadFile] — callers can
  /// distinguish "user cancelled" from a real download failure.
  Future<void> downloadApk({
    required File localFile,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.download(
        '/app/download',
        localFile.path,
        options: Options(responseType: ResponseType.stream),
        deleteOnError: true,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      _throwTransferError(e);
    }
  }
}
