/// A focused storage view for a single host: a donut ring showing the
/// aggregate used/free split across all drives, plus a per-drive breakdown
/// list. Reached from the host settings screen. Reuses the existing
/// `drivesProvider` (`/system/drives`); no agent work.
///
/// The mockup's Storage Insights screen shows a "storage by file type"
/// breakdown (Documents / Photos & Video / Applications / Free space). The
/// agent's `/system/drives` endpoint only reports free/total bytes per mount
/// point — it has no concept of file-type categories host-wide (the only
/// file-type breakdown the app has, `type_treemap_screen.dart`, scans one
/// already-chosen folder, not the whole host, and is a comparatively
/// expensive recursive operation). So this reuses the mockup's donut +
/// coloured-swatch-list *shape* but over the real per-drive dimension
/// instead of fabricating file-type numbers the backend never sends — see
/// also the note on the "Open storage-by-type map" button below.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/drive.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import '../explorer/drives_view.dart' show drivesProvider;
import 'widgets/storage_gauge.dart';

/// Cycling swatch colours for the per-drive rows (the aggregate "Free space"
/// row always gets a neutral swatch, matching the mockup's own free-space
/// row).
const _drivePalette = [Brand.seed, Brand.accent, Brand.amber];

class StorageInsightsScreen extends ConsumerWidget {
  const StorageInsightsScreen({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivesAsync = ref.watch(drivesProvider(host.id));
    final scheme = Theme.of(context).colorScheme;
    final knownDrives = drivesAsync.valueOrNull;
    final total = knownDrives == null ? null : aggregateUsage(knownDrives);

    return Scaffold(
      appBar: AppBar(
        title: ScreenHeader(
          context.l10n.storageInsightsTitle,
          subtitle:
              total != null
                  ? context.l10n.hostStorageSubtitle(
                    host.label,
                    formatSize(total.totalBytes - total.freeBytes),
                    formatSize(total.totalBytes),
                  )
                  : null,
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
          final usage = aggregateUsage(drives);
          if (usage == null) return const EmptyFolderView();
          final withCapacity =
              drives.where((d) => usedFraction(d) != null).toList();
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Center(
                child: _UsageRing(
                  fraction: usage.usedFraction,
                  usedBytes: usage.totalBytes - usage.freeBytes,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              for (var i = 0; i < withCapacity.length; i++)
                _BreakdownRow(
                  color: _drivePalette[i % _drivePalette.length],
                  label: _driveLabel(withCapacity[i]),
                  bytes:
                      withCapacity[i].totalBytes! - withCapacity[i].freeBytes!,
                ),
              _BreakdownRow(
                color: scheme.surfaceContainerHighest,
                label: context.l10n.freeSpaceLabel,
                bytes: usage.freeBytes,
              ),
            ],
          );
        },
      ),
    );
  }

  String _driveLabel(Drive d) =>
      (d.label != null && d.label!.isNotEmpty) ? d.label! : d.path;
}

/// The donut ring: a single [CircularProgressIndicator] whose track colour
/// covers the free portion and whose value arc covers the used portion —
/// the mockup's multi-colour conic-gradient ring, collapsed to the one real
/// number the agent reports (aggregate used vs. free), with the percentage
/// and used bytes centred inside, same as the mockup.
class _UsageRing extends StatelessWidget {
  const _UsageRing({required this.fraction, required this.usedBytes});

  final double fraction;
  final int usedBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: fraction,
            strokeWidth: 26,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation(Brand.seed),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(fraction * 100).round()}%',
                style: textTheme.titleLarge?.copyWith(
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                formatSize(usedBytes),
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row in the breakdown list: a coloured square swatch, a label, and a
/// mono byte value — the mockup's category row.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.color,
    required this.label,
    required this.bytes,
  });

  final Color color;
  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          Text(
            formatSize(bytes),
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
