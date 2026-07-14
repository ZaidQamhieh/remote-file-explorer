import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import 'about_screen.dart';
import 'update_tile.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _slate = Color(0xFFA1A1AA);

/// Updates, diagnostics export, and About/Changelog — the "rarely touched,
/// look-up-when-needed" settings category (Settings Overhaul, group 5 of 5).
class AboutSupportSettingsScreen extends StatelessWidget {
  const AboutSupportSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      // A short, rarely-touched page — top-pinned content on a tall phone
      // would leave a dead black void below it (same fix as Notifications).
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
                const _CreditsHero(),
                const SizedBox(height: Spacing.md),
                SettingsSection(
                  title: context.l10n.updatesSection,
                  padded: false,
                  children: const [UpdateTile()],
                ),
                const SizedBox(height: Spacing.md),
                const _DiagnosticsSection(),
                const SizedBox(height: Spacing.md),
                SettingsSection(
                  title: 'ABOUT',
                  children: [
                    SettingsTile.nav(
                      icon: LucideIcons.info,
                      title: 'About & Changelog',
                      subtitle: 'Version info and what\'s new',
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AboutScreen(),
                            ),
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered credits-style header — app icon, name, and version — replacing
/// the left-aligned [SettingsHero] band on this one screen, since About &
/// Support reads more like a splash/credits screen than a settings category.
class _CreditsHero extends StatelessWidget {
  const _CreditsHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _slate.withValues(alpha: 0.16),
              borderRadius: Radii.cardR,
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.info, size: 26, color: _slate),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'RFE',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final info = snap.data;
              return Text(
                info != null ? 'v${info.version} (${info.buildNumber})' : '…',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends ConsumerWidget {
  const _DiagnosticsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: 'DIAGNOSTICS',
      children: [
        SettingsTile.nav(
          icon: LucideIcons.share2,
          title: context.l10n.diagnosticsExportButton,
          subtitle: context.l10n.diagnosticsExportSubtitle,
          onTap: () => _export(context, ref),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final info = await PackageInfo.fromPlatform();
    final hosts = await ref.read(hostStoreProvider.future);
    final hostList = hosts.listHosts();
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const SettingsState();

    final buf =
        StringBuffer()
          ..writeln('=== RFE Diagnostics ===')
          ..writeln('App: ${info.appName} ${info.version}+${info.buildNumber}')
          ..writeln(
            'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          )
          ..writeln('Dart: ${Platform.version}')
          ..writeln('Locale: ${Platform.localeName}')
          ..writeln()
          ..writeln('--- Settings ---')
          ..writeln('Theme: ${settings.app.themeMode.name}')
          ..writeln('Dynamic color: ${settings.app.dynamicColor}')
          ..writeln('Notifications: ${settings.app.notificationsEnabled}')
          ..writeln(
            'Low-disk threshold: ${formatSize(settings.app.lowDiskThresholdBytes)}',
          )
          ..writeln('Grid view: ${settings.app.gridView}')
          ..writeln('Density: ${settings.app.density.name}')
          ..writeln(
            'Sort: ${settings.app.sort.field.name} ${settings.app.sort.ascending ? "asc" : "desc"}',
          )
          ..writeln()
          ..writeln('--- Hosts (${hostList.length}) ---');

    for (final h in hostList) {
      buf
        ..writeln('  ${h.label}')
        ..writeln('    Address: ${h.address}')
        ..writeln('    Tailscale: ${h.tailscaleAddress ?? "none"}')
        ..writeln('    MAC: ${h.macAddress ?? "none"}');
    }

    buf
      ..writeln()
      ..writeln('Generated: ${DateTime.now().toIso8601String()}');

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      showSuccess(context, context.l10n.diagnosticsCopied);
    }
  }
}
