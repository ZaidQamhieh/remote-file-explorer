import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import 'settings_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Per-device view overrides (Wave 0). Each overridable view setting defaults
/// to **"Use app default"** (inherit the global value set in App Settings) and
/// can be flipped to **"Override"** with a device-specific value. Toggling an
/// override on seeds it with the current effective value so nothing jumps;
/// toggling off clears it (the device falls back to the app default). "Reset to
/// app defaults" clears every override for this host at once.
class DeviceViewOverridesSection extends ConsumerWidget {
  const DeviceViewOverridesSection({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final overrides = settings.overridesFor(hostId);
    final resolved = settings.resolveView(hostId);
    final scheme = Theme.of(context).colorScheme;

    return SettingsSection(
      title: context.l10n.displayDeviceSection,
      icon: LucideIcons.slidersHorizontal,
      trailing: TextButton(
        onPressed:
            settings.hasOverride(hostId)
                ? () => notifier.resetDevice(hostId)
                : null,
        child: Text(context.l10n.resetToAppDefaults),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Text(
            context.l10n.displayFollowsDefaults,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        _OverrideRow(
          title: context.l10n.layoutLabel,
          isOverridden: overrides.gridView != null,
          appDefaultLabel:
              settings.app.gridView
                  ? context.l10n.gridLabel
                  : context.l10n.listLabel,
          onChanged:
              (on) => notifier.setDeviceGridView(
                hostId,
                on ? resolved.gridView : null,
              ),
          control: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(context.l10n.listLabel)),
              ButtonSegment(value: true, label: Text(context.l10n.gridLabel)),
            ],
            selected: {resolved.gridView},
            onSelectionChanged:
                (s) => notifier.setDeviceGridView(hostId, s.first),
          ),
        ),
        const Divider(height: Spacing.lg),
        _OverrideRow(
          title: context.l10n.densityLabel,
          isOverridden: overrides.density != null,
          appDefaultLabel: _densityLabel(context, settings.app.density),
          onChanged:
              (on) => notifier.setDeviceDensity(
                hostId,
                on ? resolved.density : null,
              ),
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
            selected: {resolved.density},
            onSelectionChanged:
                (s) => notifier.setDeviceDensity(hostId, s.first),
          ),
        ),
        const Divider(height: Spacing.lg),
        _OverrideRow(
          title: context.l10n.sortLabel,
          isOverridden: overrides.sort != null,
          appDefaultLabel: _sortLabel(context, settings.app.sort),
          onChanged:
              (on) => notifier.setDeviceSort(hostId, on ? resolved.sort : null),
          control: _SortControl(
            value: resolved.sort,
            onChanged: (v) => notifier.setDeviceSort(hostId, v),
          ),
        ),
      ],
    );
  }
}

/// One overridable setting: a switch that flips between "Use app default
/// (value)" and a per-device [control]. The control is only shown (and enabled)
/// while overriding.
class _OverrideRow extends StatelessWidget {
  const _OverrideRow({
    required this.title,
    required this.isOverridden,
    required this.appDefaultLabel,
    required this.onChanged,
    required this.control,
  });

  final String title;
  final bool isOverridden;
  final String appDefaultLabel;
  final ValueChanged<bool> onChanged;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(title),
          subtitle: Text(
            isOverridden
                ? context.l10n.overriddenForDevice
                : context.l10n.usingAppDefaultLabel(appDefaultLabel),
          ),
          value: isOverridden,
          onChanged: onChanged,
        ),
        if (isOverridden)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: control,
            ),
          ),
      ],
    );
  }
}

/// Compact sort picker: a field dropdown plus a direction toggle, used for a
/// device's sort override.
class _SortControl extends StatelessWidget {
  const _SortControl({required this.value, required this.onChanged});

  final SortOrder value;
  final ValueChanged<SortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<SortField>(
          value: value.field,
          onChanged:
              (f) => f == null ? null : onChanged(value.copyWith(field: f)),
          items: [
            for (final f in SortField.values)
              DropdownMenuItem(
                value: f,
                child: Text(_sortFieldLabel(context, f)),
              ),
          ],
        ),
        const SizedBox(width: Spacing.sm),
        IconButton(
          tooltip:
              value.ascending
                  ? context.l10n.ascendingTooltip
                  : context.l10n.descendingTooltip,
          icon: Icon(
            value.ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
          ),
          onPressed:
              () => onChanged(value.copyWith(ascending: !value.ascending)),
        ),
      ],
    );
  }
}

String _densityLabel(BuildContext context, EntryDensity d) =>
    d == EntryDensity.compact
        ? context.l10n.compactLabel
        : context.l10n.comfortableLabel;

String _sortLabel(BuildContext context, SortOrder s) =>
    '${_sortFieldLabel(context, s.field)} ${s.ascending ? '↑' : '↓'}';

String _sortFieldLabel(BuildContext context, SortField field) =>
    switch (field) {
      SortField.name => context.l10n.sortFieldName,
      SortField.size => context.l10n.sortFieldSize,
      SortField.date => context.l10n.sortFieldDate,
      SortField.type => context.l10n.sortFieldType,
    };
