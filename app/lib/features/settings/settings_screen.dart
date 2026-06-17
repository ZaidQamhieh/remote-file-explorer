import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/agent_settings.dart';
import '../../core/models/bandwidth_settings.dart';
import '../../core/models/device.dart';
import '../../core/models/drive.dart';
import '../../core/models/host.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/host_store.dart';
import '../../core/storage/visibility_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
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
  BandwidthSettings _bandwidth = const BandwidthSettings();
  List<Device> _devices = const [];
  List<Drive> _drives = const [];
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
      final drives = await client.drives();
      BandwidthSettings bw = const BandwidthSettings();
      try {
        bw = await client.getBandwidth();
      } catch (_) {
        // Agent may not support bandwidth endpoint yet — use defaults.
      }
      setState(() {
        _client = client;
        _settings = settings;
        _bandwidth = bw;
        _devices = devices;
        _drives = drives;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _patch({
    bool? readOnly,
    List<String>? roots,
    String? name,
    String? successMsg,
  }) async {
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
      if (mounted) showError(context, context.l10n.updateFailed('$e'));
    }
  }

  /// Un-pairs THIS phone from this host.
  ///
  /// A phone may now only manage itself: this calls `DELETE
  /// /v1/devices/{id}` on the caller's own device id with `?purge=true`
  /// (via [AgentClient.deleteDevice]), which permanently removes this
  /// device's row and immediately invalidates its bearer token. Because the
  /// session is dead the instant that call succeeds, we don't make any
  /// further authenticated requests — instead we clear this host's stored
  /// credentials locally (same cleanup as "Forget this computer") and
  /// navigate back to the hosts list.
  Future<void> _disconnectThisDevice(Device self) async {
    final client = _client;
    if (client == null) return;

    final pcName =
        _settings?.agentName.isNotEmpty == true
            ? _settings!.agentName
            : (widget.host.label.isNotEmpty
                ? widget.host.label
                : widget.host.address);

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.disconnectDeviceTitle),
            content: Text(ctx.l10n.disconnectDeviceMessage(pcName)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.disconnectButton),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      await client.deleteDevice(self.id);
    } catch (e) {
      if (mounted) showError(context, context.l10n.disconnectFailed('$e'));
      return;
    }

    // The token is now invalid — don't make any further authenticated
    // calls. Clear local credentials/host entry and head back to the hosts
    // list, mirroring HostCard's "Forget this computer" cleanup.
    final store = await ref.read(hostStoreProvider.future);
    await store.removeHost(widget.host.id);
    if (!mounted) return;
    ref.invalidate(hostStoreProvider);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _addRoot() async {
    final ctrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.addAllowedFolder),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(hintText: ctx.l10n.allowedFolderHint),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(ctx.l10n.addButton),
              ),
            ],
          ),
    );
    if (path != null && path.isNotEmpty) {
      final roots = [...?_settings?.roots, path];
      await _patch(roots: roots, successMsg: context.l10n.addedFolder(path));
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _settings?.agentName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.renameAgentTitle),
            content: TextField(controller: ctrl, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(ctx.l10n.saveButton),
              ),
            ],
          ),
    );
    if (name != null && name.isNotEmpty) {
      await _patch(name: name, successMsg: context.l10n.renamedTo(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(context.l10n.errorLabel(_error!)))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = _settings!;
    final scheme = Theme.of(context).colorScheme;
    final drivesWithCapacity =
        _drives.where((d) => (d.totalBytes ?? 0) > 0).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.xl,
      ),
      children: [
        _SecurityWarningCard(scheme: scheme),
        const SizedBox(height: Spacing.lg),
        SettingsSection(
          title: context.l10n.agentSection,
          icon: Icons.dns_outlined,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.agentNameLabel),
              subtitle: Text(s.agentName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editName,
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.accessSection,
          icon: Icons.lock_outline,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.readOnlyMode),
              subtitle: Text(
                s.readOnly
                    ? context.l10n.writesRejected
                    : context.l10n.phoneCanModify,
              ),
              value: s.readOnly,
              onChanged: (v) => _patch(readOnly: v),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _BandwidthSection(
          bandwidth: _bandwidth,
          onChanged: (bw) async {
            final client = _client;
            if (client == null) return;
            final prev = _bandwidth;
            setState(() => _bandwidth = bw);
            try {
              final updated = await client.setBandwidth(
                maxUploadBytesPerSec: bw.maxUploadBytesPerSec,
                maxDownloadBytesPerSec: bw.maxDownloadBytesPerSec,
              );
              setState(() => _bandwidth = updated);
            } catch (e) {
              setState(() => _bandwidth = prev);
              if (mounted) showError(context, context.l10n.updateFailed('$e'));
            }
          },
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.allowedFoldersSection,
          icon: Icons.folder_outlined,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.l10n.addFolderTooltip,
            onPressed: _addRoot,
          ),
          children: [
            if (s.roots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text(
                  context.l10n.allFoldersAllowed,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              ...s.roots.map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(r),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: context.l10n.removeFolderTooltip,
                    onPressed:
                        () => _patch(
                          roots: s.roots.where((x) => x != r).toList(),
                          successMsg: context.l10n.removedFolder(r),
                        ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        DeviceVisibilityOverrideSection(hostId: widget.host.id),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.pairedDevicesSection,
          icon: Icons.devices_outlined,
          children: [
            for (final d in _devices) _DeviceRow(device: d, screen: this),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.aboutSection,
          icon: Icons.info_outline,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.pcNameLabel),
              subtitle: Text(
                s.agentName.isNotEmpty
                    ? s.agentName
                    : (widget.host.label.isNotEmpty
                        ? widget.host.label
                        : widget.host.address),
              ),
            ),
            if (drivesWithCapacity.isNotEmpty) ...[
              const Divider(height: Spacing.lg),
              for (final drive in drivesWithCapacity) _DriveRow(drive: drive),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bandwidth controls
// ---------------------------------------------------------------------------

/// Preset bandwidth options in bytes/sec. 0 = unlimited.
const _bandwidthPresets = <int>[
  0, // Unlimited
  1024 * 1024, // 1 MB/s
  5 * 1024 * 1024, // 5 MB/s
  10 * 1024 * 1024, // 10 MB/s
  50 * 1024 * 1024, // 50 MB/s
];

class _BandwidthSection extends StatelessWidget {
  const _BandwidthSection({
    required this.bandwidth,
    required this.onChanged,
  });

  final BandwidthSettings bandwidth;
  final ValueChanged<BandwidthSettings> onChanged;

  String _label(BuildContext context, int bytesPerSec) {
    if (bytesPerSec == 0) return context.l10n.bandwidthUnlimited;
    return '${formatSize(bytesPerSec)}/s';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.l10n.bandwidthSection,
      icon: Icons.speed_outlined,
      children: [
        _BandwidthDropdown(
          label: context.l10n.bandwidthUploadLimit,
          value: bandwidth.maxUploadBytesPerSec,
          onChanged: (v) => onChanged(
            bandwidth.copyWith(maxUploadBytesPerSec: v),
          ),
          labelBuilder: (v) => _label(context, v),
        ),
        _BandwidthDropdown(
          label: context.l10n.bandwidthDownloadLimit,
          value: bandwidth.maxDownloadBytesPerSec,
          onChanged: (v) => onChanged(
            bandwidth.copyWith(maxDownloadBytesPerSec: v),
          ),
          labelBuilder: (v) => _label(context, v),
        ),
      ],
    );
  }
}

class _BandwidthDropdown extends StatelessWidget {
  const _BandwidthDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.labelBuilder,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String Function(int) labelBuilder;

  @override
  Widget build(BuildContext context) {
    // If current value isn't in presets, include it so the dropdown works.
    final items = _bandwidthPresets.contains(value)
        ? _bandwidthPresets
        : [value, ..._bandwidthPresets];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final v in items)
            DropdownMenuItem(value: v, child: Text(labelBuilder(v))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
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
                context.l10n.securityWarning,
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
  const VisibilityEditor({
    super.key,
    required this.prefs,
    required this.notifier,
    this.hostId,
  });

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
    final custom =
        prefs.hiddenExtensions
            .where((e) => !presetExtensions.contains(e))
            .toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.hideDotfiles),
          subtitle: Text(context.l10n.hideDotfilesSubtitle),
          value: prefs.hideDotfiles,
          onChanged: (v) => notifier.setHideDotfiles(v, hostId: hostId),
        ),
        const Divider(height: Spacing.lg),
        // One section per category; tapping a chip toggles that single file
        // type, so users pick exactly what to hide instead of all-or-nothing.
        for (final preset in visibilityPresets)
          _PresetGroup(
            preset: preset,
            prefs: prefs,
            notifier: notifier,
            hostId: hostId,
          ),
        const Divider(height: Spacing.lg),
        Text(
          context.l10n.customLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Spacing.xs),
        if (custom.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Text(
              context.l10n.noCustomExtensions,
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
                  onDeleted:
                      () => notifier.removeExtension(ext, hostId: hostId),
                ),
            ],
          ),
        const SizedBox(height: Spacing.xs),
        _AddExtensionField(
          onSubmit: (e) => notifier.addExtension(e, hostId: hostId),
        ),
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
      title: context.l10n.fileVisibilitySection,
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
/// nothing jumps; toggling off clears it.
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
      title: context.l10n.fileVisibilityDeviceSection,
      icon: Icons.visibility_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Text(
            context.l10n.followsAppDefaultVisibility,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(context.l10n.overrideForDevice),
          subtitle: Text(
            isOverridden
                ? context.l10n.usingDeviceVisibility
                : context.l10n.usingAppDefault,
          ),
          value: isOverridden,
          onChanged: (on) => notifier.setDeviceVisibilityOverride(hostId, on),
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
                  onSelected:
                      (selected) =>
                          selected
                              ? notifier.addExtension(ext, hostId: hostId)
                              : notifier.removeExtension(ext, hostId: hostId),
                ),
              for (final name in names)
                FilterChip(
                  label: Text(name),
                  selected: lowerHiddenNames.contains(name.toLowerCase()),
                  onSelected:
                      (selected) =>
                          selected
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
        hintText: context.l10n.addExtensionHint,
        suffixIcon: IconButton(
          icon: const Icon(Icons.add),
          tooltip: context.l10n.addExtensionTooltip,
          onPressed: _submit,
        ),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}

/// A single paired-device row showing its identity, status, and a read-only
/// jail badge if the PC has restricted that device to a folder.
///
/// A phone may only manage ITSELF: the current-device row gets a single
/// "Disconnect" action that un-pairs this phone (see
/// [_SettingsScreenState._disconnectThisDevice]); every other row is purely
/// informational, with a "Managed on the PC" caption in place of any
/// revoke/remove/jail-edit controls — those are now PC-only.
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
      status = context.l10n.thisDevice;
      statusColor = Brand.online;
    } else {
      final parts = <String>[
        d.revoked ? context.l10n.revokedStatus : context.l10n.activeStatus,
        if (d.lastAddress.isNotEmpty) d.lastAddress,
        if (d.lastVersion.isNotEmpty) 'v${d.lastVersion}',
        formatRelative(d.lastSeen.toLocal()),
      ];
      status = parts.join(' · ');
      statusColor = d.revoked ? scheme.error : Brand.online;
    }

    final trailing =
        d.current
            ? TextButton(
              onPressed: () => screen._disconnectThisDevice(d),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: Text(context.l10n.disconnectButton),
            )
            : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        d.revoked ? Icons.phonelink_erase : Icons.smartphone,
        color: d.revoked ? scheme.error : scheme.onSurfaceVariant,
      ),
      title: Text(d.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status, style: TextStyle(color: statusColor)),
          if (d.jailRoot.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: scheme.tertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      context.l10n.limitedTo(d.jailRoot),
                      style: TextStyle(color: scheme.tertiary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (!d.current)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                context.l10n.managedOnPc,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
        ],
      ),
      trailing: trailing,
    );
  }
}

/// One drive/mount point in the About section: its label (or path) as the
/// header, with used/total capacity and free space beneath. The drive
/// containing the OS gets a distinct icon and a note in the subtitle. Drives
/// with no known capacity (`totalBytes` null or 0) are skipped by the caller.
class _DriveRow extends StatelessWidget {
  const _DriveRow({required this.drive});

  final Drive drive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = drive.totalBytes ?? 0;
    final free = drive.freeBytes ?? 0;
    final used = total - free;
    final name =
        (drive.label != null && drive.label!.isNotEmpty)
            ? drive.label!
            : drive.path;

    final usedStr = formatSize(used);
    final totalStr = formatSize(total);
    final freeStr = formatSize(free);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        drive.isOS ? Icons.memory : Icons.storage_outlined,
        color: drive.isOS ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Expanded(child: Text(name)),
          if (drive.isOS) ...[
            const SizedBox(width: Spacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xs,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.l10n.osLabel,
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        drive.isOS
            ? context.l10n.driveCapacityLineOs(usedStr, totalStr, freeStr)
            : context.l10n.driveCapacityLine(usedStr, totalStr, freeStr),
      ),
    );
  }
}
