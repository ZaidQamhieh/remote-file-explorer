import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'about_support_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'notifications_settings_screen.dart';
import 'storage_security_settings_screen.dart';
import 'transfers_backup_settings_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Global **App Settings** — a 2-column tile grid (Settings redesign v2) into
/// 5 grouped categories. Each tile pushes its own sub-screen; this file owns
/// no settings state or controls itself.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: _HubTile(
                  icon: LucideIcons.palette,
                  title: 'Appearance',
                  subtitle: 'Theme, layout, sort, visibility',
                  tint: Colors.purple,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppearanceSettingsScreen(),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: Spacing.md2),
              Expanded(
                child: _HubTile(
                  icon: LucideIcons.arrowUpDown,
                  title: 'Transfers & Backup',
                  subtitle: 'Photo backup, watched folders, history',
                  tint: Colors.green,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TransfersBackupSettingsScreen(),
                        ),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md2),
          Row(
            children: [
              Expanded(
                child: _HubTile(
                  icon: LucideIcons.bell,
                  title: 'Notifications & Alerts',
                  subtitle: 'Transfers, low disk, weekly digest',
                  tint: Colors.amber,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NotificationsSettingsScreen(),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: Spacing.md2),
              Expanded(
                child: _HubTile(
                  icon: LucideIcons.shieldCheck,
                  title: 'Storage & Security',
                  subtitle: 'Cache, App Lock',
                  tint: Colors.blue,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StorageSecuritySettingsScreen(),
                        ),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md2),
          _HubTile(
            icon: LucideIcons.info,
            title: 'About & Support',
            subtitle: 'Updates, diagnostics, changelog',
            tint: Colors.blueGrey,
            wide: true,
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

/// One tile in the hub's tile grid: a category-tinted flat card (no glow),
/// a tonal icon badge, title, and subtitle. [wide] spans both grid columns
/// (used for the lone About & Support tile) and lays out horizontally
/// instead of stacking icon-over-text.
class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
    this.wide = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.22),
        borderRadius: Radii.smR,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: tint),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: wide ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );

    final child =
        wide
            ? Row(
              children: [
                badge,
                const SizedBox(width: Spacing.md),
                Expanded(child: text),
              ],
            )
            : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [badge, text],
            );

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: Radii.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.lgR,
        child: Container(
          height: wide ? 74 : 128,
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.md2,
          ),
          decoration: BoxDecoration(
            borderRadius: Radii.lgR,
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}
