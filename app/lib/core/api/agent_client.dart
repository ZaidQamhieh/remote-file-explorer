import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../storage/offline_body_cache.dart';
import '../app_info.dart';
import '../models/agent_settings.dart';
import '../models/archive_entry.dart';
import '../models/bandwidth_settings.dart';
import '../models/app_release.dart';
import '../models/batch_result.dart';
import '../models/device.dart';
import '../models/drive.dart';
import '../models/entry.dart';
import '../models/agent_status.dart';
import '../models/health.dart';
import '../models/host.dart';
import '../models/listing.dart';
import '../models/pair_response.dart';
import '../models/search_result.dart';
import '../models/share_link.dart';
import '../models/trash_entry.dart';
import '../models/upload_session.dart';

/// Thrown when an agent's TLS certificate does not match the pinned fingerprint.
class CertPinMismatch implements Exception {
  CertPinMismatch(this.expected, this.actual);
  final String expected;
  final String actual;
  @override
  String toString() =>
      'Certificate fingerprint mismatch '
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

/// Thrown by [AgentClient.putContent] when the agent is in read-only mode
/// (`403 READ_ONLY`) and refuses to write the file.
class ReadOnlyException implements Exception {
  ReadOnlyException(this.message);
  final String message;
  @override
  String toString() => 'ReadOnlyException: $message';
}

/// Thrown by [AgentClient.putContent] when the file changed on disk since
/// the caller's [Entry.modified] was read (`409 STALE_WRITE`) — i.e. the
/// `baseModified` the caller sent no longer matches the file's current
/// modification time.
///
/// Callers should offer to reload the file's current contents, or to
/// overwrite by retrying [AgentClient.putContent] with `baseModified: null`.
class StaleWriteException implements Exception {
  StaleWriteException(this.message);
  final String message;
  @override
  String toString() => 'StaleWriteException: $message';
}

/// Thrown by [AgentClient.putContent] when the new content exceeds the
/// agent's size limit for in-place writes (`413 PAYLOAD_TOO_LARGE`).
class PayloadTooLargeException implements Exception {
  PayloadTooLargeException(this.message);
  final String message;
  @override
  String toString() => 'PayloadTooLargeException: $message';
}

/// Thrown by [AgentClient.fetchBytes] when the remote file's bytes exceed
/// the caller's `maxBytes` cap. The transfer is aborted as soon as the cap
/// is crossed, so the excess is never buffered into memory.
class FetchTooLargeException implements Exception {
  FetchTooLargeException(this.remotePath, this.maxBytes);
  final String remotePath;
  final int maxBytes;
  @override
  String toString() =>
      'FetchTooLargeException: $remotePath exceeds the $maxBytes-byte cap';
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

/// Response from [AgentClient.completeUpload]: the finalized [Entry] plus
/// the whole-file integrity-check result.
///
/// [verified] is `true` only when the agent confirmed the whole-file
/// SHA-256 matches (and reported `verified: true`); older agents that don't
/// send `verified`/`sha256` parse as `verified: false` / `sha256: null`
/// rather than throwing.
class UploadCompleteResult {
  const UploadCompleteResult({
    required this.entry,
    this.verified = false,
    this.sha256,
  });

  final Entry entry;
  final bool verified;

  /// Verified whole-file SHA-256 (hex), present when [verified] is `true`.
  final String? sha256;

