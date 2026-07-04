import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'widgets/settings_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
            title: context.l10n.notificationsSection,
            icon: LucideIcons.bell,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.transferNotifications),
                subtitle: Text(context.l10n.transferNotificationsSubtitle),
                value: app.notificationsEnabled,
                onChanged: notifier.setNotificationsEnabled,
              ),
              const Divider(height: Spacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.lowDiskAlerts),
                subtitle: Text(context.l10n.lowDiskAlertsSubtitle),
                value: app.lowDiskThresholdBytes > 0,
                onChanged:
                    (on) => notifier.setLowDiskThreshold(
                      on ? 1024 * 1024 * 1024 : 0,
                    ),
              ),
              const Divider(height: Spacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Weekly storage digest'),
                subtitle: const Text(
                  'Once a week, notify me how free space is trending on my hosts',
                ),
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
