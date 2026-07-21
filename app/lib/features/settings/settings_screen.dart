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
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../hosts/storage_insights_screen.dart';
import '../hosts/widgets/connection_diagnostics_sheet.dart';
import '../sync/sync_screen.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Mockup shows a truncated `7f:3a:9c…` fingerprint under the host name —
/// the raw stored value is a full-length hex string with no separators
/// baked in by the agent, so this groups it into byte pairs before cutting.
String? _shortFingerprint(String? fp) {
  if (fp == null || fp.isEmpty) return null;
  final bytes = <String>[
    for (var i = 0; i + 2 <= fp.length && i < 6; i += 2) fp.substring(i, i + 2),
  ];
  if (bytes.isEmpty) return null;
  return '${bytes.join(':')}…';
}

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
      final results = await Future.wait<dynamic>([
        client.getSettings(),
        client.listDevices(),
        client.drives(),
        // Agent may not support the bandwidth endpoint yet — use defaults.
        client.getBandwidth().catchError((_) => const BandwidthSettings()),
      ]);
      setState(() {
        _client = client;
        _settings = results[0] as AgentSettings;
        _devices = results[1] as List<Device>;
        _drives = results[2] as List<Drive>;
        _bandwidth = results[3] as BandwidthSettings;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = humanizeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _patch({
    bool? readOnly,
    String? name,
    bool? allowSharing,
    String? successMsg,
  }) async {
    final client = _client;
    if (client == null) return;
    final prev = _settings;
    // Optimistic update.
    setState(() {
      _settings = _settings?.copyWith(
        readOnly: readOnly,
        agentName: name,
        allowSharing: allowSharing,
      );
    });
    try {
      final updated = await client.updateSettings(
        readOnly: readOnly,
        agentName: name,
        allowSharing: allowSharing,
      );
      setState(() => _settings = updated);
      if (mounted && successMsg != null) showSuccess(context, successMsg);
    } catch (e) {
      setState(() => _settings = prev); // rollback
      if (mounted) {
        showError(context, context.l10n.updateFailed(humanizeError(e)));
      }
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
      if (mounted) {
        showError(context, context.l10n.disconnectFailed(humanizeError(e)));
      }
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

  Future<void> _openConnectionDiagnostics(BuildContext context) async {
    final store = await ref.read(hostStoreProvider.future);
    final token = await store.getToken(widget.host.id);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) =>
              ConnectionDiagnosticsSheet(host: widget.host, deviceToken: token),
    );
  }

  Future<void> _revokeAccess() async {
    for (final d in _devices) {
      if (d.current) {
        await _disconnectThisDevice(d);
        return;
      }
    }
  }

  Future<void> _forgetThisDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(ctx.l10n.forgetComputerTitle),
            content: Text(ctx.l10n.forgetComputerConfirm(widget.host.label)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: Text(ctx.l10n.forgetButton),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    final store = await ref.read(hostStoreProvider.future);
    await store.removeHost(widget.host.id);
    if (!mounted) return;
    ref.invalidate(hostStoreProvider);
    Navigator.of(context).popUntil((route) => route.isFirst);
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
    if (name != null && name.isNotEmpty && mounted) {
      await _patch(name: name, successMsg: context.l10n.renamedTo(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fingerprint = _shortFingerprint(widget.host.certFingerprint);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.host.label.isNotEmpty
                  ? widget.host.label
                  : widget.host.address,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (fingerprint != null)
              Text.rich(
                TextSpan(
                  text: '${widget.host.address} · fingerprint ',
                  children: [
                    TextSpan(
                      text: fingerprint,
                      style: const TextStyle(fontFamily: 'JetBrains Mono'),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.xs,
            0,
            Spacing.xs,
            Spacing.md,
          ),
          child: Text(
            context.l10n.securityWarning,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        SettingsSection(
          title: context.l10n.agentSection,
          children: [
            SettingsTile.value(
              icon: LucideIcons.server,
              badgeColor: scheme.primary,
              title: context.l10n.agentNameLabel,
              value: s.agentName,
              onTap: _editName,
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.accessSection,
          children: [
            SettingsTile.toggle(
              icon: LucideIcons.lock,
              badgeColor: scheme.primary,
              title: context.l10n.readOnlyMode,
              subtitle:
                  s.readOnly
                      ? context.l10n.writesRejected
                      : context.l10n.phoneCanModify,
              value: s.readOnly,
              onChanged: (v) => _patch(readOnly: v),
            ),
            SettingsTile.toggle(
              icon: LucideIcons.link,
              badgeColor: scheme.primary,
              title: context.l10n.enableShareLinks,
              subtitle:
                  s.allowSharing
                      ? context.l10n.shareLinksEnabledHint
                      : context.l10n.shareLinksDisabledHint,
              value: s.allowSharing,
              onChanged: (v) => _patch(allowSharing: v),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.limitsSection,
          children: [
            ..._BandwidthSection(
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
                  if (mounted) {
                    showError(
                      this.context,
                      this.context.l10n.updateFailed(humanizeError(e)),
                    );
                  }
                }
              },
            ).rows,
            SettingsTile.nav(
              icon: LucideIcons.chartPie,
              badgeColor: Brand.accent,
              title: context.l10n.storageInsightsTitle,
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => StorageInsightsScreen(host: widget.host),
                    ),
                  ),
            ),
            SettingsTile.nav(
              icon: LucideIcons.activity,
              badgeColor: Brand.online,
              title: context.l10n.connectionDiagnosticsTitle,
              onTap: () => _openConnectionDiagnostics(context),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.allowedFoldersSection,
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
                (r) => _InfoRow(icon: LucideIcons.folder, title: r),
              ),
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text(
                context.l10n.managedOnPc,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        DeviceVisibilityOverrideSection(hostId: widget.host.id),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.pairedDevicesSection,
          children: [
            for (final d in _devices) _DeviceRow(device: d, screen: this),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: 'Sync Rules',
          children: [
            SettingsTile.nav(
              icon: LucideIcons.refreshCw,
              badgeColor: scheme.primary,
              title: 'Manage Sync Rules',
              subtitle: 'Download remote folders to local storage',
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SyncScreen(hostId: widget.host.id),
                    ),
                  ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SettingsSection(
          title: context.l10n.aboutSection,
          children: [
            _InfoRow(
              icon: LucideIcons.monitorSmartphone,
              title: context.l10n.pcNameLabel,
              subtitle:
                  s.agentName.isNotEmpty
                      ? s.agentName
                      : (widget.host.label.isNotEmpty
                          ? widget.host.label
                          : widget.host.address),
            ),
            if (drivesWithCapacity.isNotEmpty)
              for (final drive in drivesWithCapacity) _DriveRow(drive: drive),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SectionLabel(context.l10n.dangerZoneSection),
        Pressable(
          onTap: _revokeAccess,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: Radii.smR,
            ),
            child: Text(
              context.l10n.revokeAccessButton,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.error,
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Pressable(
          onTap: _forgetThisDevice,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: Radii.smR,
            ),
            child: Text(
              context.l10n.forgetThisDeviceButton,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The mockup's `.row`, informational-only (no chevron, not tappable) — for
/// rows on this screen that just display a fact (an allowed-folder path, the
/// PC's own name) rather than opening or toggling anything.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _rowBadge(icon, scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.row-icon`: matches [SettingsTile]'s own badge exactly, for
/// rows on this screen that need custom trailing widgets (disconnect button,
/// OS chip) and so can't use [SettingsTile] itself.
Widget _rowBadge(IconData icon, Color tint) {
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.15),
      borderRadius: Radii.smR,
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 18, color: tint),
  );
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

/// Builds the two bandwidth rows as [SettingsTile.value]s — tapping opens a
/// bottom-sheet picker (matching the mockup's tap-to-pick "value ›" row
/// idiom already used for the agent-name row) instead of a Material
/// [DropdownButton]'s native popup menu, which has no equivalent in the
/// mockup at all.
class _BandwidthSection {
  _BandwidthSection({required this.bandwidth, required this.onChanged});

  final BandwidthSettings bandwidth;
  final ValueChanged<BandwidthSettings> onChanged;

  String _label(BuildContext context, int bytesPerSec) {
    if (bytesPerSec == 0) return context.l10n.bandwidthUnlimited;
    return '${formatSize(bytesPerSec)}/s';
  }

  List<Widget> get rows => [
    Builder(
      builder:
          (context) => SettingsTile.value(
            icon: LucideIcons.arrowUp,
            badgeColor: Brand.amber,
            title: context.l10n.bandwidthUploadLimit,
            value: _label(context, bandwidth.maxUploadBytesPerSec),
            onTap:
                () => _pickBandwidth(
                  context,
                  current: bandwidth.maxUploadBytesPerSec,
                  onSelected:
                      (v) => onChanged(
                        bandwidth.copyWith(maxUploadBytesPerSec: v),
                      ),
                ),
          ),
    ),
    Builder(
      builder:
          (context) => SettingsTile.value(
            icon: LucideIcons.arrowDown,
            badgeColor: Brand.amber,
            title: context.l10n.bandwidthDownloadLimit,
            value: _label(context, bandwidth.maxDownloadBytesPerSec),
            onTap:
                () => _pickBandwidth(
                  context,
                  current: bandwidth.maxDownloadBytesPerSec,
                  onSelected:
                      (v) => onChanged(
                        bandwidth.copyWith(maxDownloadBytesPerSec: v),
                      ),
                ),
          ),
    ),
  ];

  Future<void> _pickBandwidth(
    BuildContext context, {
    required int current,
    required ValueChanged<int> onSelected,
  }) async {
    final items =
        _bandwidthPresets.contains(current)
            ? _bandwidthPresets
            : [current, ..._bandwidthPresets];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in items)
                  SettingsTile.nav(
                    icon: v == current ? LucideIcons.check : LucideIcons.gauge,
                    badgeColor: Brand.amber,
                    title: _label(ctx, v),
                    onTap: () => Navigator.pop(ctx, v),
                  ),
              ],
            ),
          ),
    );
    if (picked != null) onSelected(picked);
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
        SettingsTile.toggle(
          icon: LucideIcons.eyeOff,
          badgeColor: scheme.primary,
          title: context.l10n.hideDotfiles,
          subtitle: context.l10n.hideDotfilesSubtitle,
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
        AddExtensionField(
          onSubmit: (e) => notifier.addExtension(e, hostId: hostId),
        ),
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
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Text(
            context.l10n.followsAppDefaultVisibility,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        SettingsTile.toggle(
          icon: LucideIcons.copy,
          badgeColor: scheme.primary,
          title: context.l10n.overrideForDevice,
          subtitle:
              isOverridden
                  ? context.l10n.usingDeviceVisibility
                  : context.l10n.usingAppDefault,
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
class AddExtensionField extends StatefulWidget {
  const AddExtensionField({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<AddExtensionField> createState() => AddExtensionFieldState();
}

class AddExtensionFieldState extends State<AddExtensionField> {
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
        suffixIcon: Tooltip(
          message: context.l10n.addExtensionTooltip,
          child: Pressable(
            onTap: _submit,
            pressedScale: 0.92,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(LucideIcons.plus, size: 18),
            ),
          ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _rowBadge(
            d.revoked ? LucideIcons.unplug : LucideIcons.smartphone,
            d.revoked ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  status,
                  style: TextStyle(fontSize: 11.5, color: statusColor),
                ),
                if (d.jailRoot.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.lock,
                          size: 14,
                          color: scheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            context.l10n.limitedTo(d.jailRoot),
                            style: TextStyle(
                              color: scheme.tertiary,
                              fontSize: 12,
                            ),
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
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (d.current)
            Pressable(
              onTap: () => screen._disconnectThisDevice(d),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                child: Text(
                  context.l10n.disconnectButton,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _rowBadge(
            drive.isOS ? LucideIcons.memoryStick : LucideIcons.hardDrive,
            scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                const SizedBox(height: 1),
                Text(
                  drive.isOS
                      ? context.l10n.driveCapacityLineOs(
                        usedStr,
                        totalStr,
                        freeStr,
                      )
                      : context.l10n.driveCapacityLine(
                        usedStr,
                        totalStr,
                        freeStr,
                      ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
