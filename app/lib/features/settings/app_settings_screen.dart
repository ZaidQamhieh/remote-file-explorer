import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'about_support_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'notifications_settings_screen.dart';
import 'storage_security_settings_screen.dart';
import 'transfers_backup_settings_screen.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Global **App Settings** — thin top-level nav into 5 grouped categories
/// (Settings Overhaul). Each row pushes its own sub-screen; this file owns
/// no settings state or controls itself.
///
/// Each category gets a dedicated badge colour, reused by every
/// [SettingsTile] inside that category's sub-screen — same "one colour per
/// section" convention the web companion's Settings redesign established.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        children: [
          SettingsTile.nav(
            icon: LucideIcons.palette,
            title: 'Appearance',
            subtitle: 'Theme, layout, sort, file visibility',
            badgeColor: Colors.purple,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AppearanceSettingsScreen(),
                  ),
                ),
          ),
          SettingsTile.nav(
            icon: LucideIcons.arrowUpDown,
            title: 'Transfers & Backup',
            subtitle: 'Photo backup, watched folders, history',
            badgeColor: Colors.green,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TransfersBackupSettingsScreen(),
                  ),
                ),
          ),
          SettingsTile.nav(
            icon: LucideIcons.bell,
            title: 'Notifications & Alerts',
            subtitle: 'Transfers, low disk, weekly digest',
            badgeColor: Colors.amber,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsSettingsScreen(),
                  ),
                ),
          ),
          SettingsTile.nav(
            icon: LucideIcons.shieldCheck,
            title: 'Storage & Security',
            subtitle: 'Cache, App Lock',
            badgeColor: Colors.blue,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StorageSecuritySettingsScreen(),
                  ),
                ),
          ),
          SettingsTile.nav(
            icon: LucideIcons.info,
            title: 'About & Support',
            subtitle: 'Updates, diagnostics, changelog',
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutSupportSettingsScreen(),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
