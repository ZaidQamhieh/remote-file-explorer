import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/view_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import 'file_visibility_screen.dart';
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
            title: 'Theme',
            children: [
              SettingsTile.value(
                icon: LucideIcons.palette,
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
              SettingsTile.toggle(
                icon: LucideIcons.image,
                title: context.l10n.useWallpaperColors,
                subtitle: context.l10n.wallpaperSubtitle,
                value: app.dynamicColor,
                onChanged: notifier.setDynamicColor,
              ),
              SettingsTile.toggle(
                icon: LucideIcons.moon,
                title: 'AMOLED Dark',
                subtitle: 'Pure black background in dark mode',
                value: app.amoledDark,
                onChanged: notifier.setAmoledDark,
              ),
              SettingsTile.value(
                icon: LucideIcons.swatchBook,
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
                icon: LucideIcons.globe,
                title: context.l10n.languageLabel,
                value: _localeLabel(context, app.locale),
                onTap: () async {
                  // Same null-ambiguity guard as accent color: key by index.
                  const locales = <Locale?>[null, Locale('en'), Locale('ar')];
                  final currentIndex = locales.indexOf(app.locale);
                  final picked = await showSettingsPicker<int>(
                    context,
                    title: context.l10n.languageLabel,
                    selected: currentIndex < 0 ? 0 : currentIndex,
                    options: [
                      SettingsOption(0, context.l10n.systemTheme),
                      const SettingsOption(1, 'English'),
                      const SettingsOption(2, 'العربية'),
                    ],
                  );
                  if (picked != null) notifier.setLocale(locales[picked]);
                },
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.displaySection,
            children: [
              SettingsTile.value(
                icon: LucideIcons.layoutGrid,
                title: context.l10n.layoutLabel,
                value:
                    app.gridView
                        ? context.l10n.gridLabel
                        : context.l10n.listLabel,
                onTap: () async {
                  final picked = await showSettingsPicker<bool>(
                    context,
                    title: context.l10n.layoutLabel,
                    selected: app.gridView,
                    options: [
                      SettingsOption(
                        false,
                        context.l10n.listLabel,
                        icon: LucideIcons.list,
                      ),
                      SettingsOption(
                        true,
                        context.l10n.gridLabel,
                        icon: LucideIcons.layoutGrid,
                      ),
                    ],
                  );
                  if (picked != null) notifier.setAppGridView(picked);
                },
              ),
              SettingsTile.value(
                icon: LucideIcons.rows3,
                title: context.l10n.densityLabel,
                value:
                    app.density == EntryDensity.compact
                        ? context.l10n.compactLabel
                        : context.l10n.comfortableLabel,
                onTap: () async {
                  final picked = await showSettingsPicker<EntryDensity>(
                    context,
                    title: context.l10n.densityLabel,
                    selected: app.density,
                    options: [
                      SettingsOption(
                        EntryDensity.comfortable,
                        context.l10n.comfortableLabel,
                      ),
                      SettingsOption(
                        EntryDensity.compact,
                        context.l10n.compactLabel,
                      ),
                    ],
                  );
                  if (picked != null) notifier.setAppDensity(picked);
                },
              ),
              SettingsTile.value(
                icon: LucideIcons.arrowUpDown,
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
              SettingsTile.toggle(
                icon: LucideIcons.wifi,
                title: 'Preload previews on cellular',
                subtitle:
                    'Warm neighbouring images while swiping the preview, even '
                    'off Wi-Fi',
                value: app.preloadPreviewOnCellular,
                onChanged: notifier.setPreloadPreviewOnCellular,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'File visibility',
            children: [
              SettingsTile.nav(
                icon: LucideIcons.eyeOff,
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

String _localeLabel(BuildContext context, Locale? locale) => switch (locale) {
  null => context.l10n.systemTheme,
  Locale(languageCode: 'en') => 'English',
  Locale(languageCode: 'ar') => 'العربية',
  _ => locale.languageCode,
};
