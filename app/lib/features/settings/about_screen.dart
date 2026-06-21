import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/tokens.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _changelog = <_ChangelogEntry>[
    _ChangelogEntry('v1.21.0', [
      'File checksums (SHA-256/SHA-1/MD5)',
      'Symlink target display',
      'Transfer history journal',
      'Read-only host badge',
      'Biometric app lock',
      'AMOLED dark theme',
      'Accent color picker',
    ]),
    _ChangelogEntry('v1.20.0', [
      'Notification preferences',
      'Low disk alerts',
      'Wake-on-LAN relay',
      'Saved searches with glob/regex',
      'Diagnostics export',
    ]),
    _ChangelogEntry('v1.19.0', [
      'Listing cache',
      'Onboarding flow',
      'Explorer refactor',
      'Search refactor',
    ]),
    _ChangelogEntry('v1.18.0', [
      'Arabic/RTL localization',
      'Wake-on-LAN',
      'Open with system apps',
      'Gallery view',
      'Bandwidth throttling',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final info = snap.data;
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: Radii.lgR,
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    size: 36,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Center(
                child: Text(
                  'Remote File Explorer',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Center(
                child: Text(
                  info != null ? 'v${info.version}+${info.buildNumber}' : '...',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Center(
                child: Text(
                  'Browse, transfer, and manage files on your PCs from your phone.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: Spacing.xl),
              Text(
                'Changelog',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.md),
              for (final entry in _changelog) ...[
                Text(
                  entry.version,
                  style: textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: Spacing.xs),
                for (final item in entry.items)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: Spacing.md,
                      bottom: Spacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('  •  ', style: textTheme.bodyMedium),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
                const SizedBox(height: Spacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ChangelogEntry {
  const _ChangelogEntry(this.version, this.items);
  final String version;
  final List<String> items;
}
