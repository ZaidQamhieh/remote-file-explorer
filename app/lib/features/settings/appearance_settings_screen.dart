import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
import 'file_visibility_screen.dart';
import 'widgets/settings_hero.dart';
import 'widgets/settings_picker.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
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

    String themeLabel(ThemeMode m) => switch (m) {
      ThemeMode.system => context.l10n.systemTheme,
      ThemeMode.light => context.l10n.lightTheme,
      ThemeMode.dark => context.l10n.darkTheme,
    };

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
            icon: LucideIcons.palette,
            title: 'Appearance',
            subtitle: "Theme, layout, sort & how files look",
            tint: Brand.accent,
          ),
          const SizedBox(height: Spacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Spacing.sm,
            crossAxisSpacing: Spacing.sm,
            childAspectRatio: 1.7,
            children: [
              _QuickToggleTile(
                icon: LucideIcons.image,
                title: context.l10n.useWallpaperColors,
                value: app.dynamicColor,
                onTap: () => notifier.setDynamicColor(!app.dynamicColor),
              ),
              _QuickToggleTile(
                icon: LucideIcons.moon,
                title: 'AMOLED Dark',
                value: app.amoledDark,
                onTap: () => notifier.setAmoledDark(!app.amoledDark),
              ),
              _QuickToggleTile(
                icon: app.gridView ? LucideIcons.layoutGrid : LucideIcons.list,
                title: context.l10n.layoutLabel,
                caption:
                    app.gridView
                        ? context.l10n.gridLabel
                        : context.l10n.listLabel,
                onTap: () => notifier.setAppGridView(!app.gridView),
              ),
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
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Theme',
            children: [
              SettingsTile.value(
                icon: LucideIcons.palette,
                badgeColor: Brand.accent,
                title: context.l10n.themeLabel,
                value: themeLabel(app.themeMode),
                onTap: () async {
                  final picked = await showSettingsPicker<ThemeMode>(
                    context,
                    title: context.l10n.themeLabel,
                    selected: app.themeMode,
                    options: [
                      SettingsOption(
                        ThemeMode.system,
                        context.l10n.systemTheme,
                        icon: LucideIcons.sunMoon,
                      ),
                      SettingsOption(
                        ThemeMode.light,
                        context.l10n.lightTheme,
                        icon: LucideIcons.sun,
                      ),
                      SettingsOption(
                        ThemeMode.dark,
                        context.l10n.darkTheme,
                        icon: LucideIcons.moon,
                      ),
                    ],
                  );
                  if (picked != null) notifier.setThemeMode(picked);
                },
              ),
              SettingsTile.value(
                icon: LucideIcons.swatchBook,
                badgeColor: Brand.accent,
                title: 'Accent Color',
                value: _accentLabel(app.seedColor),
                leadingDot: app.seedColor ?? Brand.seed,
                onTap: () async {
                  // Picker is keyed by preset index, not Color?, so picking
                  // "Default" (a null Color) can't be confused with the
                  // sheet being dismissed (both would otherwise read null).
                  final currentIndex = _accentPresets.indexWhere(
                    (p) => p.$1 == app.seedColor,
                  );
                  final picked = await showSettingsPicker<int>(
                    context,
                    title: 'Accent Color',
                    selected: currentIndex < 0 ? 0 : currentIndex,
                    options: [
                      for (var i = 0; i < _accentPresets.length; i++)
                        SettingsOption(
                          i,
                          _accentPresets[i].$2,
                          color: _accentPresets[i].$1 ?? Brand.seed,
                        ),
                    ],
                  );
                  if (picked != null) {
                    notifier.setSeedColor(_accentPresets[picked].$1);
                  }
                },
              ),
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
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'File visibility',
            children: [
              SettingsTile.nav(
                icon: LucideIcons.eyeOff,
                badgeColor: Brand.accent,
                title: 'File visibility',
                subtitle: 'Hidden file types & dotfiles',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FileVisibilityScreen(),
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
    return Material(
      color:
          active
              ? Brand.accent.withValues(alpha: 0.14)
              : scheme.surfaceContainerHigh,
      borderRadius: Radii.lgR,
      child: InkWell(
        borderRadius: Radii.lgR,
        onTap: onTap,
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
                      maxLines: 1,
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

const _accentPresets = <(Color?, String)>[
  (null, 'Default'),
  (Color(0xFF2196F3), 'Blue'),
  (Color(0xFF4CAF50), 'Green'),
  (Color(0xFFFF5722), 'Deep orange'),
  (Color(0xFF9C27B0), 'Purple'),
  (Color(0xFFFF9800), 'Orange'),
  (Color(0xFFE91E63), 'Pink'),
  (Color(0xFF009688), 'Teal'),
];

String _accentLabel(Color? selected) =>
    _accentPresets
        .firstWhere((p) => p.$1 == selected, orElse: () => _accentPresets.first)
        .$2;
