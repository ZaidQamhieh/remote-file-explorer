import 'package:connectivity_plus/connectivity_plus.dart';
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
}
