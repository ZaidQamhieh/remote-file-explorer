import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/agent_settings.dart';
import '../../core/models/device.dart';
import '../../core/models/host.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/visibility_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import 'update_tile.dart';
import 'widgets/device_view_overrides_section.dart';
import 'widgets/settings_section.dart';

/// Per-host settings: read-only mode, folder jail, paired devices, agent name.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.host});
  final Host host;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AgentClient? _client;
  AgentSettings? _settings;
  List<Device> _devices = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Close any previously-built client before replacing it (e.g. on retry
      // after an error).
      _client?.close();
      final client = await buildClientForHost(ref.read, widget.host.id);
      final settings = await client.getSettings();
      final devices = await client.listDevices();
      setState(() {
        _client = client;
        _settings = settings;
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _patch(
      {bool? readOnly, List<String>? roots, String? name, String? successMsg}) async {
    final client = _client;
    if (client == null) return;
    final prev = _settings;
    // Optimistic update.
    setState(() {
      _settings = _settings?.copyWith(
        readOnly: readOnly,
        roots: roots,
        agentName: name,
      );
    });
    try {
      final updated = await client.updateSettings(
        readOnly: readOnly,
        roots: roots,
        agentName: name,
      );
      setState(() => _settings = updated);
      if (mounted && successMsg != null) showSuccess(context, successMsg);
    } catch (e) {
      setState(() => _settings = prev); // rollback
      if (mounted) showError(context, 'Update failed: $e');
    }
  }

  Future<void> _revoke(Device d) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.revokeDevice(d.id);
      await _load();
      if (mounted) showSuccess(context, 'Revoked "${d.label}"');
    } catch (e) {
      if (mounted) showError(context, 'Revoke failed: $e');
    }
  }

  Future<void> _removeDevice(Device d) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.deleteDevice(d.id);
      await _load();
      if (mounted) showSuccess(context, 'Removed "${d.label}"');
    } catch (e) {
      if (mounted) showError(context, 'Remove failed: $e');
    }
  }

  Future<void> _addRoot() async {
    final ctrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add allowed folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/home/me/Documents'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      final roots = [...?_settings?.roots, path];
      await _patch(roots: roots, successMsg: 'Added $path');
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _settings?.agentName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename agent'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _patch(name: name, successMsg: 'Renamed to $name');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = _settings!;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.xl),
      children: [
        _SecurityWarningCard(scheme: scheme),
        const SizedBox(height: Spacing.lg),
        SettingsSection(
          title: 'Agent',
          icon: Icons.dns_outlined,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Agent name'),
              subtitle: Text(s.agentName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editName,
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: 'Access',
          icon: Icons.lock_outline,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Read-only mode'),
              subtitle: Text(s.readOnly
                  ? 'Writes are rejected'
                  : 'This phone can modify files'),
              value: s.readOnly,
              onChanged: (v) => _patch(readOnly: v),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: 'Allowed folders',
          icon: Icons.folder_outlined,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add folder',
            onPressed: _addRoot,
          ),
          children: [
            if (s.roots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text(
                  'All folders allowed',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              ...s.roots.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(r),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove folder',
                      onPressed: () => _patch(
                        roots: s.roots.where((x) => x != r).toList(),
                        successMsg: 'Removed $r',
                      ),
                    ),
                  )),
          ],
        ),
        const SizedBox(height: Spacing.md),
        DeviceViewOverridesSection(hostId: widget.host.id),
        const SizedBox(height: Spacing.md),
        const FileVisibilitySection(),
        const SizedBox(height: Spacing.md),
        DeviceVisibilityOverrideSection(hostId: widget.host.id),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: 'Paired devices',
          icon: Icons.devices_outlined,
          children: [
            for (final d in _devices) _DeviceRow(device: d, screen: this),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: 'Updates',
          icon: Icons.system_update_alt_outlined,
          padded: false,
          children: [
            UpdateTile(host: widget.host),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: 'About',
          icon: Icons.info_outline,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Host'),
              subtitle: Text(widget.host.label.isNotEmpty
                  ? widget.host.label
                  : widget.host.address),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cleanly-styled warning card explaining the trust model of a paired phone.
class _SecurityWarningCard extends StatelessWidget {
  const _SecurityWarningCard({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardR),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'This phone has full control of the host. Anyone with access '
                'to it can change these settings and reach allowed folders.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File visibility section
// ---------------------------------------------------------------------------

/// The file-visibility editor body: hide-dotfiles toggle, one-tap presets that
/// add to the hidden-extensions/-names sets
/// (`core/storage/visibility_prefs.dart`), and a custom-extension input with
/// deletable chips. Pure presentation over a [VisibilityPrefs] value plus
/// mutation callbacks scoped to a target ([SettingsNotifier] with `hostId`
/// null for the app default, or a host id for a per-device override) — reused
/// by both the App Settings surface and the per-device override section.
class VisibilityEditor extends StatelessWidget {
  const VisibilityEditor({super.key, required this.prefs, required this.notifier, this.hostId});

  final VisibilityPrefs prefs;
  final SettingsNotifier notifier;

  /// `null` = edit the app default; non-null = edit this host's override.
  final String? hostId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Extensions the user typed by hand are everything in the hidden set that
    // no preset category already accounts for — they get their own section at
    // the bottom.
    final presetExtensions = {
      for (final preset in visibilityPresets) ...preset.extensions,
    };
    final custom = prefs.hiddenExtensions
        .where((e) => !presetExtensions.contains(e))
        .toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hide dotfiles'),
          subtitle: const Text('Hide files and folders starting with "."'),
          value: prefs.hideDotfiles,
          onChanged: (v) => notifier.setHideDotfiles(v, hostId: hostId),
        ),
        const Divider(height: Spacing.lg),
        // One section per category; tapping a chip toggles that single file
        // type, so users pick exactly what to hide instead of all-or-nothing.
        for (final preset in visibilityPresets)
          _PresetGroup(preset: preset, prefs: prefs, notifier: notifier, hostId: hostId),
        const Divider(height: Spacing.lg),
        Text('Custom', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.xs),
        if (custom.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Text(
              'None — add an extension below.',
              style: TextStyle(color: scheme.onSurfaceVariant),
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
                  onDeleted: () => notifier.removeExtension(ext, hostId: hostId),
                ),
            ],
          ),
        const SizedBox(height: Spacing.xs),
        _AddExtensionField(
            onSubmit: (e) => notifier.addExtension(e, hostId: hostId)),
      ],
    );
  }
}

