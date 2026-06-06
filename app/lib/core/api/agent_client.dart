import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/health.dart';
import '../models/host.dart';

/// Thrown when an agent's TLS certificate does not match the pinned fingerprint.
class CertPinMismatch implements Exception {
  CertPinMismatch(this.expected, this.actual);
  final String expected;
  final String actual;
  @override
  String toString() => 'Certificate fingerprint mismatch '
      '(expected $expected, got $actual)';
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

  /// Calls the unauthenticated `/health` endpoint.
  Future<Health> health() async {
    final res = await _dio.get<Map<String, dynamic>>('/health');
    return Health.fromJson(res.data ?? const {});
  }
}
