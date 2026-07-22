import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/visibility_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/pressable.dart';
import 'settings_screen.dart' show AddExtensionField;
import 'widgets/settings_hero.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// Organized File Visibility screen (app-default target only, `hostId: null`):
/// a dotfiles toggle, one collapsible category per [VisibilityPreset]
/// (collapsed by default, with a per-category count and a master on/off
/// switch), and the existing custom-extension add/remove flow — all driving
/// the same [SettingsNotifier] calls the old inline [VisibilityEditor] used.
/// Replaces the 50+-chip inline scroll from Appearance; the host-override
/// screen keeps using [VisibilityEditor] as-is.
class FileVisibilityScreen extends ConsumerWidget {
  const FileVisibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final prefs = settings.app.visibility;

    final presetExtensions = {
      for (final preset in visibilityPresets) ...preset.extensions,
    };
    final custom =
        prefs.hiddenExtensions
            .where((e) => !presetExtensions.contains(e))
            .toList()
          ..sort();

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
            icon: LucideIcons.eyeOff,
            title: 'File visibility',
            subtitle: 'Hidden types & dotfiles',
            tint: Brand.accent,
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'General',
            children: [
              SettingsTile.toggle(
                icon: LucideIcons.eyeOff,
                badgeColor: Brand.accent,
                title: context.l10n.hideDotfiles,
                subtitle: context.l10n.hideDotfilesSubtitle,
                value: prefs.hideDotfiles,
                onChanged: notifier.setHideDotfiles,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: 'Categories',
            padded: false,
            children: [
              for (final preset in visibilityPresets)
                _CategoryTile(preset: preset, prefs: prefs, notifier: notifier),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SettingsSection(
            title: context.l10n.customLabel,
            // Single child, not 3: SettingsSection inserts a Divider between
            // every pair of children (meant for distinct rows), which would
            // otherwise cut a divider through this composite block (empty-
            // state text/chip-wrap, spacer, input field) that isn't a list
            // of rows at all.
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (custom.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                      child: Text(
                        context.l10n.noCustomExtensions,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final ext in custom)
                          InputChip(
                            label: Text('.$ext'),
                            onDeleted: () => notifier.removeExtension(ext),
                          ),
                      ],
                    ),
                  const SizedBox(height: Spacing.xs),
                  AddExtensionField(onSubmit: notifier.addExtension),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One collapsible category: header shows the label, hidden count, and a
/// master [Switch] (on = every extension/name in the preset is hidden);
/// expanding it reveals the same per-file-type [FilterChip] grid the old
/// inline editor used, for picking individual types within the category.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.preset,
    required this.prefs,
    required this.notifier,
  });

  final VisibilityPreset preset;
  final VisibilityPrefs prefs;
  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final extensions = preset.extensions.toList()..sort();
    final names = preset.names.toList()..sort();
    final lowerHiddenNames =
        prefs.hiddenNames.map((n) => n.toLowerCase()).toSet();
    final hiddenCount =
        extensions.where(prefs.hiddenExtensions.contains).length +
        names.where((n) => lowerHiddenNames.contains(n.toLowerCase())).length;
    final allHidden =
        extensions.every(prefs.hiddenExtensions.contains) &&
        names.every((n) => lowerHiddenNames.contains(n.toLowerCase()));

    return ExpansionTile(
      title: Text(
        '${preset.label} ($hiddenCount)',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pressable(
            key: ValueKey('visibility-category-switch-${preset.label}'),
            onTap:
                () =>
                    allHidden
                        ? notifier.removePreset(preset)
                        : notifier.applyPreset(preset),
            child: _MockupSwitch(value: allHidden),
          ),
          const SizedBox(width: Spacing.xs),
          const Icon(LucideIcons.chevronDown),
        ],
      ),
      childrenPadding: const EdgeInsets.only(bottom: Spacing.md),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final ext in extensions)
                FilterChip(
                  label: Text('.$ext'),
                  selected: prefs.hiddenExtensions.contains(ext),
                  onSelected:
                      (selected) =>
                          selected
                              ? notifier.addExtension(ext)
                              : notifier.removeExtension(ext),
                ),
              for (final name in names)
                FilterChip(
                  label: Text(name),
                  selected: lowerHiddenNames.contains(name.toLowerCase()),
                  onSelected:
                      (selected) =>
                          selected
                              ? notifier.addName(name)
                              : notifier.removeName(name),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The mockup's `.switch`: 42x25 pill track, 19x19 thumb — replaces a raw
/// Material [Switch]; the tap is wired by the enclosing [Pressable].
class _MockupSwitch extends StatelessWidget {
  const _MockupSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 25,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
        border: Border.all(
          color: value ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
