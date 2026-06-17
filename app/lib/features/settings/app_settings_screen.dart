import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
import '../photo_backup/photo_backup_screen.dart';
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
      appBar: AppBar(title: Text(context.l10n.appSettingsTitle)),
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
          const BackupRestoreSection(),
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