  factory UploadCompleteResult.fromJson(Map<String, dynamic> json) =>
      UploadCompleteResult(
        entry: Entry.fromJson(json),
        verified: json['verified'] as bool? ?? false,
        sha256: json['sha256'] as String?,
      );
}

/// Pure decision for S3 gzip-on-download: should this request send
/// `Accept-Encoding: gzip`? Combines the user's "compress on cellular"
/// setting with the current connectivity state — kept separate from Dio so
/// it's directly unit-testable.
bool shouldRequestGzipDownload({
  required bool settingEnabled,
  required List<ConnectivityResult> connectivity,
}) {
  if (!settingEnabled) return false;
  if (connectivity.contains(ConnectivityResult.wifi) ||
      connectivity.contains(ConnectivityResult.ethernet)) {
    return false;
  }
  return connectivity.contains(ConnectivityResult.mobile);
}

/// True if [method] is safe to silently replay against a fallback address
/// after a connection failure. GET/HEAD have no side effects, so a lost
/// response can't mean the request was already applied; a
/// POST/PATCH/PUT/DELETE might have been, so it isn't auto-retried — the
/// error surfaces and the caller decides whether to retry as a fresh,
/// user-initiated action (PR-23).
bool isSafeToRetryOnFallback(String method) {
  final m = method.toUpperCase();
  return m == 'GET' || m == 'HEAD';
}

/// True if [errorType] means the agent was genuinely unreachable, as
/// opposed to a response it actually sent (401/403/404/...) or a failed
/// certificate check. Only this class of failure should fall back to
/// cached offline bytes — falling back on the others would hide a revoked
/// token, a deleted file, or a TLS-pin mismatch behind a stale "it worked"
/// result (PR-56).
bool isConnectivityFailure(DioExceptionType errorType) => switch (errorType) {
  DioExceptionType.connectionError ||
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => true,
  _ => false,
};

/// Accumulates [chunks] into bytes, throwing [FetchTooLargeException] for
/// [remotePath] as soon as more than [maxBytes] have arrived, so [fetchBytes]
/// never buffers past its cap regardless of what the remote file's reported
/// size claims — kept separate from Dio so it's directly unit-testable
/// (PR-28).
Future<Uint8List> collectBytesCapped(
  Stream<List<int>> chunks,
  String remotePath,
  int maxBytes,
) async {
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in chunks) {
    total += chunk.length;
    if (total > maxBytes) {
      throw FetchTooLargeException(remotePath, maxBytes);
    }
    builder.add(chunk);
  }
  return builder.toBytes();
}

/// HTTPS client for a single host agent.
///
/// The agent uses a self-signed certificate, so standard CA validation is
/// bypassed and replaced with **fingerprint pinning**: if [Host.certFingerprint]
/// is set, the leaf certificate's SHA-256 must match it. When it is null we are
/// pairing for the first time (trust on first use) and the caller captures the
/// fingerprint via [lastSeenFingerprint].
class AgentClient {
  AgentClient(this.host, {String? deviceToken, bool probeLanFirst = false})
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

