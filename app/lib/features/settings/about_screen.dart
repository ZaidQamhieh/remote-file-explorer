import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _changelog = <_ChangelogEntry>[
    _ChangelogEntry('v1.41.10', [
      'Per-PC device settings (read-only mode, bandwidth, paired devices) now '
          'carries the same hero banner + circular icon badges as the rest of '
          'Settings — it was missed in the v1.41.8 redesign pass',
    ]),
    _ChangelogEntry('v1.41.9', [
      'Launcher icon background changed from indigo to white',
    ]),
    _ChangelogEntry('v1.41.8', [
      'Settings redesigned: a 2-column tile grid up top, each category opening on its own colour-tinted hero header',
      'Settings rows now show circular icon badges and pill-style value chips; Storage & Security gets a cache usage bar',
    ]),
    _ChangelogEntry('v1.41.7', [
      'Bottom nav, buttons/chips, and Settings rows now carry the same visual language as the rest of the app',
      'Screen transitions and list entrances get a subtle fade/slide everywhere, not just Files and Servers',
    ]),
    _ChangelogEntry('v1.41.6', [
      'New app icon — the real RFE mark instead of the default Flutter icon',
      'MetaSheet\'s look (gradient header + quick actions) rolled out across the whole app',
    ]),
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

  /// Matches the mockup's `about` screen: centered gradient app mark, name,
  /// mono version+build, a plain list of two nav rows ("What's new" /
  /// "Privacy policy"), and the footer tagline — instead of the old inline
  /// changelog card. The changelog itself is real (unchanged) data, just
  /// moved behind the "What's new" tap target to match the mockup's shape;
  /// "Privacy policy" pushes a short, factual note derived from this app's
  /// actual architecture (no cloud, no account, no analytics/telemetry
  /// anywhere in the codebase — see `CLAUDE.md`), not placeholder/fabricated
  /// legal text.
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
              const SizedBox(height: Spacing.md),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Brand.seed, Brand.accent],
                    ),
                    borderRadius: Radii.lgR,
                  ),
                  child: const Icon(
                    LucideIcons.folderOpen,
                    size: 30,
                    color: Colors.white,
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
                  info != null
                      ? 'v${info.version} · build ${info.buildNumber}'
                      : '…',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xl),
              GroupedCard(
                padded: false,
                children: [
                  _NavRow(
                    title: "What's new",
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ChangelogScreen(_changelog),
                          ),
                        ),
                  ),
                  const Divider(height: 1),
                  _NavRow(
                    title: 'Privacy policy',
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _PrivacyPolicyScreen(),
                          ),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xl),
              Center(
                child: Text(
                  'No cloud. No account. Your PCs, your network.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChangelogScreen extends StatelessWidget {
  const _ChangelogScreen(this.entries);
  final List<_ChangelogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          GroupedCard(
            padded: false,
            children: [
              for (int i = 0; i < entries.length; i++) ...[
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
                        entries[i].version,
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      for (final item in entries[i].items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.xs),
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
      ),
    );
  }
}

class _PrivacyPolicyScreen extends StatelessWidget {
  const _PrivacyPolicyScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Text(
            'Remote File Explorer has no cloud server, no cloud database, '
            'and no user account. It connects directly from your phone to '
            'your own paired PCs over your LAN or your Tailscale network — '
            'the same code path either way.\n\n'
            'The app collects no analytics and no telemetry: there is no '
            'crash reporter, no usage tracking, and no third-party SDK that '
            'phones anything home. Files you browse or transfer never pass '
            'through any server operated by the developer or anyone else.\n\n'
            'Diagnostics export (Support → Export diagnostics) is the one '
            'place data leaves the app boundary at all, and only when you '
            'explicitly trigger it — it copies a plain-text summary to your '
            'clipboard for you to share yourself; nothing is sent '
            'automatically.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogEntry {
  const _ChangelogEntry(this.version, this.items);
  final String version;
  final List<String> items;
}

/// The mockup's plain `.row` (no `.row-icon` — the About screen's `.px list`
/// rows have no leading icon at all): 14px/500 title + bare chevron.
/// Replaces a raw [ListTile].
class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md2,
          vertical: 11,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
