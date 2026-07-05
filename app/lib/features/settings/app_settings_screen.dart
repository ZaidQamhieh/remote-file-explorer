import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'about_support_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'notifications_settings_screen.dart';
import 'storage_security_settings_screen.dart';
import 'transfers_backup_settings_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Global **App Settings** — thin top-level nav into 5 grouped categories
/// (Settings Overhaul). Each row pushes its own sub-screen; this file owns
/// no settings state or controls itself.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        children: [
          _CategoryTile(
            icon: LucideIcons.palette,
            title: 'Appearance',
            subtitle: 'Theme, layout, sort, file visibility',
            builder: (_) => const AppearanceSettingsScreen(),
          ),
          _CategoryTile(
            icon: LucideIcons.arrowUpDown,
            title: 'Transfers & Backup',
            subtitle: 'Photo backup, watched folders, history',
            builder: (_) => const TransfersBackupSettingsScreen(),
          ),
          _CategoryTile(
            icon: LucideIcons.bell,
            title: 'Notifications & Alerts',
            subtitle: 'Transfers, low disk, weekly digest',
            builder: (_) => const NotificationsSettingsScreen(),
          ),
          _CategoryTile(
            icon: LucideIcons.shieldCheck,
            title: 'Storage & Security',
            subtitle: 'Cache, App Lock',
            builder: (_) => const StorageSecuritySettingsScreen(),
          ),
          _CategoryTile(
            icon: LucideIcons.info,
            title: 'About & Support',
            subtitle: 'Updates, diagnostics, changelog',
            builder: (_) => const AboutSupportSettingsScreen(),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap:
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: builder)),
    );
  }
}
