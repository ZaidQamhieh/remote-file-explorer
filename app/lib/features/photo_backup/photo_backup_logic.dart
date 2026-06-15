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
