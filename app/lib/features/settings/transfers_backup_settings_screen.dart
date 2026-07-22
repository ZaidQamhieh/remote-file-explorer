import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/pressable.dart';
import '../transfers/chunk_planner.dart' show describeDefaultChunkSize;
import '../photo_backup/photo_backup_screen.dart';
import '../transfers/transfer_journal_screen.dart';
import 'widgets/backup_restore_section.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// Everything about moving/protecting data: transfer engine, photo backup,
/// watched folders, transfer history, and config backup/restore (Settings
/// Overhaul, group 2 of 5).
///
/// Mockup's `settings-transfers-backup` screen shows a "Transfer engine"
/// section with a parallel-chunks segmented control (1/2/4) and a "Wi-Fi
/// only" toggle. Neither exists as a real setting — transfer parallelism
/// isn't user-configurable and the real per-transfer network gate is
/// "compress downloads on cellular", not "Wi-Fi only" (different semantics:
/// it still transfers on cellular, just compressed). The chunk *size* badge
/// (mockup shows "4 MB") is real — `chunk_planner.dart`'s fixed 4 MB
/// constant — so that one row is genuine, read-only data, not fabricated.
class TransfersBackupSettingsScreen extends ConsumerWidget {
  const TransfersBackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfers & Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          SettingsSection(
            title: 'Transfer engine',
            padded: false,
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.arrowUpDown,
                badgeColor: Brand.online,
                title: 'Compress downloads on cellular',
                subtitle:
                    'Sends Accept-Encoding: gzip on mobile data for '
                    'compressible files (text, logs, source code)',
                value: settings.app.compressDownloadsOnCellular,
                onChanged: notifier.setCompressDownloadsOnCellular,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Chunk size',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _NeutralBadge(describeDefaultChunkSize()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Photo backup',
            padded: false,
            children: [
              SettingsTile.nav(
                icon: LucideIcons.cloudUpload,
                badgeColor: Brand.online,
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
          const _WatchedFoldersSection(),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'History',
            padded: false,
            children: [
              SettingsTile.nav(
                icon: LucideIcons.history,
                badgeColor: Brand.online,
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
          const BackupRestoreSection(),
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
      title: context.l10n.watchedFoldersTitle,
      padded: false,
      children: [
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              context.l10n.watchedFoldersEmpty,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final folder in folders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            child: Row(
              children: [
                _folderBadge(LucideIcons.folder),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    folder,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Tooltip(
                  message: context.l10n.stopWatchingTooltip,
                  child: Pressable(
                    onTap: () => notifier.removeWatchedFolder(folder),
                    pressedScale: 0.92,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        LucideIcons.circleMinus,
                        size: 19,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Pressable(
          onTap: () => _showAddDialog(context, notifier),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            child: Row(
              children: [
                _folderBadge(LucideIcons.plus),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.addFolderPathTile,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Same tonal square badge recipe as [SettingsTile]'s `.row-icon`, so
  /// watched-folder rows don't look bare next to every other row on this
  /// screen.
  Widget _folderBadge(IconData icon) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: Brand.online.withValues(alpha: 0.14),
      borderRadius: Radii.smR,
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 18, color: Brand.online),
  );

  Future<void> _showAddDialog(
    BuildContext context,
    SettingsNotifier notifier,
  ) async {
    final controller = TextEditingController();
    final path = await showShadDialog<String>(
      context: context,
      builder:
          (ctx) => ShadDialog.alert(
            title: Text(ctx.l10n.watchAFolderTitle),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: Text(ctx.l10n.watchButton),
              ),
            ],
            child: ShadInput(
              controller: controller,
              placeholder: const Text('/home/user/Downloads'),
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ),
    );
    controller.dispose();
    if (path != null && path.isNotEmpty) {
      await notifier.addWatchedFolder(path);
    }
  }
}

/// The mockup's `.badge.neutral`: `surface-3` bg, `text-dim` text, pill.
class _NeutralBadge extends StatelessWidget {
  const _NeutralBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'JetBrains Mono',
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