/// "File visibility" App Settings card: edits the **app-default**
/// [VisibilityPrefs] (`hostId: null`) — the global default every host inherits
/// unless it carries its own override (set per-device in
/// [DeviceVisibilityOverrideSection]).
class FileVisibilitySection extends ConsumerWidget {
  const FileVisibilitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSection(
      title: 'File visibility',
      icon: Icons.visibility_outlined,
      children: [
        VisibilityEditor(prefs: settings.app.visibility, notifier: notifier),
      ],
    );
  }
}

/// Per-device file-visibility override (Wave 0). Defaults to **"Use app
/// default"** (inherit the global visibility set in App Settings) and can be
/// flipped to **"Override"** with a host-specific [VisibilityPrefs]. Toggling
/// the override on seeds it from the host's current effective visibility so
/// nothing jumps; toggling off clears it. Matches the
/// [DeviceViewOverridesSection] interaction pattern.
class DeviceVisibilityOverrideSection extends ConsumerWidget {
  const DeviceVisibilityOverrideSection({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const SettingsState();
    final notifier = ref.read(settingsProvider.notifier);
    final isOverridden = settings.overridesFor(hostId).visibility != null;
    final resolved = settings.resolveVisibility(hostId);
    final scheme = Theme.of(context).colorScheme;

    return SettingsSection(
      title: 'File visibility (this device)',
      icon: Icons.visibility_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Text(
            'Follows your app-default file visibility unless you override it '
            'here.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Override for this device'),
          subtitle: Text(isOverridden
              ? 'Using device-specific visibility'
              : 'Using app default'),
          value: isOverridden,
          onChanged: (on) =>
              notifier.setDeviceVisibilityOverride(hostId, on),
        ),
        if (isOverridden) ...[
          const Divider(height: Spacing.lg),
          VisibilityEditor(prefs: resolved, notifier: notifier, hostId: hostId),
        ],
      ],
    );
  }
}

