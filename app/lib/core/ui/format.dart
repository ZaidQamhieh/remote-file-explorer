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

/// Short `YYYY-MM-DD` date string for [dt] (local calendar date).
String formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';
