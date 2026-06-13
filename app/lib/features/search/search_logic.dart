/// Pure helper functions for the search screen — extracted from the widget
/// so they can be unit tested without pumping a widget tree.
library;

import '../../core/models/entry.dart';
import '../../core/storage/visibility_prefs.dart';

/// Returns `true` if [q] should be treated as a glob pattern (contains `*`
/// or `?`) rather than a plain substring match.
bool isGlobQuery(String q) => q.contains('*') || q.contains('?');

/// Sorts [entries] by relevance to [query]:
///
/// - Entries whose [Entry.name] starts with [query] (case-insensitive) come
///   first, followed by all others.
/// - Within each group, entries are ordered alphabetically by name
///   (case-insensitive).
///
/// If [query] is a glob pattern (see [isGlobQuery]), relevance grouping is
/// skipped and the result is purely alphabetical — substring "starts with"
/// has no clear meaning for a glob.
///
/// Returns a new list; [entries] is not modified.
List<Entry> sortByRelevance(List<Entry> entries, String query) {
  final sorted = List<Entry>.from(entries);
  final q = query.trim().toLowerCase();

  if (q.isEmpty || isGlobQuery(query)) {
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  int rank(Entry e) => e.name.toLowerCase().startsWith(q) ? 0 : 1;

  sorted.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

/// A `[start, end)` character range within a name to be highlighted, in
/// UTF-16 code unit offsets (suitable for [TextRange]/[TextSpan] use).
class HighlightRange {
  const HighlightRange(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is HighlightRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'HighlightRange($start, $end)';
}

/// Filters search [results] using the same file-visibility prefs as the
/// explorer listing (`core/storage/visibility_prefs.dart`) — dotfiles,
/// hidden extensions, and hidden exact names. The search screen's own
/// category/size/date filters are separate server-side `types`/etc.
/// parameters and unrelated to this client-side pass.
///
/// When [includeHidden] is `true` (the search filter sheet's "Include hidden
/// items" switch), [results] is returned unchanged.
List<Entry> filterSearchResults(
  List<Entry> results,
  VisibilityPrefs prefs, {
  required bool includeHidden,
}) {
  if (includeHidden) return results;
  return filterHiddenEntries(results, prefs);
}

/// Returns the range of [name] that matches [query] (case-insensitive
/// substring), or `null` when:
///
/// - [query] is empty,
/// - [query] is a glob pattern (see [isGlobQuery]) — highlighting is
///   ambiguous for patterns, so callers should skip it, or
/// - [name] does not contain [query].
///
/// Only the first match is highlighted.
HighlightRange? highlightRange(String name, String query) {
  final q = query.trim();
  if (q.isEmpty || isGlobQuery(q)) return null;
  final idx = name.toLowerCase().indexOf(q.toLowerCase());
  if (idx < 0) return null;
  return HighlightRange(idx, idx + q.length);
}