/// One category section in [VisibilityEditor]: a header (the preset label)
/// above a wrap of per-file-type toggle chips. Each chip hides a single
/// extension (`.ext`) or exact name (e.g. `Thumbs.db`) independently, so the
/// user picks precisely which types in the category to hide. Mutations target
/// the app default ([hostId] null) or a host override.
class _PresetGroup extends StatelessWidget {
  const _PresetGroup({
    required this.preset,
    required this.prefs,
    required this.notifier,
    this.hostId,
  });

  final VisibilityPreset preset;
  final VisibilityPrefs prefs;
  final SettingsNotifier notifier;
  final String? hostId;

  @override
  Widget build(BuildContext context) {
    final extensions = preset.extensions.toList()..sort();
    final names = preset.names.toList()..sort();
    final lowerHiddenNames =
        prefs.hiddenNames.map((n) => n.toLowerCase()).toSet();

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(preset.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final ext in extensions)
                FilterChip(
                  label: Text('.$ext'),
                  selected: prefs.hiddenExtensions.contains(ext),
                  onSelected: (selected) => selected
                      ? notifier.addExtension(ext, hostId: hostId)
                      : notifier.removeExtension(ext, hostId: hostId),
                ),
              for (final name in names)
                FilterChip(
                  label: Text(name),
                  selected: lowerHiddenNames.contains(name.toLowerCase()),
                  onSelected: (selected) => selected
                      ? notifier.addName(name, hostId: hostId)
                      : notifier.removeName(name, hostId: hostId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Text field for adding a custom hidden extension (e.g. "tmp"), submitted
/// via the keyboard action or the trailing add button. [onSubmit] normalizes
/// (strips dots, lowercases) and persists via the settings controller.
class _AddExtensionField extends StatefulWidget {
  const _AddExtensionField({required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<_AddExtensionField> createState() => _AddExtensionFieldState();
}

class _AddExtensionFieldState extends State<_AddExtensionField> {
  final _controller = TextEditingController();

  void _submit() {
    final value = _controller.text;
    if (value.trim().isEmpty) return;
    widget.onSubmit(value);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        isDense: true,
        prefixText: '.',
        hintText: 'Add extension (e.g. tmp)',
        suffixIcon: IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add extension',
          onPressed: _submit,
        ),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}

/// A single paired-device row showing its identity, status, and the relevant
/// trailing action (revoke for active devices, remove for revoked ones).
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.screen});

  final Device device;
  final _SettingsScreenState screen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = device;

    String status;
    Color statusColor;
    if (d.current) {
      status = 'This device';
      statusColor = Brand.online;
    } else {
      final parts = <String>[
        d.revoked ? 'Revoked' : 'Active',
        if (d.lastAddress.isNotEmpty) d.lastAddress,
        if (d.lastVersion.isNotEmpty) 'v${d.lastVersion}',
        formatRelative(d.lastSeen.toLocal()),
      ];
      status = parts.join(' · ');
      statusColor = d.revoked ? scheme.error : Brand.online;
    }

    Widget? trailing;
    if (!d.current) {
      if (d.revoked) {
        trailing = IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove device',
          color: scheme.error,
          onPressed: () => screen._removeDevice(d),
        );
      } else {
        trailing = TextButton(
          onPressed: () => screen._revoke(d),
          child: const Text('Revoke'),
        );
      }
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        d.revoked ? Icons.phonelink_erase : Icons.smartphone,
        color: d.revoked ? scheme.error : scheme.onSurfaceVariant,
      ),
      title: Text(d.label),
      subtitle: Text(
        status,
        style: TextStyle(color: statusColor),
      ),
      trailing: trailing,
    );
  }
}
