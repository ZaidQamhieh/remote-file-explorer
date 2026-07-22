import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import 'widgets/settings_picker.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Theme, accent, layout, density, and sort — everything about how the app
/// looks and lists files (Settings Overhaul, group 1 of 5; merges the old
/// "Appearance" and "Display" sections).
///
/// Structure matches the mockup's `settings-appearance` screen: an inline
/// theme-swatch grid and accent-color dot row (no value-row + bottom-sheet
/// picker for those two — tap directly selects). File visibility moved to a
/// top-level Settings-hub entry (mockup's `tab-settings` Data section) so it
/// no longer lives here.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final app = settings.app;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          const SectionLabel('Theme'),
          // ponytail: mockup shows 6 swatches (Dark/AMOLED/Light/Dracula/
          // Nord/System) as first-class theme presets. The real settings
          // model only has ThemeMode (system/light/dark) plus a separate
          // `amoledDark` bool modifier — no Dracula/Nord palettes exist.
          // Built the swatch grid for the 3 real modes only; AMOLED stays
          // where it already was (the quick-toggle grid below) rather than
          // faking 3 more theme presets with no backing implementation.
          _ThemeSwatchGrid(
            selected: app.themeMode,
            onSelected: notifier.setThemeMode,
          ),
          const SizedBox(height: Spacing.md),
          const SectionLabel('Accent color'),
          _AccentDotRow(
            selected: app.seedColor,
            onSelected: notifier.setSeedColor,
          ),
          // ponytail: mockup also has a "Text size" segmented control here —
          // no text-scale setting exists anywhere in AppDefaults/the
          // notifier, so it's omitted rather than shipping a dead control.
          // Add a real `textScale` setting first if this is wanted.
          const SizedBox(height: Spacing.md),
          // A fixed-childAspectRatio GridView doesn't fit these tiles' natural
          // (variable, sometimes 2-line-caption) height — it left large dead
          // space in every cell. A same-order 2-column-of-natural-height
          // layout keeps the same visual grid without forcing a bad ratio.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _QuickToggleTile(
                      icon: LucideIcons.image,
                      title: context.l10n.useWallpaperColors,
                      value: app.dynamicColor,
                      onTap: () => notifier.setDynamicColor(!app.dynamicColor),
                    ),
                    const SizedBox(height: Spacing.sm),
                    _QuickToggleTile(
                      icon:
                          app.gridView
                              ? LucideIcons.layoutGrid
                              : LucideIcons.list,
                      title: context.l10n.layoutLabel,
                      caption:
                          app.gridView
                              ? context.l10n.gridLabel
                              : context.l10n.listLabel,
                      onTap: () => notifier.setAppGridView(!app.gridView),
                    ),
                    const SizedBox(height: Spacing.sm),
                    _QuickToggleTile(
                      icon: LucideIcons.wifi,
                      title: 'Preload on cellular',
                      value: app.preloadPreviewOnCellular,
                      onTap:
                          () => notifier.setPreloadPreviewOnCellular(
                            !app.preloadPreviewOnCellular,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  children: [
                    _QuickToggleTile(
                      icon: LucideIcons.moon,
                      title: 'AMOLED Dark',
                      value: app.amoledDark,
                      onTap: () => notifier.setAmoledDark(!app.amoledDark),
                    ),
                    const SizedBox(height: Spacing.sm),
                    _QuickToggleTile(
                      icon: LucideIcons.rows3,
                      title: context.l10n.densityLabel,
                      caption:
                          app.density == EntryDensity.compact
                              ? context.l10n.compactLabel
                              : context.l10n.comfortableLabel,
                      onTap:
                          () => notifier.setAppDensity(
                            app.density == EntryDensity.compact
                                ? EntryDensity.comfortable
                                : EntryDensity.compact,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Sort-by isn't in the mockup's Appearance screen at all (it only
          // mocks Theme/Accent/Text size) — kept as a real, working setting
          // rather than deleted; it just doesn't map to any mockup section.
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Sort',
            children: [
              SettingsTile.value(
                icon: LucideIcons.arrowUpDown,
                badgeColor: Brand.accent,
                title: context.l10n.sortByLabel,
                value:
                    '${_sortFieldLabel(context, app.sort.field)} '
                    '${app.sort.ascending ? '↑' : '↓'}',
                onTap: () async {
                  final picked = await showSettingsPicker<SortField>(
                    context,
                    title: context.l10n.sortByLabel,
                    selected: app.sort.field,
                    options: [
                      for (final field in SortField.values)
                        SettingsOption(field, _sortFieldLabel(context, field)),
                    ],
                  );
                  if (picked == null) return;
                  if (app.sort.field == picked) {
                    notifier.setAppSort(
                      app.sort.copyWith(ascending: !app.sort.ascending),
                    );
                  } else {
                    notifier.setAppSort(SortOrder(field: picked));
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline theme picker matching the mockup's `.theme-grid`: a 3-column grid
/// of tappable preview swatches (no value-row + bottom-sheet).
class _ThemeSwatchGrid extends StatelessWidget {
  const _ThemeSwatchGrid({required this.selected, required this.onSelected});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.sm,
      crossAxisSpacing: Spacing.sm,
      childAspectRatio: 0.95,
      children: [
        _swatch(
          context,
          mode: ThemeMode.dark,
          label: context.l10n.darkTheme,
          preview: const _SolidPreview(
            bg: Color(0xFF08090D),
            bar: Color(0xFF191C24),
          ),
        ),
        _swatch(
          context,
          mode: ThemeMode.light,
          label: context.l10n.lightTheme,
          preview: const _SolidPreview(
            bg: Color(0xFFF3F4F7),
            bar: Colors.white,
          ),
        ),
        _swatch(
          context,
          mode: ThemeMode.system,
          label: context.l10n.systemTheme,
          preview: const _SystemPreview(),
        ),
      ],
    );
  }

  Widget _swatch(
    BuildContext context, {
    required ThemeMode mode,
    required String label,
    required Widget preview,
  }) {
    final active = selected == mode;
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => onSelected(mode),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: Radii.smR,
          border: Border.all(
            color: active ? Brand.accent : scheme.outlineVariant,
            width: active ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(child: preview),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SolidPreview extends StatelessWidget {
  const _SolidPreview({required this.bg, required this.bar});
  final Color bg;
  final Color bar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.all(6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 30,
          height: 8,
          decoration: BoxDecoration(
            color: bar,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _SystemPreview extends StatelessWidget {
  const _SystemPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08090D), Color(0xFF191C24)],
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        LucideIcons.sunMoon,
        size: 16,
        color: Color(0xFF5B6377),
      ),
    );
  }
}

/// Inline accent picker matching the mockup's `.dot-row`: a row of tappable
/// color circles (no value-row + bottom-sheet). Keeps the same
/// [accentPresets] list the old picker used.
class _AccentDotRow extends StatelessWidget {
  const _AccentDotRow({required this.selected, required this.onSelected});

  final Color? selected;
  final ValueChanged<Color?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          for (final (color, label) in accentPresets)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: Tooltip(
                message: label,
                child: Pressable(
                  onTap: () => onSelected(color),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color ?? Brand.seed,
                      border:
                          selected == color
                              ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2,
                              )
                              : null,
                    ),
                    alignment: Alignment.center,
                    child:
                        selected == color
                            ? const Icon(
                              LucideIcons.check,
                              size: 14,
                              color: Colors.white,
                            )
                            : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Square tile for a short binary/2-option setting — tap toggles it (or
/// cycles the 2-option value) directly, no separate row/picker needed.
class _QuickToggleTile extends StatelessWidget {
  const _QuickToggleTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.caption,
  });

  final IconData icon;
  final String title;
  final bool? value;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = value ?? false;
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color:
              active
                  ? Brand.accent.withValues(alpha: 0.14)
                  : scheme.surfaceContainerHigh,
          borderRadius: Radii.lgR,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Brand.accent),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      caption ?? (active ? 'On' : 'Off'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

/// Accent presets shared with [AppSettingsScreen]'s hub subtitle (single
/// source of truth for the color↔label mapping).
const accentPresets = <(Color?, String)>[
  (null, 'Default'),
  (Color(0xFF2196F3), 'Blue'),
  (Color(0xFF4CAF50), 'Green'),
  (Color(0xFFFF5722), 'Deep orange'),
  (Color(0xFF9C27B0), 'Purple'),
  (Color(0xFFFF9800), 'Orange'),
  (Color(0xFFE91E63), 'Pink'),
  (Color(0xFF009688), 'Teal'),
];

String accentLabel(Color? selected) =>
    accentPresets
        .firstWhere((p) => p.$1 == selected, orElse: () => accentPresets.first)
        .$2;

/// Theme mode label shared with [AppSettingsScreen]'s hub subtitle.
String themeModeLabel(BuildContext context, ThemeMode m) => switch (m) {
  ThemeMode.system => context.l10n.systemTheme,
  ThemeMode.light => context.l10n.lightTheme,
  ThemeMode.dark => context.l10n.darkTheme,
};
