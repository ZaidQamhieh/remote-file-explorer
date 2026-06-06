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
  static Future<String> saveToDownloads(
    File sourceFile,
    String fileName,
    String mimeType,
  ) async {
    if (!Platform.isAndroid) return sourceFile.path;

    final saved = await _channel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': sourceFile.path,
      'fileName': fileName,
      'mimeType': mimeType,
    });

    // Remove the app-private staging copy now that it's in Downloads.
    try {
      if (await sourceFile.exists()) await sourceFile.delete();
    } catch (_) {}

    return saved ?? 'Downloads/$fileName';
  }
}
