/// Pure helpers for photo backup (Wave 3 / #11). Kept free of plugins so the
/// path layout + dedupe selection are unit-testable; the controller wires
/// these to photo_manager / the transfer queue.
library;

/// Two-digit zero-padded string for the date-folder layout.
String _two(int n) => n.toString().padLeft(2, '0');

/// Builds the remote destination path for a photo: `<destRoot>/YYYY/YYYY-MM/<name>`,
/// using [created] (the photo's capture date) for the date folders. The
/// returned path always uses `/` separators (the agent normalizes per-OS) and
/// avoids a leading double slash when [destRoot] is the filesystem root.
String backupRemotePath({
  required String destRoot,
  required DateTime created,
  required String name,
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
  return '$root/$year/$month/$name';
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
