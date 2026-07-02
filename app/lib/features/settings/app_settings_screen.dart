import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/cache_manager.dart';
import '../../core/storage/host_store.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/screen_header.dart';
import '../photo_backup/photo_backup_screen.dart';
import '../transfers/transfer_journal_screen.dart';
import 'about_screen.dart';
import 'settings_screen.dart' show FileVisibilitySection;
import 'update_tile.dart';
import 'widgets/backup_restore_section.dart';
import 'widgets/settings_section.dart';

/// Global **App Settings** — the single "general settings" surface (Wave 0).
///
/// This is the one source of truth for app-wide defaults; per-device settings
/// (in each host's settings screen) only override these deliberately. v1 covers
/// the view defaults (layout, density, sort); future waves add theme, update
/// channel, etc. here.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final app = settings.app;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.xs,
              0,
              Spacing.xs,
              Spacing.md,
            ),
            child: Text(
              context.l10n.defaultsApplyHint,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          SettingsSection(
            title: context.l10n.appearanceSection,
            icon: Icons.palette_outlined,
            children: [
              _LabeledControl(
                label: context.l10n.themeLabel,
                control: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(context.l10n.systemTheme),
                      icon: const Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(context.l10n.lightTheme),
                      icon: const Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(context.l10n.darkTheme),
                      icon: const Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
              ),
              const Divider(height: Spacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.useWallpaperColors),
                subtitle: Text(context.l10n.wallpaperSubtitle),
                value: app.dynamicColor,
                onChanged: notifier.setDynamicColor,
              ),
              const Divider(height: Spacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('AMOLED Dark'),
                subtitle: const Text('Pure black background in dark mode'),
                value: app.amoledDark,
                onChanged: notifier.setAmoledDark,
              ),
              const Divider(height: Spacing.lg),
              _LabeledControl(
                label: 'Accent Color',
                control: _AccentColorPicker(
                  selected: app.seedColor,
                  onChanged: notifier.setSeedColor,
                ),
              ),
              const Divider(height: Spacing.lg),
              _LabeledControl(
                label: context.l10n.languageLabel,
                control: SegmentedButton<Locale?>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: null,
                      label: Text(context.l10n.systemTheme),
                    ),
                    const ButtonSegment(
                      value: Locale('en'),
                      label: Text('English'),
                    ),
                    const ButtonSegment(
                      value: Locale('ar'),
                      label: Text('العربية'),
                    ),
                  ],
                  selected: {app.locale},
                  onSelectionChanged: (s) => notifier.setLocale(s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.displaySection,
            icon: Icons.grid_view_rounded,
            children: [
              _LabeledControl(
                label: context.l10n.layoutLabel,
                control: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.l10n.listLabel),
                      icon: const Icon(Icons.view_list_rounded),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.l10n.gridLabel),
                      icon: const Icon(Icons.grid_view_rounded),
                    ),
                  ],
                  selected: {app.gridView},
                  onSelectionChanged: (s) => notifier.setAppGridView(s.first),
                ),
              ),
              const Divider(height: Spacing.lg),
              _LabeledControl(
                label: context.l10n.densityLabel,
                control: SegmentedButton<EntryDensity>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: EntryDensity.comfortable,
                      label: Text(context.l10n.comfortableLabel),
                    ),
                    ButtonSegment(
                      value: EntryDensity.compact,
                      label: Text(context.l10n.compactLabel),
                    ),
                  ],
                  selected: {app.density},
                  onSelectionChanged: (s) => notifier.setAppDensity(s.first),
                ),
              ),
              const Divider(height: Spacing.lg),
              _LabeledControl(
                label: context.l10n.sortByLabel,
                control: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final field in SortField.values)
                      ChoiceChip(
                        label: Text(_sortFieldLabel(context, field)),
                        selected: app.sort.field == field,
                        avatar:
                            app.sort.field == field
                                ? Icon(
                                  app.sort.ascending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 18,
                                )
                                : null,
                        onSelected: (_) {
                          if (app.sort.field == field) {
                            notifier.setAppSort(
                              app.sort.copyWith(ascending: !app.sort.ascending),
                            );
                          } else {
                            notifier.setAppSort(SortOrder(field: field));
                          }
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: Spacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Preload previews on cellular'),
                subtitle: const Text(
                  'Warm neighbouring images while swiping the preview, even '
                  'off Wi-Fi',
                ),
                value: app.preloadPreviewOnCellular,
                onChanged: notifier.setPreloadPreviewOnCellular,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.updatesSection,
            icon: Icons.system_update_alt_outlined,
            padded: false,
            children: const [UpdateTile()],
          ),
          const SizedBox(height: Spacing.md),
          // App-default file visibility (per-device overrides live on each
          // host's settings screen). Self-contained card; reused from
          // settings_screen.dart where the editor + override section are defined.
          const FileVisibilitySection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.photoBackupSection,
            icon: Icons.photo_library_outlined,
            padded: false,
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(context.l10n.photoBackupTitle),
                subtitle: Text(context.l10n.copyPhonePhotos),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PhotoBackupScreen(),
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.notificationsSection,
            icon: Icons.notifications_outlined,
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
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Transfers',
            icon: Icons.swap_vert_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compress downloads on cellular'),
                subtitle: const Text(
                  'Sends Accept-Encoding: gzip on mobile data for '
                  'compressible files (text, logs, source code)',
                ),
                value: app.compressDownloadsOnCellular,
                onChanged: notifier.setCompressDownloadsOnCellular,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const _WatchedFoldersSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Security',
            icon: Icons.security_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('App Lock'),
                subtitle: const Text('Require biometric or PIN to open'),
                value: app.appLockEnabled,
                onChanged: notifier.setAppLockEnabled,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const _CacheSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Transfer History',
            icon: Icons.history_outlined,
            padded: false,
            children: [
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('View Transfer History'),
                subtitle: const Text('Completed uploads and downloads'),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TransferJournalScreen(),
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const _DiagnosticsSection(),
          const SizedBox(height: Spacing.md),
          const BackupRestoreSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'About',
            icon: Icons.info_outline,
            padded: false,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About & Changelog'),
                subtitle: const Text('Version info and what\'s new'),
                trailing: const Icon(Icons.chevron_right),
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
    );
  }
}

