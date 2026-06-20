import 'dart:io';

import 'package:flutter/services.dart';

/// Opens a local file with the system's default handler (ACTION_VIEW on
/// Android). Uses the same `rfe/downloads` method channel as [DownloadSaver]
/// and the APK installer — the native side hands the file to another app via
/// FileProvider so read permission is granted automatically.
///
/// [mimeType] should match the file's actual content type so Android picks the
/// right handler. Falls back to `application/octet-stream` when unknown.
class FileOpener {
  static const _channel = MethodChannel('rfe/downloads');

  /// Opens [file] with the system's default app for [mimeType]. Returns `true`
  /// on success. On non-Android platforms this is a no-op (returns `false`).
  static Future<bool> open(File file, String mimeType) async {
    if (!Platform.isAndroid) return false;

    final result = await _channel.invokeMethod<bool>('openFile', {
      'path': file.path,
      'mimeType': mimeType,
    });
    return result ?? false;
  }
}
