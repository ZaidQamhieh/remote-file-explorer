import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/cache_manager.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import 'widgets/settings_hero.dart';
import 'widgets/settings_tile.dart';
import 'widgets/settings_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Indirection around `LocalAuthentication().isDeviceSupported()` so widget
/// tests can stub device-auth support without a real platform channel —
/// local_auth's Pigeon-generated API has no simple `MethodChannel` to mock.
/// Overridden by tests, reset via `addTearDown`.
@visibleForTesting
Future<bool> Function() isDeviceAuthSupportedCheck =
    () => LocalAuthentication().isDeviceSupported();

/// Cache stats/clear and App Lock — grouped as "storage you might reclaim,
/// security you might tighten" (Settings Overhaul, group 4 of 5).
class StorageSecuritySettingsScreen extends ConsumerWidget {
  const StorageSecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          const SettingsHero(
            icon: LucideIcons.shieldCheck,
            title: 'Storage & Security',
            subtitle: 'Cache usage & App Lock',
            tint: Brand.seed,
          ),
          const SizedBox(height: Spacing.md),
          const _CacheSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Security',
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.lock,
                badgeColor: Brand.seed,
                title: 'App Lock',
                subtitle: 'Require biometric or PIN to open',
                value: settings.app.appLockEnabled,
                onChanged: (enabled) async {
                  // Turning it on with no device auth configured would leave
                  // the toggle showing "on" while actually locking nothing —
                  // lock_gate.dart's fail-safe (PR-18) treats "no auth
                  // available" as unlocked, by design, once you're already
                  // past this point. Preflight instead of relying on that.
                  if (enabled && !await isDeviceAuthSupportedCheck()) {
                    if (context.mounted) {
                      showError(
                        context,
                        'Set up a screen lock (PIN, pattern, or biometric) on '
                        'this device before enabling App Lock.',
                      );
                    }
                    return;
                  }
                  notifier.setAppLockEnabled(enabled);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CacheSection extends ConsumerWidget {
  const _CacheSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(cacheStatsProvider);
    final scheme = Theme.of(context).colorScheme;

    return SettingsSection(
      title: context.l10n.cacheSection,
      children: [
        statsAsync.when(
          loading:
              () => Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text(
                  context.l10n.cacheCalculating,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
          error: (_, __) => const SizedBox.shrink(),
          data: (stats) {
            return Column(
              children: [
                const SizedBox(height: Spacing.xs),
                _CacheGauge(
                  listingBytes: stats.listingBytes,
                  tempBytes: stats.tempBytes,
                ),
                const SizedBox(height: Spacing.md),
                _CacheLegendRow(
                  color: Brand.seed,
                  label: context.l10n.cacheListingLabel,
                  bytes: stats.listingBytes,
                ),
                _CacheLegendRow(
                  color: Brand.accent,
                  label: context.l10n.cacheTempLabel,
                  bytes: stats.tempBytes,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Spacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            icon: const Icon(LucideIcons.trash2),
            label: Text(context.l10n.cacheClearAll),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
            onPressed: () async {
              await ref.read(cacheManagerProvider).clearAll();
              ref.invalidate(cacheStatsProvider);
              if (context.mounted) {
                showSuccess(context, context.l10n.cacheCleared);
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Donut gauge splitting total cache between listing/temp — replaces the
/// old stacked-rows + linear bar with an at-a-glance radial breakdown.
class _CacheGauge extends StatelessWidget {
  const _CacheGauge({required this.listingBytes, required this.tempBytes});

  final int listingBytes;
  final int tempBytes;

  @override
  Widget build(BuildContext context) {
    final total = listingBytes + tempBytes;
    return Center(
      child: SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(
          painter: _DonutPainter(
            trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            listingFraction: total > 0 ? listingBytes / total : 0,
            tempFraction: total > 0 ? tempBytes / total : 0,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatSize(total),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'cache used',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.trackColor,
    required this.listingFraction,
    required this.tempFraction,
  });

  final Color trackColor;
  final double listingFraction;
  final double tempFraction;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 12.0;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final track =
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 6.28319, false, track);

    const start = -1.5708; // -90deg, 12 o'clock
    final listingSweep = 6.28319 * listingFraction;
    final tempSweep = 6.28319 * tempFraction;

    final listingPaint =
        Paint()
          ..color = Brand.seed
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, listingSweep, false, listingPaint);

    final tempPaint =
        Paint()
          ..color = Brand.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start + listingSweep, tempSweep, false, tempPaint);
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.listingFraction != listingFraction ||
      oldDelegate.tempFraction != tempFraction ||
      oldDelegate.trackColor != trackColor;
}

class _CacheLegendRow extends StatelessWidget {
  const _CacheLegendRow({
    required this.color,
    required this.label,
    required this.bytes,
  });

  final Color color;
  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text(label)),
          Text(formatSize(bytes)),
        ],
      ),
    );
  }
}
