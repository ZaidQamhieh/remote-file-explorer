/// Shared formatting helpers for file sizes and dates, used across the
/// explorer, search, transfers, and preview screens so every surface renders
/// the same human-readable strings.
library;

/// Human-readable byte size (e.g. `512 B`, `4.2 KB`, `1.3 MB`, `2.10 GB`).
///
/// Returns an empty string for `null` (used where size is optional/unknown).
String formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Clock-style duration string for [d] (e.g. `0:07`, `3:42`, `1:05:09`).
///
/// Minutes and seconds are always two digits; the hours field is only shown
/// when the duration reaches an hour. Negative or null values render `0:00`,
/// so it's safe to pass a media player's position before it's known.
String formatDuration(Duration? d) {
  final total = (d?.inSeconds ?? 0).clamp(0, 1 << 31);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

/// Short `YYYY-MM-DD` date string for [dt] (local calendar date).
String formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

/// Compact relative time for [dt] vs. now (e.g. `just now`, `5m ago`,
/// `3h ago`, `2d ago`), falling back to [formatDate] for anything 7 days or
/// older.
String formatRelative(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(dt);
}
