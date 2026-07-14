import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'about_support_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'notifications_settings_screen.dart';
import 'storage_security_settings_screen.dart';
import 'transfers_backup_settings_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Global **App Settings** — categories grouped under section labels
/// (Personalize / Data / Info) as flat rows, each with a gradient icon
/// circle (Settings redesign v3). Each row pushes its own sub-screen; this
/// file owns no settings state or controls itself.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          const _SectionLabel('Personalize'),
          _HubRow(
            icon: LucideIcons.palette,
            title: 'Appearance',
            gradient: const [Color(0xFFC4B5FD), Color(0xFF7C3AED)],
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AppearanceSettingsScreen(),
                  ),
                ),
          ),
          _HubRow(
            icon: LucideIcons.bell,
            title: 'Notifications & Alerts',
            gradient: const [Color(0xFFFDE68A), Color(0xFFD97706)],
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsSettingsScreen(),
                  ),
                ),
          ),
          const _SectionLabel('Data'),
          _HubRow(
            icon: LucideIcons.arrowUpDown,
            title: 'Transfers & Backup',
            gradient: const [Color(0xFF6EE7B7), Color(0xFF059669)],
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TransfersBackupSettingsScreen(),
                  ),
                ),
          ),
          _HubRow(
            icon: LucideIcons.shieldCheck,
            title: 'Storage & Security',
            gradient: const [Color(0xFF93C5FD), Color(0xFF2563EB)],
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StorageSecuritySettingsScreen(),
                  ),
                ),
          ),
          const _SectionLabel('Info'),
          _HubRow(
            icon: LucideIcons.info,
            title: 'About & Support',
            gradient: const [Color(0xFFD4D4D8), Color(0xFF52525B)],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xs,
        Spacing.md,
        Spacing.xs,
        Spacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// One row in the hub: a gradient icon circle (same recipe as
/// [GradientActionCircle], the host action sheet's shared component) and a
/// title, in a flat tappable card.
class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.cardR,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.cardR,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.last.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
