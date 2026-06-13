import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entry.dart';
import '../ui/entry_leading.dart';

/// Global file-visibility preferences: which dotfiles/extensions/exact names
/// are hidden from listings by default, plus the pure filter logic that
/// decides whether a given [Entry] should be hidden. Persisted in
/// [SharedPreferences] (applies to all hosts), following the same
/// load-then-persist pattern as `core/storage/view_prefs.dart`
/// ([ViewPrefsNotifier]).

const _kHideDotfilesKey = 'rfe_hide_dotfiles_v1';
const _kHiddenExtensionsKey = 'rfe_hidden_extensions_v1';
const _kHiddenNamesKey = 'rfe_hidden_names_v1';

// ---------------------------------------------------------------------------
// Presets
// ---------------------------------------------------------------------------

/// A one-tap preset that ADDS extensions and/or exact names to the user's
/// [VisibilityPrefs] sets (additive — applying a preset never removes
/// anything the user already configured).
class VisibilityPreset {
  const VisibilityPreset(this.label, {this.extensions = const {}, this.names = const {}});

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
const archivesPreset =
    VisibilityPreset('Archives', extensions: archiveExtensions);

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
  }) =>
      VisibilityPrefs(
        hideDotfiles: hideDotfiles ?? this.hideDotfiles,
        hiddenExtensions: hiddenExtensions ?? this.hiddenExtensions,
        hiddenNames: hiddenNames ?? this.hiddenNames,
      );
}

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

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Loads and persists [VisibilityPrefs]. Mutating methods update
/// [SharedPreferences] immediately and then update [state], following the
/// same load-then-persist pattern as `ViewPrefsNotifier` in
/// `view_prefs.dart`.
class VisibilityPrefsNotifier extends AsyncNotifier<VisibilityPrefs> {
  SharedPreferences? _prefs;

  @override
  Future<VisibilityPrefs> build() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final hideDotfiles = prefs.getBool(_kHideDotfilesKey) ?? true;

    final rawExtensions = prefs.getString(_kHiddenExtensionsKey);
    final hiddenExtensions = rawExtensions == null
        ? <String>{}
        : (jsonDecode(rawExtensions) as List).cast<String>().toSet();

    final rawNames = prefs.getString(_kHiddenNamesKey);
    final hiddenNames = rawNames == null
        ? <String>{}
        : (jsonDecode(rawNames) as List).cast<String>().toSet();

    return VisibilityPrefs(
      hideDotfiles: hideDotfiles,
      hiddenExtensions: hiddenExtensions,
      hiddenNames: hiddenNames,
    );
  }

  /// Sets whether dotfiles/dotfolders are hidden, persisting the choice.
  Future<void> setHideDotfiles(bool hide) async {
    final current = state.valueOrNull ?? const VisibilityPrefs();
    await _prefs?.setBool(_kHideDotfilesKey, hide);
    state = AsyncData(current.copyWith(hideDotfiles: hide));
  }

  /// Replaces the set of hidden extensions, persisting the choice.
  Future<void> setHiddenExtensions(Set<String> extensions) async {
    final current = state.valueOrNull ?? const VisibilityPrefs();
    final normalized = extensions.map((e) => e.toLowerCase()).toSet();
    await _prefs?.setString(_kHiddenExtensionsKey, jsonEncode(normalized.toList()));
    state = AsyncData(current.copyWith(hiddenExtensions: normalized));
  }

  /// Replaces the set of hidden exact names, persisting the choice.
  Future<void> setHiddenNames(Set<String> names) async {
    final current = state.valueOrNull ?? const VisibilityPrefs();
    await _prefs?.setString(_kHiddenNamesKey, jsonEncode(names.toList()));
    state = AsyncData(current.copyWith(hiddenNames: names));
  }

  /// Adds a single extension (lowercase, without the leading dot — leading
  /// dots and surrounding whitespace are stripped) to the hidden set. No-op
  /// if the result is empty.
  Future<void> addExtension(String extension) async {
    final normalized = extension.trim().toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
    if (normalized.isEmpty) return;
    final current = state.valueOrNull ?? const VisibilityPrefs();
    await setHiddenExtensions({...current.hiddenExtensions, normalized});
  }

  /// Removes a single extension from the hidden set.
  Future<void> removeExtension(String extension) async {
    final current = state.valueOrNull ?? const VisibilityPrefs();
    final updated = Set<String>.from(current.hiddenExtensions)
      ..remove(extension.toLowerCase());
    await setHiddenExtensions(updated);
  }

  /// Applies [preset], adding its extensions/names to the current sets
  /// (additive — never removes existing entries).
  Future<void> applyPreset(VisibilityPreset preset) async {
    final current = state.valueOrNull ?? const VisibilityPrefs();
    await setHiddenExtensions({...current.hiddenExtensions, ...preset.extensions});
    await setHiddenNames({...current.hiddenNames, ...preset.names});
  }

  /// Removes [preset]'s extensions/names from the current sets — the inverse
  /// of [applyPreset]. Entries not currently present are ignored. Names are
  /// matched case-insensitively (mirroring [isEntryHidden]). Note: an
  /// extension/name shared with another applied preset is removed too, which
  /// will visually de-select that overlapping preset's chip as well.
  Future<void> removePreset(VisibilityPreset preset) async {
    final current = state.valueOrNull ?? const VisibilityPrefs();
    final lowerToRemove = preset.names.map((n) => n.toLowerCase()).toSet();
    await setHiddenExtensions(
      current.hiddenExtensions.difference(preset.extensions),
    );
    await setHiddenNames(
      current.hiddenNames
          .where((n) => !lowerToRemove.contains(n.toLowerCase()))
          .toSet(),
    );
  }
}

final visibilityPrefsProvider =
    AsyncNotifierProvider<VisibilityPrefsNotifier, VisibilityPrefs>(
  VisibilityPrefsNotifier.new,
);
