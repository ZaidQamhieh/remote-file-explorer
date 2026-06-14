import '../models/entry.dart';
import '../ui/entry_leading.dart';

/// File-visibility preferences: which dotfiles/extensions/exact names are
/// hidden from listings, plus the pure filter logic that decides whether a
/// given [Entry] should be hidden, and the one-tap presets.
///
/// This file holds only the immutable [VisibilityPrefs] value type, the pure
/// filters, and the presets — they are reused by both the resolver and the
/// widgets. *Persistence and resolution* (app default + optional per-device
/// override) now live in the two-tier settings model (`core/settings/`),
/// mirroring how `view_prefs.dart` relates to the settings controller. The
/// mutation API the settings controller exposes (setHideDotfiles, applyPreset,
/// …) is documented there.

// ---------------------------------------------------------------------------
// Presets
// ---------------------------------------------------------------------------

/// A one-tap preset that ADDS extensions and/or exact names to the user's
/// [VisibilityPrefs] sets (additive — applying a preset never removes
/// anything the user already configured).
class VisibilityPreset {
  const VisibilityPreset(
    this.label, {
    this.extensions = const {},
    this.names = const {},
  });

  /// Chip label shown in the settings UI.
  final String label;

  /// Extensions added to [VisibilityPrefs.hiddenExtensions] (lowercase, no
  /// leading dot).
  final Set<String> extensions;

  /// Exact names added to [VisibilityPrefs.hiddenNames].
  final Set<String> names;
}

/// "System junk": common transient/system files (`.tmp`, `.bak`, lockfiles,
/// plus well-known OS junk files by exact name).
const systemJunkPreset = VisibilityPreset(
  'System junk',
  extensions: {'tmp', 'bak', 'swp', 'lock', 'ini'},
  names: {'.DS_Store', 'Thumbs.db', 'desktop.ini'},
);

/// "Logs": log files and rotated/old log files.
const logsPreset = VisibilityPreset('Logs', extensions: {'log', 'old'});

/// "Archives": archive/compressed files, reusing [archiveExtensions].
const archivesPreset = VisibilityPreset(
  'Archives',
  extensions: archiveExtensions,
);

/// "Audio": audio files, reusing [audioExtensions].
const audioPreset = VisibilityPreset('Audio', extensions: audioExtensions);

/// "Images": image files, reusing [imageExtensions].
const imagesPreset = VisibilityPreset('Images', extensions: imageExtensions);

/// "Videos": video files, reusing [videoExtensions].
const videosPreset = VisibilityPreset('Videos', extensions: videoExtensions);

/// "Docs": document files, reusing [docExtensions].
const docsPreset = VisibilityPreset('Docs', extensions: docExtensions);

/// All visibility presets, in the order they should appear as chips.
const visibilityPresets = [
  systemJunkPreset,
  logsPreset,
  archivesPreset,
  audioPreset,
  imagesPreset,
  videosPreset,
  docsPreset,
];

// ---------------------------------------------------------------------------
// Prefs model
// ---------------------------------------------------------------------------

/// Snapshot of persisted file-visibility preferences.
class VisibilityPrefs {
  const VisibilityPrefs({
    this.hideDotfiles = true,
    this.hiddenExtensions = const {},
    this.hiddenNames = const {},
  });

  /// Hide entries (files and folders) whose name starts with `.`. Default ON.
  final bool hideDotfiles;

  /// User-managed set of file extensions to hide, lowercase and without the
  /// leading dot (e.g. `{'tmp', 'log'}`).
  final Set<String> hiddenExtensions;

  /// Exact (case-insensitive) names to hide, e.g. `desktop.ini`. Populated by
  /// presets.
  final Set<String> hiddenNames;

  VisibilityPrefs copyWith({
    bool? hideDotfiles,
    Set<String>? hiddenExtensions,
    Set<String>? hiddenNames,
  }) => VisibilityPrefs(
    hideDotfiles: hideDotfiles ?? this.hideDotfiles,
    hiddenExtensions: hiddenExtensions ?? this.hiddenExtensions,
    hiddenNames: hiddenNames ?? this.hiddenNames,
  );

  @override
  bool operator ==(Object other) =>
      other is VisibilityPrefs &&
      other.hideDotfiles == hideDotfiles &&
      _setEquals(other.hiddenExtensions, hiddenExtensions) &&
      _setEquals(other.hiddenNames, hiddenNames);

  @override
  int get hashCode => Object.hash(
    hideDotfiles,
    Object.hashAllUnordered(hiddenExtensions),
    Object.hashAllUnordered(hiddenNames),
  );
}

/// Order-independent set equality used by [VisibilityPrefs]'s `==` so two
/// prefs with the same contents (regardless of iteration order) compare equal.
bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

// ---------------------------------------------------------------------------
// Pure filter logic
// ---------------------------------------------------------------------------

/// Returns the lowercase extension of [name] (without the leading dot), or
/// `''` if [name] has no extension (no `.`, or the `.` is the last
/// character, or [name] starts with `.` and has no further `.` — i.e. a
/// dotfile like `.bashrc` has no "extension" for this purpose).
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// `true` if [name] is a dotfile/dotfolder — i.e. starts with `.` (matching
/// [VisibilityPrefs.hideDotfiles]; applies to both files and directories).
bool isDotfile(String name) => name.startsWith('.');

/// Decides whether [entry] should be hidden from a listing under [prefs]:
///
/// - [VisibilityPrefs.hideDotfiles] hides any entry (file or folder) whose
///   name starts with `.` (see [isDotfile]).
/// - [VisibilityPrefs.hiddenExtensions] hides files whose extension (see
///   [extensionOf]) is in the set, case-insensitively. Never applies to
///   directories.
/// - [VisibilityPrefs.hiddenNames] hides entries whose name exactly matches
///   one in the set, case-insensitively.
///
/// Pure function — no I/O, trivially unit-testable.
bool isEntryHidden(Entry entry, VisibilityPrefs prefs) {
  if (prefs.hideDotfiles && isDotfile(entry.name)) return true;
  if (!entry.isDir) {
    final ext = extensionOf(entry.name);
    if (ext.isNotEmpty &&
        prefs.hiddenExtensions.map((e) => e.toLowerCase()).contains(ext)) {
      return true;
    }
  }
  final lowerName = entry.name.toLowerCase();
  if (prefs.hiddenNames.any((n) => n.toLowerCase() == lowerName)) return true;
  return false;
}

/// Filters [entries] down to the visible ones under [prefs]. Pure function —
/// suitable for use in `ExplorerState`'s entries pipeline (before sorting) or
/// the search results pipeline.
List<Entry> filterHiddenEntries(List<Entry> entries, VisibilityPrefs prefs) =>
    entries.where((e) => !isEntryHidden(e, prefs)).toList();

/// Decides whether [entry] should be hidden from the destination picker under
/// [prefs]. The picker only ever shows directories, and only the dotfolder
/// rule applies there — extension/exact-name rules are file-only and the
/// picker has no files to apply them to.
bool isEntryHiddenInPicker(Entry entry, VisibilityPrefs prefs) =>
    prefs.hideDotfiles && isDotfile(entry.name);