/// A stacked label-over-control row for the App Settings cards.
class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.control});

  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.sm),
          Align(alignment: AlignmentDirectional.centerStart, child: control),
        ],
      ),
    );
  }
}

String _sortFieldLabel(BuildContext context, SortField field) =>
    switch (field) {
      SortField.name => context.l10n.sortFieldName,
      SortField.size => context.l10n.sortFieldSize,
      SortField.date => context.l10n.sortFieldDate,
      SortField.type => context.l10n.sortFieldType,
    };

class _CacheSection extends ConsumerWidget {
  const _CacheSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(cacheStatsProvider);
    final scheme = Theme.of(context).colorScheme;

    return SettingsSection(
      title: context.l10n.cacheSection,
      icon: Icons.cached_rounded,
      children: [
        statsAsync.when(
          loading:
              () => Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text(
                  context.l10n.cacheCalculating,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
          error: (_, __) => const SizedBox.shrink(),
          data: (stats) {
            return Column(
              children: [
                _CacheRow(
                  label: context.l10n.cacheListingLabel,
                  bytes: stats.listingBytes,
                ),
                _CacheRow(
                  label: context.l10n.cacheTempLabel,
                  bytes: stats.tempBytes,
                ),
                const Divider(height: Spacing.lg),
                _CacheRow(
                  label: context.l10n.cacheTotalLabel,
                  bytes: stats.totalBytes,
                  bold: true,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Spacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(context.l10n.cacheClearAll),
            onPressed: () async {
              await ref.read(cacheManagerProvider).clearAll();
              ref.invalidate(cacheStatsProvider);
              if (context.mounted) {
                showSuccess(context, context.l10n.cacheCleared);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.label,
    required this.bytes,
    this.bold = false,
  });

  final String label;
  final int bytes;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w600 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatSize(bytes), style: style),
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
      title: context.l10n.diagnosticsExportTitle,
      icon: Icons.bug_report_outlined,
      padded: false,
      children: [
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: Text(context.l10n.diagnosticsExportButton),
          subtitle: Text(context.l10n.diagnosticsExportSubtitle),
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

class _AccentColorPicker extends StatelessWidget {
  const _AccentColorPicker({required this.selected, required this.onChanged});

  final Color? selected;
  final ValueChanged<Color?> onChanged;

  static const _presets = <Color?>[
    null,
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0xFFFF5722),
    Color(0xFF9C27B0),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF009688),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final preset in _presets)
          GestureDetector(
            onTap: () => onChanged(preset),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: preset ?? Brand.seed,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected == preset ? scheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
              child:
                  selected == preset
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
            ),
          ),
      ],
    );
  }
}

/// Lists watched folders and lets the user add or remove them.
///
/// A watched folder causes a local notification whenever the SSE stream reports
/// a file-create event inside it (L3). Folders are added by typing a remote
/// path; the toggle on each entry removes it.
class _WatchedFoldersSection extends ConsumerWidget {
  const _WatchedFoldersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final folders = settings.app.watchedFolders.toList()..sort();

    return SettingsSection(
      title: 'Watched folders',
      icon: Icons.folder_special_outlined,
      padded: false,
      children: [
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              'No watched folders. Add a remote folder path below to get notified when new files appear there.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final folder in folders)
          ListTile(
            dense: true,
            title: Text(folder, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Stop watching',
              onPressed: () => notifier.removeWatchedFolder(folder),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add folder path'),
          onTap: () => _showAddDialog(context, notifier),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    SettingsNotifier notifier,
  ) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Watch a folder'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '/home/user/Downloads',
                labelText: 'Remote folder path',
              ),
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Watch'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (path != null && path.isNotEmpty) {
      await notifier.addWatchedFolder(path);
    }
  }
}
