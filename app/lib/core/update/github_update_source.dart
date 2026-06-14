import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../api/agent_client.dart' show RangeNotSatisfiedException;
import '../models/app_release.dart';

/// Hardcoded GitHub repo that publishes app releases (CD workflow
/// `.github/workflows/release.yml`). Keep this in one place so it's easy to
/// find if the repo is ever renamed/moved.
const String githubReleaseRepo = 'ZaidQamhieh/remote-file-explorer';

/// Stable redirect to the latest release's `latest.json` manifest asset.
const String githubLatestManifestUrl =
    'https://github.com/$githubReleaseRepo/releases/latest/download/latest.json';

/// App-wide (host-independent) update source backed by GitHub Releases.
///
/// Mirrors the resilience of [AgentClient.downloadApk] — HTTP Range resume,
/// append-on-resume, a 206-vs-200 guard that throws
/// [RangeNotSatisfiedException] on a failed resume, and `deleteOnError:
/// false` so a dropped connection leaves a resumable partial — but talks to
/// plain public HTTPS endpoints with standard TLS (no certificate pinning).
class GithubUpdateSource {
  GithubUpdateSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Fetches and parses the `latest.json` manifest from GitHub's stable
  /// "latest release" redirect. Returns `null` only if the response body is
  /// empty; network/HTTP errors are rethrown as [DioException] so callers can
  /// distinguish "checked, no release" from "the check itself failed".
  Future<AppRelease?> latestRelease() async {
    // GitHub serves release assets with a non-JSON content type
    // (octet-stream), so Dio does NOT auto-decode the body — it returns a
    // String. Fetch it as plain text and parse it ourselves; requesting
    // <Map> here caused a "String is not a subtype of Map" cast crash.
    final res = await _dio.get<String>(
      githubLatestManifestUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final body = res.data;
    if (body == null || body.trim().isEmpty) return null;
    final data = jsonDecode(body) as Map<String, dynamic>;
    return AppRelease.fromJson(data);
  }

  /// Downloads the APK referenced by [release]'s `url` to [localFile],
  /// reporting [onProgress] as *absolute* bytes received / total (i.e.
  /// including any [startByte] already on disk), so the percentage stays
  /// honest across a resume.
  ///
  /// Supports HTTP Range resumption: pass [startByte] to skip data already
  /// present in [localFile] (it must already contain exactly [startByte]
  /// bytes); 0 (the default) starts a fresh download that
  /// overwrites/truncates the file.
  ///
  /// If a ranged request (`startByte > 0`) is answered with a full `200 OK`
  /// instead of `206 Partial Content`, the (now-corrupt) partial is deleted
  /// and [RangeNotSatisfiedException] is thrown so the caller restarts from
  /// 0 — matching [AgentClient.downloadApk].
  ///
  /// Pass [cancelToken] to allow aborting an in-flight download (e.g. the
  /// user taps Cancel on the update progress dialog). A cancellation
  /// surfaces as a [DioException] with [DioExceptionType.cancel].
  Future<void> downloadApk({
    required AppRelease release,
    required File localFile,
    int startByte = 0,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = release.url;
    if (url == null || url.isEmpty) {
      throw ArgumentError('AppRelease.url is required to download the APK');
    }

    final headers = <String, dynamic>{};
    if (startByte > 0) {
      headers['Range'] = 'bytes=$startByte-';
    }
    final response = await _dio.download(
      url,
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
  }
}
