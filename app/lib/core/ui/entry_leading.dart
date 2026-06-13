import 'package:flutter/material.dart';

import '../models/entry.dart';

/// Broad file-type categories used for icon selection, mirroring the
/// server's category table (`folder`, `image`, `video`, `audio`, `document`,
/// `archive`, `other`) and the search filter's [SearchCategory] values.
enum EntryCategory { folder, image, video, audio, document, archive, other }

// ---------------------------------------------------------------------------
// Category extension sets
// ---------------------------------------------------------------------------
//
// File-extension tables (lowercase, without the leading dot) for the
// categories that have a corresponding file-visibility preset
// (`core/storage/visibility_prefs.dart`). [categoryOf] above resolves a
// category from [Entry.isDir]/[Entry.mimeType] for icon selection; these
// extension sets are a separate, name-based signal used to let users hide
// entire categories of files regardless of whether the agent reported a
// MIME type.

/// Image file extensions (e.g. `photo.png`).
const Set<String> imageExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'heic', 'heif', 'svg', 'tiff',
  'ico',
};

/// Video file extensions (e.g. `clip.mp4`).
const Set<String> videoExtensions = {
  'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v', '3gp', 'flv', 'wmv',
};

/// Audio file extensions (e.g. `track.mp3`).
const Set<String> audioExtensions = {
  'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus',
};

/// Archive/compressed file extensions (e.g. `bundle.zip`).
const Set<String> archiveExtensions = {
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz',
};

/// Document file extensions (e.g. `report.pdf`).
const Set<String> docExtensions = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
  'txt', 'md', 'rtf', 'csv',
};

/// Resolves the [EntryCategory] for [entry] from [Entry.isDir] and
/// [Entry.mimeType], using the same MIME-prefix rules used for icon
/// selection across the explorer and search screens.
EntryCategory categoryOf(Entry entry) {
  if (entry.isDir) return EntryCategory.folder;
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('image/')) return EntryCategory.image;
  if (mime.startsWith('video/')) return EntryCategory.video;
  if (mime.startsWith('audio/')) return EntryCategory.audio;
  if (mime.contains('pdf')) return EntryCategory.document;
  if (mime.contains('zip') || mime.contains('archive')) {
    return EntryCategory.archive;
  }
  if (mime.startsWith('text/') || mime.contains('json')) {
    return EntryCategory.document;
  }
  return EntryCategory.other;
}

/// A single file-type icon glyph + tint, by [EntryCategory] and (for
/// `document`) the specific MIME type — pdf and text/json render distinct
/// icons even though both are "documents".
class _IconSpec {
  const _IconSpec(this.icon, this.color);
  final IconData icon;
  final Color? color;
}

_IconSpec _iconSpecFor(Entry entry) {
  if (entry.isDir) return const _IconSpec(Icons.folder, Colors.amber);
  final mime = entry.mimeType ?? '';
  switch (categoryOf(entry)) {
    case EntryCategory.folder:
      return const _IconSpec(Icons.folder, Colors.amber);
    case EntryCategory.image:
      return const _IconSpec(Icons.image, Colors.blue);
    case EntryCategory.video:
      return const _IconSpec(Icons.movie, Colors.purple);
    case EntryCategory.audio:
      return const _IconSpec(Icons.music_note, Colors.green);
    case EntryCategory.archive:
      return const _IconSpec(Icons.folder_zip, Colors.orange);
    case EntryCategory.document:
      if (mime.contains('pdf')) {
        return const _IconSpec(Icons.picture_as_pdf, Colors.red);
      }
      return const _IconSpec(Icons.description, Colors.teal);
    case EntryCategory.other:
      return const _IconSpec(Icons.insert_drive_file, null);
  }
}

/// File-type icon for [entry] — centralises the category/MIME → icon + tint
/// mapping shared by the explorer's list tile, grid cell, and search result
/// tile so all three stay visually in sync.
///
/// This renders only the glyph (matching the previous `_EntryIcon` /
/// `_resultIcon` private widgets); callers that show a tonal container or
/// thumbnail around it keep doing so themselves.
class EntryLeading extends StatelessWidget {
  const EntryLeading({super.key, required this.entry, this.size = 24});

  final Entry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = _iconSpecFor(entry);
    return Icon(spec.icon, size: size, color: spec.color);
  }
}
