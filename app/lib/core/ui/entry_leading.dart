import 'package:flutter/material.dart';

import '../models/entry.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
  'heic',
  'heif',
  'svg',
  'tiff',
  'ico',
};

/// Video file extensions (e.g. `clip.mp4`).
const Set<String> videoExtensions = {
  'mp4',
  'mov',
  'mkv',
  'avi',
  'webm',
  'm4v',
  '3gp',
  'flv',
  'wmv',
};

/// Audio file extensions (e.g. `track.mp3`).
const Set<String> audioExtensions = {
  'mp3',
  'wav',
  'flac',
  'aac',
  'ogg',
  'm4a',
  'wma',
  'opus',
};

/// Archive/compressed file extensions (e.g. `bundle.zip`).
const Set<String> archiveExtensions = {
  'zip',
  'rar',
  '7z',
  'tar',
  'gz',
  'bz2',
  'xz',
  'tgz',
};

/// Document file extensions (e.g. `report.pdf`).
const Set<String> docExtensions = {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'odt',
  'ods',
  'odp',
  'txt',
  'md',
  'rtf',
  'csv',
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
  const _IconSpec(this.icon, this.color, this.bg);
  final IconData icon;
  final Color? color;

  /// Figma's per-type tonal chip background (dark theme only — see
  /// [figmaIconBg]).
  final Color bg;
}

// RFE mockup file-type palette (`rfe-full-remake-mockups-2026-07`, Files tab
// row icons): folder/generic-document = primary blue, image/video = violet,
// PDF = red, archive = amber, plain text/other = neutral (no tint — matches
// the mockup's un-classed `.row-icon`). Dark-tonal chip background behind
// each icon mirrors the mockup's `--*-tint` CSS vars.
const Color _folderColor = Color(0xFF4C8DFF); // --primary
const Color _folderBg = Color(0x244C8DFF); // --primary-tint
const Color _imageColor = Color(0xFF9B87F5); // --violet
const Color _imageBg = Color(0x249B87F5); // --violet-tint
const Color _pdfColor = Color(0xFFF1596B); // --red
const Color _pdfBg = Color(0x24F1596B); // --red-tint
const Color _archiveColor = Color(0xFFF3A73F); // --amber
const Color _archiveBg = Color(0x24F3A73F); // --amber-tint
const Color _otherBg = Color(0xFF191C24); // --surface-2 (neutral, no tint)

_IconSpec _iconSpecFor(Entry entry) {
  if (entry.isDir) {
    return const _IconSpec(LucideIcons.folder, _folderColor, _folderBg);
  }
  final mime = entry.mimeType ?? '';
  switch (categoryOf(entry)) {
    case EntryCategory.folder:
      return const _IconSpec(LucideIcons.folder, _folderColor, _folderBg);
    case EntryCategory.image:
      return const _IconSpec(LucideIcons.image, _imageColor, _imageBg);
    case EntryCategory.video:
      return const _IconSpec(LucideIcons.video, _imageColor, _imageBg);
    case EntryCategory.audio:
      return const _IconSpec(LucideIcons.music, null, _otherBg);
    case EntryCategory.archive:
      return const _IconSpec(
        LucideIcons.fileArchive,
        _archiveColor,
        _archiveBg,
      );
    case EntryCategory.document:
      if (mime.contains('pdf')) {
        return const _IconSpec(LucideIcons.fileText, _pdfColor, _pdfBg);
      }
      // Plain text/markdown reads as a neutral "generic file" in the
      // mockup (no tint); other office docs (docx/xlsx/...) share the
      // folder's primary-blue tonal treatment.
      if (mime.startsWith('text/')) {
        return const _IconSpec(LucideIcons.fileText, null, _otherBg);
      }
      return const _IconSpec(LucideIcons.fileText, _folderColor, _folderBg);
    case EntryCategory.other:
      return const _IconSpec(LucideIcons.file, null, _otherBg);
  }
}

/// Figma's per-type tonal chip background for [entry]'s icon container.
/// Dark-theme-only (the Figma spec has no light variant) — callers fall back
/// to their own scheme-derived background in light theme.
Color figmaIconBg(Entry entry) => _iconSpecFor(entry).bg;

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
