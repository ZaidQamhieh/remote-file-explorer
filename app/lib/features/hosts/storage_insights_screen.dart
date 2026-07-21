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
/// coloured-swatch-list *shape* — literal ring geometry (170px/26px stroke),
/// row layout (`.row`), and `.btn-ghost` CTA from `docs/mockup-reference/
/// mockup.css` — over the real per-drive dimension instead of fabricating
/// file-type numbers the backend never sends.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/providers.dart' show clientProvider;
import '../../core/l10n_ext.dart';
import '../../core/models/drive.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';
import '../explorer/drives_view.dart' show drivesProvider;
import '../explorer/type_treemap_screen.dart';
import 'widgets/storage_gauge.dart';

/// Cycling swatch colours for the per-drive ring segments/rows — the
/// mockup's own conic-gradient stop order (primary, violet, amber); the
/// aggregate "Free space" segment always gets the mockup's `--surface-3`
/// neutral tone instead of cycling into it.
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
          final segments = [
            for (var i = 0; i < withCapacity.length; i++)
              (
                color: _drivePalette[i % _drivePalette.length],
                fraction:
                    (withCapacity[i].totalBytes! - withCapacity[i].freeBytes!) /
                    usage.totalBytes,
              ),
            (
              color: scheme.surfaceContainerHighest,
              fraction: usage.freeBytes / usage.totalBytes,
            ),
          ];
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  18,
                  Spacing.md,
                  6,
                ),
                child: Center(
                  child: _UsageRing(
                    segments: segments,
                    percent: (usage.usedFraction * 100).round(),
                    usedLabel: formatSize(usage.totalBytes - usage.freeBytes),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  18,
                  Spacing.md,
                  8,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < withCapacity.length; i++)
                      _BreakdownRow(
                        color: _drivePalette[i % _drivePalette.length],
                        label: _driveLabel(withCapacity[i]),
                        bytes:
                            withCapacity[i].totalBytes! -
                            withCapacity[i].freeBytes!,
                        showDivider: true,
                      ),
                    _BreakdownRow(
                      color: scheme.surfaceContainerHighest,
                      label: context.l10n.freeSpaceLabel,
                      bytes: usage.freeBytes,
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  0,
                  Spacing.md,
                  24,
                ),
                child: _StorageByTypeButton(
                  onTap: () => _openStorageByType(context, ref),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openStorageByType(BuildContext context, WidgetRef ref) async {
    final client = await ref.read(clientProvider(host.id).future);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) =>
                TypeTreemapScreen(hostId: host.id, path: '/', client: client),
      ),
    );
  }

  String _driveLabel(Drive d) =>
      (d.label != null && d.label!.isNotEmpty) ? d.label! : d.path;
}

/// The mockup's donut ring: a 170px circle with a 26px stroke, one arc
/// segment per drive (cycling `_drivePalette`) plus a final free-space
/// segment, matching the mockup's literal `conic-gradient(var(--primary) 0
/// 38%, var(--violet) 38% 58%, var(--amber) 58% 72%, var(--surface-3) 72%
/// 100%)` ring — over real per-drive fractions instead of fabricated
/// file-type ones. Percentage (20px/700/mono) + used-bytes caption
/// (10.5px/faint) centred, same as the mockup.
class _UsageRing extends StatelessWidget {
  const _UsageRing({
    required this.segments,
    required this.percent,
    required this.usedLabel,
  });

  final List<({Color color, double fraction})> segments;
  final int percent;
  final String usedLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 170,
      height: 170,
      child: CustomPaint(
        painter: _RingPainter(segments: segments),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              Text(
                usedLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.segments});

  final List<({Color color, double fraction})> segments;

  static const _strokeWidth = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _strokeWidth / 2,
      _strokeWidth / 2,
      size.width - _strokeWidth,
      size.height - _strokeWidth,
    );
    var start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.fraction <= 0) continue;
      final sweep = segment.fraction * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.segments != segments;
}

/// One row in the breakdown list: a coloured square swatch, a label, and a
/// mono byte value — the mockup's literal `.row` (11px vertical padding,
/// 12px gap, 1px bottom border except the last row) with a `.row-sub.mono`
/// trailing value in place of the `.row-end` chevron this row doesn't need.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.color,
    required this.label,
    required this.bytes,
    required this.showDivider,
  });

  final Color color;
  final String label;
  final int bytes;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        border:
            showDivider
                ? Border(bottom: BorderSide(color: scheme.outlineVariant))
                : null,
      ),
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
          const SizedBox(width: Spacing.md2),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatSize(bytes),
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block`: full-width, `--surface-2`
/// background, no icon leading — text then a trailing arrow, matching the
/// literal markup order (`Open storage-by-type map<svg arrow-right/>`).
class _StorageByTypeButton extends StatelessWidget {
  const _StorageByTypeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: Radii.smR,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10n.openStorageTypeMapButton,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 7),
            Icon(LucideIcons.arrowRight, size: 16, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}
