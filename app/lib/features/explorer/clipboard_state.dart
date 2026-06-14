import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [FileClipboard.paths] should be moved (cut) or duplicated (copy)
/// into the paste destination.
enum ClipboardMode { copy, cut }

/// Snapshot of "what's on the clipboard": the absolute [paths] of the entries
/// the user cut/copied, the [mode] (cut vs copy), and the [hostId] they were
/// copied from — paste is only offered while browsing the SAME host
/// (cross-host copy is out of scope for this wave).
class FileClipboard {
  const FileClipboard({
    required this.paths,
    required this.mode,
    required this.hostId,
  });

  final List<String> paths;
  final ClipboardMode mode;
  final String hostId;

  bool get isEmpty => paths.isEmpty;
}

/// App-scoped clipboard for cut/copy/paste across explorer screens.
///
/// Deliberately **not** `autoDispose` — an [ExplorerScreen] is disposed when
/// the user navigates to another folder (each path push is a new route), but
/// the clipboard must survive that so "cut here, paste there" works. A single
/// instance lives for the app's lifetime.
class ClipboardNotifier extends Notifier<FileClipboard?> {
  @override
  FileClipboard? build() => null;

  /// Fills the clipboard with [paths] from [hostId] in copy mode. No-op if
  /// [paths] is empty (leaves the clipboard untouched/null).
  void copy(List<String> paths, String hostId) {
    if (paths.isEmpty) return;
    state = FileClipboard(paths: paths, mode: ClipboardMode.copy, hostId: hostId);
  }

  /// Fills the clipboard with [paths] from [hostId] in cut mode. No-op if
  /// [paths] is empty (leaves the clipboard untouched/null).
  void cut(List<String> paths, String hostId) {
    if (paths.isEmpty) return;
    state = FileClipboard(paths: paths, mode: ClipboardMode.cut, hostId: hostId);
  }

  /// Empties the clipboard.
  void clear() => state = null;
}

final clipboardProvider =
    NotifierProvider<ClipboardNotifier, FileClipboard?>(ClipboardNotifier.new);
