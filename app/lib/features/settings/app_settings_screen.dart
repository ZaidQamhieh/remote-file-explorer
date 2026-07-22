import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'about_support_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'file_visibility_screen.dart';
import 'notifications_settings_screen.dart';
import 'storage_security_settings_screen.dart';
import 'transfers_backup_settings_screen.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Global **Settings hub** — card-grouped sections (one rounded surface per
/// section holding all its rows, dividers between rows) matching the
/// mockup's `tab-settings` screen exactly: section labels "Preferences" /
/// "Data" / "Support" (not the old "Personalize" / "Data" / "Info"), and a
/// subtitle under Appearance reflecting the live theme mode + accent color.
///
/// Sync is deliberately NOT listed here even though the mockup shows it in
/// this hub — `SyncScreen` requires a `hostId` and is genuinely per-host,
/// already wired correctly from the per-host settings screen. Forcing it in
/// here would be an architecture regression.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final app = settings.app;
    final appearanceSubtitle =
        '${themeModeLabel(context, app.themeMode)} · '
        '${accentLabel(app.seedColor)} accent';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder:
              (context, snap) => ScreenHeader(
                'Settings',
                subtitle:
                    snap.data != null
                        ? 'RFE Mobile · v${snap.data!.version}'
                        : null,
              ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          SettingsSection(
            title: 'Preferences',
            padded: false,
            children: [
              SettingsTile.nav(
                icon: LucideIcons.palette,
                badgeColor: Brand.accent,
                title: 'Appearance',
                subtitle: appearanceSubtitle,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AppearanceSettingsScreen(),
                      ),
                    ),
              ),
              SettingsTile.nav(
                icon: LucideIcons.bell,
                badgeColor: Brand.amber,
                title: 'Notifications',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotificationsSettingsScreen(),
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Data',
            padded: false,
            children: [
              SettingsTile.nav(
                icon: LucideIcons.shieldCheck,
                badgeColor: Brand.accent,
                title: 'Storage & Security',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StorageSecuritySettingsScreen(),
                      ),
                    ),
              ),
              SettingsTile.nav(
                icon: LucideIcons.arrowUpDown,
                badgeColor: Brand.online,
                title: 'Transfers & Backup',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TransfersBackupSettingsScreen(),
                      ),
                    ),
              ),
              SettingsTile.nav(
                icon: LucideIcons.eye,
                title: 'File Visibility',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FileVisibilityScreen(),
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Support',
            padded: false,
            children: [
              SettingsTile.nav(
                icon: LucideIcons.info,
                title: 'About & Support',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AboutSupportSettingsScreen(),
                      ),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
