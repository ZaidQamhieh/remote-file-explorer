import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import 'settings_section.dart';

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
      title: 'Display (this device)',
      icon: Icons.tune_rounded,
      trailing: TextButton(
        onPressed: settings.hasOverride(hostId)
            ? () => notifier.resetDevice(hostId)
            : null,
        child: const Text('Reset to app defaults'),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Text(
            'These follow your app defaults unless you override them here.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        _OverrideRow(
          title: 'Layout',
          isOverridden: overrides.gridView != null,
          appDefaultLabel: settings.app.gridView ? 'Grid' : 'List',
          onChanged: (on) => notifier.setDeviceGridView(
              hostId, on ? resolved.gridView : null),
          control: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('List')),
              ButtonSegment(value: true, label: Text('Grid')),
            ],
            selected: {resolved.gridView},
            onSelectionChanged: (s) =>
                notifier.setDeviceGridView(hostId, s.first),
          ),
        ),
        const Divider(height: Spacing.lg),
        _OverrideRow(
          title: 'Density',
          isOverridden: overrides.density != null,
          appDefaultLabel: _densityLabel(settings.app.density),
          onChanged: (on) => notifier.setDeviceDensity(
              hostId, on ? resolved.density : null),
          control: SegmentedButton<EntryDensity>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: EntryDensity.comfortable, label: Text('Comfortable')),
              ButtonSegment(
                  value: EntryDensity.compact, label: Text('Compact')),
            ],
            selected: {resolved.density},
            onSelectionChanged: (s) =>
                notifier.setDeviceDensity(hostId, s.first),
          ),
        ),
        const Divider(height: Spacing.lg),
        _OverrideRow(
          title: 'Sort',
          isOverridden: overrides.sort != null,
          appDefaultLabel: _sortLabel(settings.app.sort),
          onChanged: (on) =>
              notifier.setDeviceSort(hostId, on ? resolved.sort : null),
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
          subtitle: Text(isOverridden
              ? 'Overridden for this device'
              : 'Using app default ($appDefaultLabel)'),
          value: isOverridden,
          onChanged: onChanged,
        ),
        if (isOverridden)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Align(alignment: Alignment.centerLeft, child: control),
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
          onChanged: (f) =>
              f == null ? null : onChanged(value.copyWith(field: f)),
          items: [
            for (final f in SortField.values)
              DropdownMenuItem(value: f, child: Text(_sortFieldLabel(f))),
          ],
        ),
        const SizedBox(width: Spacing.sm),
        IconButton(
          tooltip: value.ascending ? 'Ascending' : 'Descending',
          icon: Icon(value.ascending
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded),
          onPressed: () =>
              onChanged(value.copyWith(ascending: !value.ascending)),
        ),
      ],
    );
  }
}

String _densityLabel(EntryDensity d) =>
    d == EntryDensity.compact ? 'Compact' : 'Comfortable';

String _sortLabel(SortOrder s) =>
    '${_sortFieldLabel(s.field)} ${s.ascending ? '↑' : '↓'}';

String _sortFieldLabel(SortField field) => switch (field) {
      SortField.name => 'Name',
      SortField.size => 'Size',
      SortField.date => 'Date modified',
      SortField.type => 'Type',
    };
