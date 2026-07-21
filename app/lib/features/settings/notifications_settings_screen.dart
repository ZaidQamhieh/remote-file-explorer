import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Transfer notifications, low-disk alerts, and the weekly storage digest
/// (Settings Overhaul, group 3 of 5).
///
/// Card-grouped sections matching the mockup's `settings-notifications`
/// screen shape (section label + one rounded card of divided toggle rows).
///
/// The mockup mocks 5 toggles across 3 sections (Transfers: "Transfer
/// completed" / "Transfer failed" split; Backup: "Photo backup status" /
/// "Weekly activity digest"; Devices: "Device paired/revoked"). The real
/// settings model only has 3 notification toggles total —
/// `notificationsEnabled` (one combined transfer-notification switch, not
/// split into completed/failed), `lowDiskThresholdBytes` (not in the mockup
/// at all), and `weeklyDigestEnabled`. There's no photo-backup-status or
/// device-paired/revoked notification setting anywhere in the app. Rather
/// than fabricate switches with nothing behind them, this renders the 3 real
/// toggles under their closest real section and omits the rest.
class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final app = settings.app;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          SettingsSection(
            title: 'Transfers',
            padded: false,
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.bell,
                badgeColor: Brand.amber,
                title: context.l10n.transferNotifications,
                subtitle: context.l10n.transferNotificationsSubtitle,
                value: app.notificationsEnabled,
                onChanged: notifier.setNotificationsEnabled,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Storage',
            padded: false,
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.hardDrive,
                badgeColor: Brand.amber,
                title: context.l10n.lowDiskAlerts,
                subtitle: context.l10n.lowDiskAlertsSubtitle,
                value: app.lowDiskThresholdBytes > 0,
                onChanged:
                    (bool on) => notifier.setLowDiskThreshold(
                      on ? 1024 * 1024 * 1024 : 0,
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Backup',
            padded: false,
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.calendarClock,
                badgeColor: Brand.amber,
                title: 'Weekly activity digest',
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
