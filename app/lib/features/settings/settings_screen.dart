import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/agent_settings.dart';
import '../../core/models/device.dart';
import '../../core/models/host.dart';
import '../../core/storage/visibility_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import 'update_tile.dart';

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
        _Section(
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
        _Section(
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
        _Section(
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
        const FileVisibilitySection(),
        const SizedBox(height: Spacing.md),
        _Section(
          title: 'Paired devices',
          icon: Icons.devices_outlined,
          children: [
            for (final d in _devices) _DeviceRow(device: d, screen: this),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _Section(
          title: 'Updates',
          icon: Icons.system_update_alt_outlined,
          padded: false,
          children: [
            UpdateTile(host: widget.host),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _Section(
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

/// A grouped settings section: a labelled header followed by a card containing
/// related rows. Keeps visual rhythm consistent across the screen.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
    this.padded = true,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  /// Whether the card content gets the standard padding. UpdateTile already
  /// manages its own internal padding, so the Updates section opts out.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.xs, 0, Spacing.xs, Spacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: Spacing.sm),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Card(
          elevation: Elevations.card,
          color: scheme.surfaceContainerLow,
          shape: const RoundedRectangleBorder(borderRadius: Radii.cardR),
          clipBehavior: Clip.antiAlias,
          child: padded
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md, vertical: Spacing.xs),
                  child: Column(children: children),
                )
              : Column(children: children),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// File visibility section
// ---------------------------------------------------------------------------

/// "File visibility" settings: hide-dotfiles toggle, one-tap presets that add
/// to the hidden-extensions/-names sets (`core/storage/visibility_prefs.dart`),
/// and a custom-extension input with deletable chips. Global — applies to
/// every host's explorer/search listings, unlike the rest of this
/// per-[Host] screen.
class FileVisibilitySection extends ConsumerWidget {
  const FileVisibilitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(visibilityPrefsProvider).valueOrNull ?? const VisibilityPrefs();
    final notifier = ref.read(visibilityPrefsProvider.notifier);
    final extensions = prefs.hiddenExtensions.toList()..sort();
    final scheme = Theme.of(context).colorScheme;

    return _Section(
      title: 'File visibility',
      icon: Icons.visibility_outlined,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hide dotfiles'),
          subtitle: const Text('Hide files and folders starting with "."'),
          value: prefs.hideDotfiles,
          onChanged: notifier.setHideDotfiles,
        ),
        const SizedBox(height: Spacing.sm),
        Text('Hide by type', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            for (final preset in visibilityPresets)
              FilterChip(
                label: Text(preset.label),
                selected: _presetApplied(preset, prefs),
                onSelected: (_) => notifier.applyPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Text('Hidden extensions', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.xs),
        if (extensions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Text(
              'None — add one below or use a preset above.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final ext in extensions)
                InputChip(
                  label: Text('.$ext'),
                  onDeleted: () => notifier.removeExtension(ext),
                ),
            ],
          ),
        const SizedBox(height: Spacing.xs),
        _AddExtensionField(onSubmit: notifier.addExtension),
      ],
    );
  }
}

/// `true` if every extension/name in [preset] is already in [prefs] — shown
/// as the preset chip's selected state. Tapping a chip always (re-)applies
/// the preset (additive, idempotent) regardless of this value.
bool _presetApplied(VisibilityPreset preset, VisibilityPrefs prefs) {
  final names = prefs.hiddenNames.map((n) => n.toLowerCase()).toSet();
  return preset.extensions.every(prefs.hiddenExtensions.contains) &&
      preset.names.every((n) => names.contains(n.toLowerCase()));
}

/// Text field for adding a custom hidden extension (e.g. "tmp"), submitted
/// via the keyboard action or the trailing add button. [onSubmit] is
/// [VisibilityPrefsNotifier.addExtension], which normalizes (strips dots,
/// lowercases) and persists.
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
    } else if (d.revoked) {
      status = 'Revoked';
      statusColor = scheme.error;
    } else {
      status = 'Active · last seen ${d.lastSeen.toLocal()}';
      statusColor = Brand.online;
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