    // When probing (health checks), always start from LAN (index 0) so we
    // re-discover it after coming home. Otherwise start from whichever
    // address worked last time so requests don't pay fallback latency.
    _addrIndex =
        probeLanFirst
            ? 0
            : (_lastGoodAddrIndex[host.id] ?? 0).clamp(
              0,
              _addresses.length - 1,
            );

    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrlFor(_addresses[_addrIndex]),
        connectTimeout: Duration(seconds: probeLanFirst ? 3 : 10),
        headers: {
          if (deviceToken != null) 'Authorization': 'Bearer $deviceToken',
          'X-RFE-Client-Version': appClientVersion,
        },
      ),
    )..httpClientAdapter = adapter;

    // Dual-address fallback: if the active address is unreachable (e.g. the
    // LAN address while we're away from home), retry the same request against
    // the next candidate (typically the Tailscale address) and, on success,
    // stick with it for the rest of this client's life.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          final isConnectionFailure =
              e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout;
          if (!isConnectionFailure ||
              !isSafeToRetryOnFallback(e.requestOptions.method) ||
              _addrIndex + 1 >= _addresses.length) {
            return handler.next(e);
          }
          _addrIndex++;
          final newBase = _baseUrlFor(_addresses[_addrIndex]);
          _dio.options.baseUrl = newBase;
          _dio.options.connectTimeout = const Duration(seconds: 10);
          try {
            final retried = await _dio.fetch(
              e.requestOptions..baseUrl = newBase,
            );
            _lastGoodAddrIndex[host.id] = _addrIndex;
            return handler.resolve(retried);
          } on DioException catch (e2) {
            return handler.next(e2);
          }
        },
      ),
    );
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

  /// When set, [fetchBytes] writes to this cache on success and reads from it
  /// as a fallback when the agent is unreachable.
  OfflineBodyCache? offlineBodyCache;

  /// Called by [fetchBytes] to decide whether to cache a file's bytes.
  /// Receives [host].id and the file's parent folder path.
  /// When null, no caching occurs.
  bool Function(String hostId, String folderPath)? isPinnedFolder;

  /// Whether to send `Accept-Encoding: gzip` on a fresh (non-resumed)
  /// download while on a cellular connection (S3) — set from the user's
  /// "Compress downloads on cellular" app setting at client construction
  /// (see `buildClientForHost`). The agent only honors the header for
  /// non-Range requests on compressible text/code extensions above a small
  /// size floor, so defaulting to true is safe.
  bool compressDownloadsOnCellular = true;

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

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  /// Whether [fetchBytes]/[downloadFile] should send `Accept-Encoding: gzip`
  /// on this request — see [shouldRequestGzipDownload].
  Future<bool> _wantsGzip() async {
    if (!compressDownloadsOnCellular) return false;
    final connectivity = await Connectivity().checkConnectivity();
    return shouldRequestGzipDownload(
      settingEnabled: compressDownloadsOnCellular,
      connectivity: connectivity,
    );
  }

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
    // No HTTP response body means the request never completed — a dropped
    // connection or timeout, not a server error. Surface that as a readable
    // CONNECTION error instead of the opaque "UNKNOWN" catch-all (this is what
    // a flaky network during the large APK download used to report).
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AgentApiException(
          0,
          'CONNECTION',
          'Connection lost — check your network and try again.',
        );
      default:
        return AgentApiException(
          e.response?.statusCode ?? 0,
          'UNKNOWN',
          e.message ?? e.toString(),
        );
    }
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

  Future<T> _put<T>(String path, {dynamic data}) async {
    try {
      final res = await _dio.put<T>(path, data: data);
      return res.data as T;
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  Future<T> _delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
  }) async {
    try {
      final res = await _dio.delete<T>(
        path,
        queryParameters: queryParameters,
        data: data,
      );
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
    final data = await _get<Map<String, dynamic>>('/health');
    return Health.fromJson(data);
  }

  /// Calls the authenticated `/status` endpoint.
  Future<AgentStatus> fetchStatus() async {
    final data = await _get<Map<String, dynamic>>('/status');
    return AgentStatus.fromJson(data);
  }

  /// Fetches a single-use nonce for device-identity proof-of-possession —
  /// sign it with [DeviceIdentity] and pass the result to [pair], [register],
  /// or [login] as `signature`.
  Future<String> challenge() async {
    final data = await _post<Map<String, dynamic>>('/auth/challenge');
    return data['nonce'] as String;
  }

  /// Pair this device with the agent.
  ///
  /// Returns the [PairResponse] which contains the device token. The caller
  /// should capture [lastSeenFingerprint] (TOFU) immediately after and verify
  /// it against any fingerprint obtained via QR. [devicePublicKey]/[nonce]/
  /// [signature] prove possession of this device's identity key — see
  /// [DeviceIdentity] and [challenge].
  Future<PairResponse> pair({
    required String pairingCode,
    required String deviceLabel,
    required String devicePublicKey,
    required String nonce,
    required String signature,
    String? deviceId,
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/pair',
      data: {
        'pairingCode': pairingCode,
        'deviceLabel': deviceLabel,
        'devicePublicKey': devicePublicKey,
        'nonce': nonce,
        'signature': signature,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      },
    );
    return PairResponse.fromJson(data);
  }

  /// Creates the account used by [login] and pairs this device in the same
  /// step — requires a fresh one-time pairing code, exactly like [pair], so
  /// registration can't be done by a stranger on the network. Same response
  /// shape and device-identity proof as [pair].
  Future<PairResponse> register({
    required String pairingCode,
    required String username,
    required String password,
    required String deviceLabel,
    required String devicePublicKey,
    required String nonce,
    required String signature,
    String? deviceId,
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/register',
      data: {
        'pairingCode': pairingCode,
        'username': username,
        'password': password,
        'deviceLabel': deviceLabel,
        'devicePublicKey': devicePublicKey,
        'nonce': nonce,
        'signature': signature,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      },
    );
    return PairResponse.fromJson(data);
  }

  /// Log in with an account (created via [register] or `rfe-agent adduser`)
  /// — an additional way to obtain a device token alongside [pair], for
  /// repeat access without a fresh one-time code. Same response shape and
  /// device-identity proof as [pair].
  Future<PairResponse> login({
    required String username,
    required String password,
    required String deviceLabel,
    required String devicePublicKey,
    required String nonce,
    required String signature,
    String? deviceId,
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/login',
      data: {
        'username': username,
        'password': password,
        'deviceLabel': deviceLabel,
        'devicePublicKey': devicePublicKey,
        'nonce': nonce,
        'signature': signature,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      },
    );
    return PairResponse.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // WOL relay
  // ---------------------------------------------------------------------------

  /// Asks this agent to send a Wake-on-LAN magic packet to [mac] on its LAN.
  /// Used when the app is connected via Tailscale and can't broadcast directly.
  Future<void> sendWolRelay(String mac) async {
    await _post<Map<String, dynamic>>('/wol', data: {'mac': mac});
  }

  // ---------------------------------------------------------------------------
  // Filesystem — read
  // ---------------------------------------------------------------------------

  /// List available drives / mount points.
  Future<List<Drive>> drives() async {
    final data = await _get<List<dynamic>>('/system/drives');
    return data.map((e) => Drive.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// List a directory at [path].
  ///
  /// Pass [cursor] to page through large directories.
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    final data = await _get<Map<String, dynamic>>(
      '/fs',
      queryParameters: {
        'path': path,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
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

  /// Compute a file's checksum. Returns a hex-encoded hash string.
  Future<String> checksum(String path, {String algo = 'sha256'}) async {
    final data = await _get<Map<String, dynamic>>(
      '/fs/checksum',
      queryParameters: {'path': path, 'algo': algo},
    );
    return data['checksum'] as String;
  }

  /// Change the POSIX permissions of a file or directory.
  ///
  /// [mode] is an octal string like `"0755"`. Returns the updated [Entry].
  Future<Entry> chmod(String path, String mode) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/chmod',
      data: {'path': path, 'mode': mode},
    );
    return Entry.fromJson(data);
  }

  /// List the contents of an archive without extracting it.
  ///
  /// Supports `.zip`, `.tar.gz`, `.tgz`, and `.tar`. Returns at most [limit]
  /// entries (default 500 server-side).
  Future<List<ArchiveEntry>> archiveList(String path, {int? limit}) async {
    final data = await _get<Map<String, dynamic>>(
      '/fs/archive',
      queryParameters: {'path': path, if (limit != null) 'limit': limit},
    );
    final entries = (data['entries'] as List?) ?? const [];
    return entries
        .map((e) => ArchiveEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Compute checksums for multiple files in one request.
  ///
  /// Returns a map of path to hex-encoded hash. Files that could not be
  /// hashed are omitted from the map.
  Future<Map<String, String>> batchChecksums(
    List<String> paths, {
    String algo = 'sha256',
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/checksums',
      data: {'paths': paths, 'algo': algo},
    );
    final checksums = (data['checksums'] as List?) ?? const [];
    final result = <String, String>{};
    for (final item in checksums) {
      final m = item as Map<String, dynamic>;
      final hash = m['hash'] as String?;
      if (hash != null && hash.isNotEmpty) {
        result[m['path'] as String] = hash;
      }
    }
    return result;
  }

  /// Connect to the SSE event stream.
  ///
  /// Returns a broadcast [Stream] that emits parsed SSE data lines as raw
  /// JSON strings. The caller is responsible for parsing the JSON and
  /// handling reconnection.
  Stream<String> events() async* {
    try {
      final response = await _dio.get<ResponseBody>(
        '/events',
        options: Options(responseType: ResponseType.stream),
      );
      final stream = response.data?.stream;
      if (stream == null) return;

      String buffer = '';
      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.startsWith('data: ')) {
            yield line.substring(6);
          }
        }
      }
    } on DioException catch (e) {
      throw _apiError(e);
    }
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
      final res = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {
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
        },
        cancelToken: cancelToken,
      );
      return SearchResult.fromResponse(res.data ?? const [], res.headers.map);
    } on DioException catch (e) {
      _throwTransferError(e);
    }
  }

  /// Lists the most recently modified files (not directories) under the
  /// agent's configured roots, newest first — `GET /v1/fs/recent`.
  ///
  /// If [root] is provided the walk is constrained to that subtree.
  /// [limit] caps the number of results (server-side capped too).
  ///
  /// Like [search], the walk has a server-side time budget — check
  /// [SearchResult.timeBudgetHit] before treating the list as complete.
  Future<SearchResult> recent({String? root, int limit = 100}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/fs/recent',
        queryParameters: {'limit': limit, if (root != null) 'root': root},
      );
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
    String? agentName,
    bool? allowSharing,
  }) async {
    final data = await _patch<Map<String, dynamic>>(
      '/settings',
      data: {
        if (readOnly != null) 'readOnly': readOnly,
        if (agentName != null) 'agentName': agentName,
        if (allowSharing != null) 'allowSharing': allowSharing,
      },
    );
    return AgentSettings.fromJson(data);
  }

  Future<List<Device>> listDevices() async {
    final data = await _get<List<dynamic>>('/devices');
    return data.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Permanently removes a device row.
  ///
  /// As of the tightened trust model, the agent only accepts this for the
  /// CALLER'S OWN device (`?purge=true`) — targeting any other device
  /// returns 403 FORBIDDEN. Used by [SettingsScreen]'s "Disconnect this
  /// device" action to un-pair the current phone.
  Future<void> deleteDevice(String id) async {
    await _delete<void>('/devices/$id', queryParameters: {'purge': 'true'});
  }

  // ---------------------------------------------------------------------------
  // R1 — one-time share links
  // ---------------------------------------------------------------------------

  /// Mints a one-time share link for [path]. Throws [AgentApiException] with
  /// statusCode 403 if the agent's "Enable share links" setting is off.
  Future<ShareLink> mintShareLink(
    String path, {
    Duration expiresIn = const Duration(minutes: 15),
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/share/mint',
      data: {'path': path, 'expiresInSeconds': expiresIn.inSeconds},
    );
    return ShareLink.fromJson(data);
  }

  /// Revokes an active share link, identified by its hash
  /// ([ShareLink.tokenHash], not the raw token).
  Future<void> revokeShareLink(String tokenHash) async {
    await _delete<void>('/share/$tokenHash');
  }

  /// Lists active (unexpired) share links.
  Future<List<ShareLink>> listShareLinks() async {
    final data = await _get<List<dynamic>>('/share');
    return data
        .map((e) => ShareLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Bandwidth
  // ---------------------------------------------------------------------------

  Future<BandwidthSettings> getBandwidth() async {
    final data = await _get<Map<String, dynamic>>('/settings/bandwidth');
    return BandwidthSettings.fromJson(data);
  }

  Future<BandwidthSettings> setBandwidth({
    int? maxUploadBytesPerSec,
    int? maxDownloadBytesPerSec,
  }) async {
    final data = await _put<Map<String, dynamic>>(
      '/settings/bandwidth',
      data: {
        if (maxUploadBytesPerSec != null)
          'maxUploadBytesPerSec': maxUploadBytesPerSec,
        if (maxDownloadBytesPerSec != null)
          'maxDownloadBytesPerSec': maxDownloadBytesPerSec,
      },
    );
    return BandwidthSettings.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — write
  // ---------------------------------------------------------------------------

  Future<Entry> createFolder(String path) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/folder',
      data: {'path': path},
    );
    return Entry.fromJson(data);
  }

  Future<Entry> createFile(String path) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/file',
      data: {'path': path},
    );
    return Entry.fromJson(data);
  }

  Future<Entry> rename(String src, String dst) async {
    final data = await _patch<Map<String, dynamic>>(
      '/fs/rename',
      data: {'src': src, 'dst': dst},
    );
    return Entry.fromJson(data);
  }

  /// Copies [sources] into [destDir].
  ///
  /// Collision precedence (server-side): [duplicate] `true` wins — colliding
  /// items are auto-renamed ("keep both"); otherwise [overwrite] `true`
  /// replaces the existing item; otherwise a colliding item comes back as a
  /// per-item `CONFLICT` result in the response's `results` list.
  Future<BatchResult> copy(
    List<String> sources,
    String destDir, {
    bool duplicate = false,
    bool overwrite = false,
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/copy',
      data: {
        'sources': sources,
        'destDir': destDir,
        'duplicate': duplicate,
        'overwrite': overwrite,
      },
    );
    return BatchResult.fromJson(data);
  }

  /// Moves [sources] into [destDir]. See [copy] for the [duplicate] /
  /// [overwrite] collision precedence.
  Future<BatchResult> move(
    List<String> sources,
    String destDir, {
    bool duplicate = false,
    bool overwrite = false,
  }) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/move',
      data: {
        'sources': sources,
        'destDir': destDir,
        'duplicate': duplicate,
        'overwrite': overwrite,
      },
    );
    return BatchResult.fromJson(data);
  }

  /// Deletes [paths]. By default this is **reversible** — the agent moves them
  /// to the trash (recoverable via [listTrash] / [restoreTrash]). Pass
  /// [permanent] `true` to hard-delete (recursive, irreversible).
  Future<BatchResult> delete(
    List<String> paths, {
    bool permanent = false,
  }) async {
    final data = await _delete<Map<String, dynamic>>(
      '/fs',
      queryParameters: permanent ? {'permanent': 'true'} : null,
      data: {'paths': paths},
    );
    return BatchResult.fromJson(data);
  }

  /// Lists items currently in the trash, newest first.
  Future<List<TrashEntry>> listTrash() async {
    final data = await _get<Map<String, dynamic>>('/trash');
    final items = (data['items'] as List?) ?? const [];
    return items
        .map((e) => TrashEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Restores trashed items (by [ids]) to their original locations.
  Future<BatchResult> restoreTrash(List<String> ids) async {
    final data = await _post<Map<String, dynamic>>(
      '/trash/restore',
      data: {'ids': ids},
    );
    return BatchResult.fromJson(data);
  }

  /// Permanently empties the trash. With [ids] only those items are purged;
  /// otherwise the whole trash is emptied.
  Future<void> emptyTrash({List<String>? ids}) async {
    await _delete<Map<String, dynamic>>(
      '/trash',
      data: ids == null ? null : {'ids': ids},
    );
  }

  /// Compresses [sources] into a new zip archive at [dest].
  ///
  /// If [dest] already exists the agent auto-renames it ("keep both"), so this
  /// never clobbers an existing file. Returns the created archive's [Entry] —
  /// whose `path`/`name` reflect the actual (possibly auto-renamed) file.
  Future<Entry> compress(List<String> sources, String dest) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/compress',
      data: {'sources': sources, 'dest': dest},
    );
    return Entry.fromJson(data);
  }

  /// Extracts [archive] (a `.zip`, `.tar.gz` or `.tgz`) into [destDir],
  /// which is created if absent. The agent guards every entry against
  /// zip-slip. Returns the destination directory's [Entry].
  Future<Entry> extract(String archive, String destDir) async {
    final data = await _post<Map<String, dynamic>>(
      '/fs/extract',
      data: {'archive': archive, 'destDir': destDir},
    );
    return Entry.fromJson(data);
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
        // Resumed download: never request gzip (the server already skips
        // compression for any Range request — see downloadHandler — but
        // sending the header here would falsely imply we want it on this
        // path).
        headers['Range'] = 'bytes=$startByte-';
      } else if (await _wantsGzip()) {
        headers['Accept-Encoding'] = 'gzip';
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

  /// Opens a streaming GET to `/content` for [remotePath], forwarding
  /// [rangeHeader] verbatim if given.
  ///
  /// Used by the video-preview loopback proxy ([VideoLoopbackProxy]) so
  /// `video_player` can request byte ranges over a plain local HTTP
  /// connection without knowing about this client's TLS pinning or bearer
  /// auth — the proxy does that dance here and just relays bytes.
  Future<Response<ResponseBody>> openContentStream(
    String remotePath, {
    String? rangeHeader,
  }) {
    return _dio.get<ResponseBody>(
      '/content',
      queryParameters: {'path': remotePath},
      options: Options(
        headers: {if (rangeHeader != null) 'Range': rangeHeader},
        responseType: ResponseType.stream,
      ),
    );
  }

  /// Default cap for [fetchBytes] when the caller doesn't pass its own —
  /// generous enough for any real preview/small-file use, small enough to
  /// backstop a stale-metadata or attacker-controlled remote size from
  /// exhausting memory (PR-28).
  static const int kFetchBytesDefaultMaxBytes = 64 * 1024 * 1024;

  /// Fetch the full contents of [remotePath] into memory as raw bytes.
  ///
  /// Intended for small-ish files (previews of images/text/PDFs). Streams
  /// the response and aborts as soon as more than [maxBytes] have arrived —
  /// throwing [FetchTooLargeException] — rather than trusting the remote
  /// file's reported size and buffering it unbounded (PR-28).
  Future<Uint8List> fetchBytes(
    String remotePath, {
    CancelToken? cancelToken,
    int maxBytes = kFetchBytesDefaultMaxBytes,
  }) async {
    try {
      final headers = <String, dynamic>{};
      if (await _wantsGzip()) {
        headers['Accept-Encoding'] = 'gzip';
      }
      final res = await _dio.get<ResponseBody>(
        '/content',
        queryParameters: {'path': remotePath},
        options: Options(responseType: ResponseType.stream, headers: headers),
        cancelToken: cancelToken,
      );
      final bytes = await collectBytesCapped(
        res.data!.stream,
        remotePath,
        maxBytes,
      );

      // Cache bytes when the parent folder is pinned (fire-and-forget).
      final cache = offlineBodyCache;
      final pinCheck = isPinnedFolder;
      if (cache != null &&
          pinCheck != null &&
          pinCheck(host.id, _parentOf(remotePath))) {
        cache.put(host.id, remotePath, bytes).ignore();
      }

      return bytes;
    } on DioException catch (e) {
      // Offline fallback: only for a genuinely unreachable agent (PR-56) —
      // see isConnectivityFailure.
      if (isConnectivityFailure(e.type)) {
        final cached = await offlineBodyCache?.get(host.id, remotePath);
        if (cached != null) return cached;
      }
      throw _apiError(e);
    }
  }

  /// Overwrites the file at [remotePath] with [bytes] (max 5 MiB).
  ///
  /// Pass [baseModified] — typically the [Entry.modified] timestamp last
  /// read for this file — for optimistic concurrency: the agent rejects the
  /// write with [StaleWriteException] if the file changed on disk since
  /// then. Omit it (or pass `null`) to force an overwrite regardless of
  /// concurrent changes.
  ///
  /// Returns the updated [Entry]; use its `modified` as the new
  /// [baseModified] for any subsequent save.
  ///
  /// Throws:
  /// - [ReadOnlyException] if the agent is in read-only mode (`403
  ///   READ_ONLY`).
  /// - [StaleWriteException] if the file changed on disk since
  ///   [baseModified] (`409 STALE_WRITE`).
  /// - [PayloadTooLargeException] if [bytes] is too large to save (`413
  ///   PAYLOAD_TOO_LARGE`).
  /// - [AgentApiException] for any other error response.
  Future<Entry> putContent(
    String remotePath,
    Uint8List bytes, {
    DateTime? baseModified,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/content',
        data: Stream.fromIterable([bytes]),
        queryParameters: {
          'path': remotePath,
          if (baseModified != null)
            'baseModified': baseModified.toUtc().toIso8601String(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );
      return Entry.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final err = _apiError(e);
      switch (err.code) {
        case 'READ_ONLY':
          throw ReadOnlyException(err.message);
        case 'STALE_WRITE':
          throw StaleWriteException(err.message);
        case 'PAYLOAD_TOO_LARGE':
          throw PayloadTooLargeException(err.message);
        default:
          throw err;
      }
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
    final data = await _post<Map<String, dynamic>>(
      '/transfers',
      data: {
        'path': path,
        'size': size,
        'sha256': sha256Hex,
        'chunkSize': chunkSize,
        'overwrite': overwrite,
      },
    );
    return UploadSession.fromJson(data);
  }

  /// Get the current status of an upload session (for resume).
  Future<UploadSession> getUploadSession(String id) async {
    final data = await _get<Map<String, dynamic>>('/transfers/$id');
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
  ///
  /// The agent's 200 response includes the usual [Entry] fields plus
  /// `sha256` (the verified whole-file SHA-256) and `verified: true`. Older
  /// agents that predate integrity verification won't send those two fields
  /// — [UploadCompleteResult.fromJson] treats their absence as "not
  /// verified" rather than crashing.
  Future<UploadCompleteResult> completeUpload(String sessionId) async {
    final data = await _post<Map<String, dynamic>>(
      '/transfers/$sessionId/complete',
    );
    return UploadCompleteResult.fromJson(data);
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

  /// Downloads the latest APK to [localFile], reporting [onProgress] as
  /// *absolute* bytes received / total (i.e. including any [startByte] already
  /// on disk), so the percentage stays honest across a resume.
  ///
  /// Supports HTTP Range resumption — the same mechanism as [downloadFile].
  /// Pass [startByte] to skip data already present in [localFile] (it must
  /// already contain exactly [startByte] bytes); 0 (the default) starts a
  /// fresh download that overwrites/truncates the file. The 77 MB APK over
  /// cellular/Tailscale is the download most likely to be interrupted, so a
  /// dropped connection should leave the partial file in place for a resume
  /// rather than forcing a full re-download — hence `deleteOnError: false`.
  ///
  /// If a ranged request (`startByte > 0`) is answered with a full `200 OK`
  /// instead of `206 Partial Content`, the (now-corrupt) partial is deleted
  /// and [RangeNotSatisfiedException] is thrown so the caller restarts from 0.
  ///
  /// Pass [cancelToken] to allow aborting an in-flight download (e.g. the
  /// user taps Cancel on the update progress dialog). A cancellation surfaces
  /// as a [DioException] with [DioExceptionType.cancel] rather than
  /// [AgentApiException], matching [search] and [downloadFile] — callers can
  /// distinguish "user cancelled" from a real download failure.
  Future<void> downloadApk({
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
        '/app/download',
        localFile.path,
        options: Options(headers: headers, responseType: ResponseType.stream),
        deleteOnError: false,
        cancelToken: cancelToken,
        fileAccessMode:
            startByte > 0 ? FileAccessMode.append : FileAccessMode.write,
        // Report absolute progress so a resumed download doesn't restart at 0%.
        onReceiveProgress:
            onProgress == null
                ? null
                : (received, total) => onProgress(
                  startByte + received,
                  total > 0 ? startByte + total : total,
                ),
      );

      if (startByte > 0 && response.statusCode != 206) {
        // Server ignored Range and sent the whole file, which we just appended
        // onto the existing partial — it's now corrupt. Delete and signal the
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
}
