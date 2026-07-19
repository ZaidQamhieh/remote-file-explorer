import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges to the native MediaStore API so downloaded files land in the public
/// **Downloads** collection (visible in the system Files app), instead of the
/// app-private storage Android otherwise restricts us to.
class DownloadSaver {
  static const _channel = MethodChannel('rfe/downloads');

  /// Moves [sourceFile] into the public Downloads folder on Android and returns
  /// a human-readable location (e.g. "Downloads/report.pdf"). The staging copy
  /// is deleted afterwards. On other platforms the original path is returned.
  ///
  /// Throws [DownloadSaveCancelled] if the native side reports no result
  /// (cancellation or platform failure) — the staging copy is kept in that
  /// case, not deleted, since it may be the only copy of the download
  /// (PR-57). Callers already route any thrown error to a failed-transfer
  /// state (see `transfer_state.dart`'s `_runTransfer` catch-all).
  static Future<String> saveToDownloads(
    File sourceFile,
    String fileName,
    String mimeType,
  ) async {
    if (!Platform.isAndroid) return sourceFile.path;

    final saved = requireSaved(
      await _channel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': sourceFile.path,
        'fileName': fileName,
        'mimeType': mimeType,
      }),
      fileName,
    );

    // Remove the app-private staging copy now that it's confirmed in
    // Downloads.
    try {
      if (await sourceFile.exists()) await sourceFile.delete();
    } catch (_) {}

    return saved;
  }
}

/// Turns the native channel's raw result into either a confirmed
/// destination or a thrown [DownloadSaveCancelled] — a `null` result means
/// the native side didn't confirm a save (cancellation or platform
/// failure), and must never be turned into an invented success (PR-57).
/// Pure and unit-testable on its own.
String requireSaved(String? saved, String fileName) {
  if (saved == null) throw DownloadSaveCancelled(fileName);
  return saved;
}

/// Thrown by [DownloadSaver.saveToDownloads] when the native save didn't
/// report a destination — the download must not be reported as saved, and
/// its staging copy is kept rather than deleted (PR-57).
class DownloadSaveCancelled implements Exception {
  DownloadSaveCancelled(this.fileName);
  final String fileName;

  @override
  String toString() => 'Save to Downloads was cancelled or failed: $fileName';
}
