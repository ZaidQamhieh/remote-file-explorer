import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import '../photo_backup/photo_backup_screen.dart';
import '../transfers/transfer_journal_screen.dart';
import 'widgets/backup_restore_section.dart';
import 'widgets/settings_hero.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Everything about moving/protecting data: photo backup, watched folders,
/// cellular compression, transfer history, and config backup/restore
/// (Settings Overhaul, group 2 of 5).
class TransfersBackupSettingsScreen extends ConsumerWidget {
  const TransfersBackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          const SettingsHero(
            icon: LucideIcons.arrowUpDown,
            title: 'Transfers & Backup',
            subtitle: 'Photo backup, watched folders & history',
            tint: Colors.green,
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.photoBackupSection,
            children: [
              SettingsTile.nav(
                icon: LucideIcons.cloudUpload,
                badgeColor: Colors.green,
                title: context.l10n.photoBackupTitle,
                subtitle: context.l10n.copyPhonePhotos,
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
            title: 'Transfers',
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.arrowUpDown,
                badgeColor: Colors.green,
                title: 'Compress downloads on cellular',
                subtitle:
                    'Sends Accept-Encoding: gzip on mobile data for '
                    'compressible files (text, logs, source code)',
                value: settings.app.compressDownloadsOnCellular,
                onChanged: notifier.setCompressDownloadsOnCellular,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const _WatchedFoldersSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'History',
            children: [
              SettingsTile.nav(
                icon: LucideIcons.history,
                badgeColor: Colors.green,
                title: 'View transfer history',
                subtitle: 'Completed uploads and downloads',
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
          SettingsSection(
            title: 'Backup & restore',
            padded: false,
            children: const [BackupRestoreSection()],
          ),
        ],
      ),
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
              icon: const Icon(LucideIcons.circleMinus),
              tooltip: 'Stop watching',
              onPressed: () => notifier.removeWatchedFolder(folder),
            ),
          ),
        ListTile(
          leading: const Icon(LucideIcons.plus),
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
