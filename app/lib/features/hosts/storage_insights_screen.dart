/// A focused storage view for a single host: an across-all-drives aggregate
/// total plus a per-drive [StorageGauge] list. Reached from the host card's
/// ⋯ menu. Reuses the existing `drivesProvider` (`/system/drives`); no agent
/// work. Drives without usable capacity are excluded from the total and
/// skipped by [StorageGauge].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/state_views.dart';
import '../explorer/drives_view.dart' show drivesProvider;
import 'widgets/storage_gauge.dart';

class StorageInsightsScreen extends ConsumerWidget {
  const StorageInsightsScreen({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivesAsync = ref.watch(drivesProvider(host.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.hostStorageTitle(host.label),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: drivesAsync.when(
        loading: () => const ListingSkeleton(),
        error:
            (e, _) => ErrorRetryCard(
              message: context.l10n.couldNotLoadStorage(humanizeError(e)),
              onRetry: () => ref.invalidate(drivesProvider(host.id)),
            ),
        data: (drives) {
          final total = aggregateUsage(drives);
          if (total == null) return const EmptyFolderView();
          final withCapacity =
              drives.where((d) => usedFraction(d) != null).toList();
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _TotalCard(usage: total, driveCount: withCapacity.length),
              const SizedBox(height: Spacing.md),
              for (final drive in withCapacity) StorageGauge(drive: drive),
            ],
          );
        },
      ),
    );
  }
}

/// The aggregate "All drives" card: a single gauge bar over the summed
/// capacity, with a "`free` free of `total` · N drive(s)" caption.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.usage, required this.driveCount});

  final ({int totalBytes, int freeBytes, double usedFraction}) usage;
  final int driveCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return Card(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardR,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.allDrives, style: textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: Radii.stadiumR,
              child: LinearProgressIndicator(
                value: usage.usedFraction,
                minHeight: 10,
                backgroundColor: scheme.tertiaryContainer,
                valueColor: AlwaysStoppedAnimation(scheme.tertiary),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              l10n.freeOfTotalDrives(
                formatSize(usage.freeBytes),
                formatSize(usage.totalBytes),
                driveCount,
              ),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
