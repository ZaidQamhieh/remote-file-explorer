/// Pure helpers for photo backup (Wave 3 / #11). Kept free of plugins so the
/// path layout + dedupe selection are unit-testable; the controller wires
/// these to photo_manager / the transfer queue.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Two-digit zero-padded string for the date-folder layout.
String _two(int n) => n.toString().padLeft(2, '0');

String safeRemoteSegment(String raw, {required String fallback}) {
  var segment = raw.split(RegExp(r'[/\\]')).last.trim();
  segment = segment.replaceAll(RegExp(r'[\x00-\x1f\x7f:*?"<>|]'), '_');
  segment = segment.replaceFirst(RegExp(r'[. ]+$'), '');
  if (segment.isEmpty || segment == '.' || segment == '..') return fallback;
  final stem = segment.split('.').first;
  if (RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  ).hasMatch(stem)) {
    return fallback;
  }
  if (segment.length > 120) segment = segment.substring(0, 120);
  return segment;
}

String photoBackupFileName({
  required String assetId,
  required String suggestedName,
  required String localPath,
}) {
  final suggested = safeRemoteSegment(suggestedName, fallback: 'photo');
  final local = safeRemoteSegment(localPath, fallback: 'photo');
  final extensionSource = suggested.contains('.') ? suggested : local;
  final dot = extensionSource.lastIndexOf('.');
  final candidateExtension =
      dot >= 0 ? extensionSource.substring(dot).toLowerCase() : '';
  final extension =
      RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(candidateExtension)
          ? candidateExtension
          : '.jpg';
  final stemWithExtension =
      suggested.endsWith(extension)
          ? suggested.substring(0, suggested.length - extension.length)
          : suggested;
  final stem = safeRemoteSegment(stemWithExtension, fallback: 'photo');
  final suffix = sha256
      .convert(utf8.encode(assetId))
      .toString()
      .substring(0, 12);
  final maxStem = 120 - suffix.length - extension.length - 1;
  final boundedStem = stem.length > maxStem ? stem.substring(0, maxStem) : stem;
  return '$boundedStem-$suffix$extension';
}

/// Builds the remote destination path for a photo:
/// `<destRoot>/[deviceSegment/]YYYY/YYYY-MM/<name>`, using [created] (the
/// photo's capture date) for the date folders. The returned path always uses
/// `/` separators (the agent normalizes per-OS) and avoids a leading double
/// slash when [destRoot] is the filesystem root.
///
/// [deviceSegment], when non-empty, is inserted right after [destRoot] so
/// multiple phones backing up to the same shared destRoot don't interleave
/// their photos in one folder.
String backupRemotePath({
  required String destRoot,
  required DateTime created,
  required String name,
  String deviceSegment = '',
}) {
  final year = created.year.toString();
  final month = '$year-${_two(created.month)}';
  // Normalize destRoot: drop a trailing slash; treat '/' (root) as empty so we
  // don't produce '//YYYY'.
  var root = destRoot;
  while (root.length > 1 && root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  if (root == '/') root = '';
  final safeName = safeRemoteSegment(name, fallback: 'photo');
  final safeDevice =
      deviceSegment.isEmpty
          ? ''
          : safeRemoteSegment(deviceSegment, fallback: 'device');
  final dateFolders =
      safeDevice.isEmpty ? '$year/$month' : '$safeDevice/$year/$month';
  return '$root/$dateFolders/$safeName';
}

/// Returns the subset of [allIds] (photo asset ids) not present in
/// [backedUp] — i.e. the photos still needing upload, preserving order.
List<String> pendingIds(List<String> allIds, Set<String> backedUp) =>
    allIds.where((id) => !backedUp.contains(id)).toList();

/// Which album ids to actually scan given the user's [selected] set and the
/// [available] albums on the device. An empty [selected] means "all photos" →
/// every available album; otherwise the selection filtered to albums that
/// still exist (a selected album the user later deleted is silently dropped).
List<String> albumsToScan(List<String> available, Set<String> selected) =>
    selected.isEmpty ? available : available.where(selected.contains).toList();

/// True once two reads of [readLength] taken [interval] apart agree and are
/// non-zero.
///
/// The plain "skip if zero-byte" check (v1.20.0) only catches a file that
/// hasn't started materializing yet. It misses the more common case: the
/// media store/cloud-sync client is still *writing* the file when
/// `photo_manager` hands us the path, so the length is non-zero but still
/// growing — uploading it races the write and ships a truncated photo. A
/// second read after a short delay catches that: a length still changing
/// means "not ready yet, try again next run" instead of "looks done, go".
Future<bool> isFileStable(
  Future<int> Function() readLength, {
  Future<void> Function(Duration) wait = Future.delayed,
  Duration interval = const Duration(milliseconds: 300),
}) async {
  final first = await readLength();
  if (first <= 0) return false;
  await wait(interval);
  final second = await readLength();
  return second == first;
}
