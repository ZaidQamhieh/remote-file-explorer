import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            tint: Colors.blue,
          ),
          const SizedBox(height: Spacing.md),
          const _CacheSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Security',
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.lock,
                badgeColor: Colors.blue,
                title: 'App Lock',
                subtitle: 'Require biometric or PIN to open',
                value: settings.app.appLockEnabled,
                onChanged: notifier.setAppLockEnabled,
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
      icon: LucideIcons.refreshCw,
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
                _CacheRow(
                  label: context.l10n.cacheListingLabel,
                  bytes: stats.listingBytes,
                ),
                _CacheRow(
                  label: context.l10n.cacheTempLabel,
                  bytes: stats.tempBytes,
                ),
                const Divider(height: Spacing.lg),
                _CacheRow(
                  label: context.l10n.cacheTotalLabel,
                  bytes: stats.totalBytes,
                  bold: true,
                ),
                const SizedBox(height: Spacing.sm),
                _UsageBar(
                  // ponytail: no real quota concept exists to measure
                  // against yet, so this is a decorative fixed proportion,
                  // not a computed used/total fraction — wire to a real
                  // quota if the app ever gets one.
                  fraction: stats.totalBytes > 0 ? 0.14 : 0.0,
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

/// Thin rounded usage bar under the cache totals — a blue→purple gradient
/// fill at [fraction] of the track width.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: Radii.chipR,
      child: Container(
        height: 6,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.label,
    required this.bytes,
    this.bold = false,
  });

  final String label;
  final int bytes;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w600 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatSize(bytes), style: style),
        ],
      ),
    );
  }
}
