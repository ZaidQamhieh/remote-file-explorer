/// Pure logic for the weekly storage digest (L4): comparing per-host
/// free-space snapshots and deciding when a week has elapsed. Kept free of
/// Flutter/network/notification plumbing (see [WeeklyDigestService] for the
/// orchestration) so it's directly unit-testable.
library;

import '../../core/ui/format.dart';

/// A host's aggregate drive usage, as produced by `aggregateUsage` in
/// `widgets/storage_gauge.dart`.
typedef HostUsage = ({int totalBytes, int freeBytes, double usedFraction});

/// True when a digest is due: never shown before, or 7+ days since
/// [lastShownAt].
bool shouldShowDigest(DateTime? lastShownAt, DateTime now) =>
    lastShownAt == null ||
    now.difference(lastShownAt) >= const Duration(days: 7);

/// Builds the one-line-per-host digest body, e.g. `Desktop-PC: 340.0 GB free
/// (-1.2 GB this week) · Laptop: 89.0 GB free`.
///
/// [current] and [previous] are keyed by host label. A host present only in
/// [current] (no prior snapshot) is shown without a trend delta. Returns an
/// empty string when [current] is empty.
String buildDigestSummary(
  Map<String, HostUsage> current,
  Map<String, HostUsage> previous,
) {
  final parts = <String>[];
  for (final entry in current.entries) {
    final usage = entry.value;
    final prev = previous[entry.key];
    final free = '${formatSize(usage.freeBytes)} free';
    if (prev == null) {
      parts.add('${entry.key}: $free');
    } else {
      final delta = usage.freeBytes - prev.freeBytes;
      final sign = delta < 0 ? '-' : '+';
      parts.add(
        '${entry.key}: $free ($sign${formatSize(delta.abs())} this week)',
      );
    }
  }
  return parts.join(' · ');
}
