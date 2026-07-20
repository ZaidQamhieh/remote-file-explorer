import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';

/// Transfer notifications, low-disk alerts, and the weekly storage digest
/// (Settings Overhaul, group 3 of 5).
class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final app = settings.app;

    final entries = [
      (
        icon: LucideIcons.bell,
        title: context.l10n.transferNotifications,
        subtitle: context.l10n.transferNotificationsSubtitle,
        value: app.notificationsEnabled,
        onChanged: notifier.setNotificationsEnabled,
      ),
      (
        icon: LucideIcons.hardDrive,
        title: context.l10n.lowDiskAlerts,
        subtitle: context.l10n.lowDiskAlertsSubtitle,
        value: app.lowDiskThresholdBytes > 0,
        onChanged:
            (bool on) =>
                notifier.setLowDiskThreshold(on ? 1024 * 1024 * 1024 : 0),
      ),
      (
        icon: LucideIcons.calendarClock,
        title: 'Weekly storage digest',
        subtitle:
            'Once a week, notify me how free space is trending on my hosts',
        value: app.weeklyDigestEnabled,
        onChanged: notifier.setWeeklyDigestEnabled,
      ),
    ];
    final activeCount = entries.where((e) => e.value).length;

    return Scaffold(
      appBar: AppBar(),
      // Only 3 rows exist on this page — a top-pinned ListView leaves most
      // of a tall phone screen as dead black space below them, which reads
      // as broken rather than just "a short page". Centering the block
      // keeps it feeling designed regardless of viewport height.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NotificationSummary(
                  activeCount: activeCount,
                  totalCount: entries.length,
                ),
                const SizedBox(height: Spacing.md),
                for (final e in entries) ...[
                  _ToggleCard(
                    icon: e.icon,
                    title: e.title,
                    subtitle: e.subtitle,
                    value: e.value,
                    onChanged: e.onChanged,
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bell glyph + "X of N active" summary, replacing the plain hero band —
/// gives an at-a-glance read before the 3 toggle cards below.
class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({
    required this.activeCount,
    required this.totalCount,
  });

  final int activeCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Column(
        children: [
          Icon(LucideIcons.bell, size: 36, color: Brand.amber),
          const SizedBox(height: Spacing.xs),
          Text(
            '$activeCount of $totalCount alerts active',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Full-width card per alert, roomier than a plain [SettingsTile] row so
/// each of the 3 (genuinely few) settings gets space to breathe.
class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShadCard(
      padding: EdgeInsets.zero,
      radius: Radii.cardR,
      backgroundColor: scheme.surfaceContainerHigh,
      border: ShadBorder.all(color: scheme.outline, width: 1.5),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Brand.amber.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: Brand.amber),
            ),
            const SizedBox(width: Spacing.md3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ShadSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
