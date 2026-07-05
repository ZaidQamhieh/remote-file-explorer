import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'settings_screen.dart' show FileVisibilitySection;
import 'widgets/settings_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Theme, layout, density, sort, and file-visibility defaults — everything
/// about how the app looks and lists files (Settings Overhaul, group 1 of 5;
/// merges the old "Appearance" and "Display" sections).
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final app = settings.app;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const ScreenHeader('Appearance'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          SettingsSection(
            title: context.l10n.appearanceSection,
            icon: LucideIcons.palette,
            children: [
              _LabeledControl(
                label: context.l10n.themeLabel,
                control: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(context.l10n.systemTheme),
                      icon: const Icon(LucideIcons.sunMoon),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(context.l10n.lightTheme),
                      icon: const Icon(LucideIcons.sun),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(context.l10n.darkTheme),
                      icon: const Icon(LucideIcons.moon),
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
            icon: LucideIcons.layoutGrid,
            children: [
              _LabeledControl(
                label: context.l10n.layoutLabel,
                control: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.l10n.listLabel),
                      icon: const Icon(LucideIcons.list),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.l10n.gridLabel),
                      icon: const Icon(LucideIcons.layoutGrid),
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
                                      ? LucideIcons.arrowUp
                                      : LucideIcons.arrowDown,
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
          const FileVisibilitySection(),
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
                      ? const Icon(
                        LucideIcons.check,
                        size: 18,
                        color: Colors.white,
                      )
                      : null,
            ),
          ),
      ],
    );
  }
}
