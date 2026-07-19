import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';

// S3 — pure decision seam for "should this download request send
// Accept-Encoding: gzip". Actual Dio/gzip behavior isn't tested here (not
// ours to test); only the setting + connectivity -> bool logic.
void main() {
  test('setting off never requests gzip, even on cellular', () {
    expect(
      shouldRequestGzipDownload(
        settingEnabled: false,
        connectivity: [ConnectivityResult.mobile],
      ),
      isFalse,
    );
  });

  test('setting on + cellular requests gzip', () {
    expect(
      shouldRequestGzipDownload(
        settingEnabled: true,
        connectivity: [ConnectivityResult.mobile],
      ),
      isTrue,
    );
  });

  test('setting on + wifi does not request gzip', () {
    expect(
      shouldRequestGzipDownload(
        settingEnabled: true,
        connectivity: [ConnectivityResult.wifi],
      ),
      isFalse,
    );
  });

  test('setting on + ethernet does not request gzip', () {
    expect(
      shouldRequestGzipDownload(
        settingEnabled: true,
        connectivity: [ConnectivityResult.ethernet],
      ),
      isFalse,
    );
  });

  test('mixed mobile+wifi (e.g. VPN over wifi) does not request gzip', () {
    expect(
      shouldRequestGzipDownload(
        settingEnabled: true,
        connectivity: [ConnectivityResult.mobile, ConnectivityResult.wifi],
      ),
      isFalse,
    );
  });

  test('no connectivity does not request gzip', () {
    expect(
      shouldRequestGzipDownload(
        settingEnabled: true,
        connectivity: [ConnectivityResult.none],
      ),
      isFalse,
    );
  });

  group('isSafeToRetryOnFallback (PR-23)', () {
    test('GET and HEAD are safe, any case', () {
      expect(isSafeToRetryOnFallback('GET'), isTrue);
      expect(isSafeToRetryOnFallback('get'), isTrue);
      expect(isSafeToRetryOnFallback('HEAD'), isTrue);
    });

    test('POST/PATCH/PUT/DELETE are not safe to auto-retry', () {
      for (final m in ['POST', 'PATCH', 'PUT', 'DELETE']) {
        expect(isSafeToRetryOnFallback(m), isFalse, reason: m);
      }
    });
  });

  group('isConnectivityFailure (PR-56)', () {
    test('connection/timeout errors are treated as unreachable', () {
      for (final t in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(isConnectivityFailure(t), isTrue, reason: t.toString());
      }
    });

    test('a real response (auth/authz/not-found) or a bad cert is NOT '
        'unreachable — must not trigger the offline fallback', () {
      expect(isConnectivityFailure(DioExceptionType.badResponse), isFalse);
      expect(isConnectivityFailure(DioExceptionType.badCertificate), isFalse);
      expect(isConnectivityFailure(DioExceptionType.cancel), isFalse);
    });
  });
}
