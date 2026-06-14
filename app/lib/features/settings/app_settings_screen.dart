import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
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
      appBar: AppBar(title: const Text('App settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.md, Spacing.md, Spacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.xs, 0, Spacing.xs, Spacing.md),
            child: Text(
              'These defaults apply to every device. Override any of them for a '
              'single device from that device’s settings.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          SettingsSection(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            children: [
              _LabeledControl(
                label: 'Theme',
                control: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
              ),
              const Divider(height: Spacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use wallpaper colors'),
                subtitle: const Text(
                    'Material You — derive the palette from your wallpaper '
                    'where supported'),
                value: app.dynamicColor,
                onChanged: notifier.setDynamicColor,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Display',
            icon: Icons.grid_view_rounded,
            children: [
              _LabeledControl(
                label: 'Layout',
                control: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('List'),
                      icon: Icon(Icons.view_list_rounded),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Grid'),
                      icon: Icon(Icons.grid_view_rounded),
                    ),
                  ],
                  selected: {app.gridView},
                  onSelectionChanged: (s) => notifier.setAppGridView(s.first),
                ),
              ),
              const Divider(height: Spacing.lg),
              _LabeledControl(
                label: 'Density',
                control: SegmentedButton<EntryDensity>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: EntryDensity.comfortable,
                      label: Text('Comfortable'),
                    ),
                    ButtonSegment(
                      value: EntryDensity.compact,
                      label: Text('Compact'),
                    ),
                  ],
                  selected: {app.density},
                  onSelectionChanged: (s) => notifier.setAppDensity(s.first),
                ),
              ),
              const Divider(height: Spacing.lg),
              _LabeledControl(
                label: 'Sort by',
                control: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final field in SortField.values)
                      ChoiceChip(
                        label: Text(_sortFieldLabel(field)),
                        selected: app.sort.field == field,
                        avatar: app.sort.field == field
                            ? Icon(
                                app.sort.ascending
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 18,
                              )
                            : null,
                        onSelected: (_) {
                          if (app.sort.field == field) {
                            notifier.setAppSort(app.sort
                                .copyWith(ascending: !app.sort.ascending));
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
          Align(alignment: Alignment.centerLeft, child: control),
        ],
      ),
    );
  }
}

String _sortFieldLabel(SortField field) => switch (field) {
      SortField.name => 'Name',
      SortField.size => 'Size',
      SortField.date => 'Date modified',
      SortField.type => 'Type',
    };
