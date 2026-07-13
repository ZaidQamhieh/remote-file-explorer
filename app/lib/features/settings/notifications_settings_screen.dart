import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const ScreenHeader('Notifications & Alerts'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          SettingsSection(
            title: 'ALERTS',
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.bell,
                badgeColor: Colors.amber,
                title: context.l10n.transferNotifications,
                subtitle: context.l10n.transferNotificationsSubtitle,
                value: app.notificationsEnabled,
                onChanged: notifier.setNotificationsEnabled,
              ),
              SettingsTile.toggle(
                icon: LucideIcons.hardDrive,
                badgeColor: Colors.amber,
                title: context.l10n.lowDiskAlerts,
                subtitle: context.l10n.lowDiskAlertsSubtitle,
                value: app.lowDiskThresholdBytes > 0,
                onChanged:
                    (on) => notifier.setLowDiskThreshold(
                      on ? 1024 * 1024 * 1024 : 0,
                    ),
              ),
              SettingsTile.toggle(
                icon: LucideIcons.calendarClock,
                badgeColor: Colors.amber,
                title: 'Weekly storage digest',
                subtitle:
                    'Once a week, notify me how free space is trending on my hosts',
                value: app.weeklyDigestEnabled,
                onChanged: notifier.setWeeklyDigestEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
