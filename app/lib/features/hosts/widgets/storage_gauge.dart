import 'package:flutter/material.dart';

import '../../../core/models/drive.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';

/// Fraction of [drive] currently used, clamped to `[0, 1]`.
///
/// Returns `null` when usage can't be determined (missing/zero total bytes,
/// or a free value that doesn't fit within the total) so callers can skip
/// rendering a gauge for that drive rather than showing a misleading bar.
double? usedFraction(Drive drive) {
  final total = drive.totalBytes;
  final free = drive.freeBytes;
  if (total == null || total <= 0 || free == null) return null;
  final used = total - free;
  return (used / total).clamp(0.0, 1.0);
}

/// Aggregate used/free/total across every drive in [drives] that reports real
/// capacity (`totalBytes != null && totalBytes > 0 && freeBytes != null`).
///
/// Returns `null` when no drive has usable capacity, so callers can render an
/// empty state instead of a meaningless zero bar. A per-drive `freeBytes` that
/// exceeds its `totalBytes` (bad agent data) is capped to the total so it can't
/// inflate the aggregate free beyond capacity — mirroring [usedFraction]'s
/// clamping contract.
({int totalBytes, int freeBytes, double usedFraction})? aggregateUsage(
  List<Drive> drives,
) {
  var sumTotal = 0;
  var sumFree = 0;
  var any = false;
  for (final drive in drives) {
    final total = drive.totalBytes;
    final free = drive.freeBytes;
    if (total == null || total <= 0 || free == null) continue;
    any = true;
    sumTotal += total;
    sumFree += free > total ? total : free;
  }
  if (!any || sumTotal <= 0) return null;
  final used = sumTotal - sumFree;
  return (
    totalBytes: sumTotal,
    freeBytes: sumFree,
    usedFraction: (used / sumTotal).clamp(0.0, 1.0),
  );
}

/// A single-drive storage gauge: a thin rounded progress track plus a
/// "`<free>` free of `<total>`" label and the mount path/label underneath.
///
/// Renders nothing if [usedFraction] can't compute a usable fraction for
/// [drive] (e.g. the agent reported zero/garbage totals).
class StorageGauge extends StatelessWidget {
  const StorageGauge({super.key, required this.drive});

  final Drive drive;

  @override
  Widget build(BuildContext context) {
    final fraction = usedFraction(drive);
    if (fraction == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final free = drive.freeBytes!;
    final total = drive.totalBytes!;
    final label =
        (drive.label != null && drive.label!.isNotEmpty)
            ? drive.label!
            : drive.path;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: Radii.stadiumR,
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                    backgroundColor: scheme.tertiaryContainer,
                    valueColor: AlwaysStoppedAnimation(scheme.tertiary),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '${formatSize(free)} free of ${formatSize(total)}',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs / 2),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
