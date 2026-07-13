import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _changelog = <_ChangelogEntry>[
    _ChangelogEntry('v1.41.4', [
      'Allowed folders are now managed from the web companion, not the phone',
    ]),
    _ChangelogEntry('v1.41.3', [
      'Search: visual polish pass — gradient scope pill, shimmer loading, tinted app bar',
    ]),
    _ChangelogEntry('v1.41.2', [
      'File-action sheet: redesigned as quick-action row + list, no more layout gaps',
      'Accent color picker (and other option sheets) now scroll properly',
      'Search: faster on unscoped searches, path queries resolve instantly',
      'Search: decluttered filters, skeleton loading instead of a spinner',
    ]),
    _ChangelogEntry('v1.41.1', [
      'Redesigned file-action sheet to match the Figma mockup',
      'Clearer error messages instead of raw technical dumps',
    ]),
    _ChangelogEntry('v1.41.0', [
      'File-action sheet: primary actions + overflow menu',
      'Video preview now streams instead of downloading first',
      'Transfer queue survives app restarts',
      'English-only (dropped incomplete Arabic translations)',
    ]),
    _ChangelogEntry('v1.40.0', [
      'True-black AMOLED cards with hairline borders',
      'Reorganized File Visibility into a collapsible screen',
    ]),
    _ChangelogEntry('v1.38.0 – v1.39.0', [
      'Settings reorganized into 5 category screens',
      'Unified settings row/picker design across all screens',
    ]),
    _ChangelogEntry('v1.34.0 – v1.37.0', [
      'Web companion: browse, control, and monitor from any browser',
      'Username/password login for phone and web',
      'Live CPU/RAM/network dashboard, Transfers/Users/Logs pages',
      'Recents view (recently modified files across the server)',
      'Photo backup: choose albums, server-owned destination',
    ]),
    _ChangelogEntry('v1.28.0 – v1.33.0', [
      'Visual re-skin: new dark theme and redesigned navigation',
    ]),
    _ChangelogEntry('v1.27.0', [
      'Persistent bottom navigation (Servers/Files/Transfers/Settings)',
      'Background update pre-download',
    ]),
    _ChangelogEntry('v1.25.0', [
      'One-time share links',
      'Phone-to-phone file transfer via QR code',
      'Weekly storage digest',
      'Keyboard shortcuts and type-ahead jump',
    ]),
    _ChangelogEntry('v1.24.0', [
      'Offline pinning (view cached files without a connection)',
      'File bookmarks with tags',
      'New-file notifications for watched folders',
      'Agent status dashboard on host cards',
    ]),
    _ChangelogEntry('v1.23.0', [
      'Live updates via SSE (auto-refresh on file changes)',
      'Permission editing (chmod dialog)',
      'mDNS agent discovery on local network',
      'Archive browser (zip/tar preview)',
      'Duplicate file finder',
      'Sync rules (download remote folders)',
      'Cross-host search',
      'Command palette',
    ]),
    _ChangelogEntry('v1.22.0', [
      'Audio player with playback speed',
      'Markdown file preview',
      'CSV table preview',
      'Video resume & double-tap seek',
      'Storage-by-type breakdown',
    ]),
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
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('About')),
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
                    LucideIcons.folderOpen,
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
              const SectionLabel('Changelog'),
              GroupedCard(
                padded: false,
                children: [
                  for (int i = 0; i < _changelog.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: Spacing.md,
                        endIndent: Spacing.md,
                        color: scheme.outlineVariant,
                      ),
                    Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _changelog[i].version,
                            style: textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                          for (final item in _changelog[i].items)
                            Padding(
                              padding: const EdgeInsets.only(
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
                        ],
                      ),
                    ),
                  ],
                ],
              ),
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
