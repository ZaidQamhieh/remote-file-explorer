import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/api/providers.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/models/drive.dart';
import '../../../core/models/health.dart';
import '../../../core/models/host.dart';
import '../../../core/platform/wol.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/storage/host_store.dart';
import '../../../core/theme/tokens.dart';
import '../../explorer/drives_view.dart';
import '../../explorer/explorer_screen.dart';
import '../../search/search_screen.dart';
import '../../settings/settings_screen.dart';
import '../../transfers/transfer_manager.dart';
import '../storage_insights_screen.dart';
import 'connection_diagnostics_sheet.dart';
import 'storage_gauge.dart';

/// Maximum number of storage gauges shown before collapsing the rest behind
/// "+N more".
const _maxVisibleDrives = 3;

/// Picks the root screen to open when browsing [host], based on its most
/// recent `/health` response.
///
/// Windows hosts (`health.os == 'windows'`, case-insensitive) open the drive
/// list ([DrivesView]) since `/` isn't a meaningful path there. Any other (or
/// unknown/offline, `health == null`) OS opens [ExplorerScreen] rooted at `/`
/// as before.
Widget explorerRootFor(Health? health, Host host) {
  final isWindows = health?.os.toLowerCase() == 'windows';
  return isWindows ? DrivesView(host: host) : ExplorerScreen(host: host);
}

/// A single host's dashboard card: status, agent version, active-network
/// chip, storage gauges, and a quick actions row (Browse / Search /
/// Transfers / ⋯).
///
/// Pings the host's `/health` on mount to determine online/offline state and,
/// when online, fetches `AgentClient.drives()` for the storage gauges
/// (gracefully skipped if the agent predates that endpoint).
class HostCard extends ConsumerStatefulWidget {
  const HostCard({
    super.key,
    required this.host,
    required this.store,
    this.isFirst = false,
  });

  final Host host;
  final HostStore store;

  /// Whether this is the first (most-recently-used) host in the list.
  /// Currently unused by the card itself — kept so callers (the host list)
  /// don't need to change — but reserved for future first-card-only behavior.
  final bool isFirst;

  @override
  ConsumerState<HostCard> createState() => _HostCardState();
}

class _HostCardState extends ConsumerState<HostCard> {
  late Future<Health?> _pingFuture;
  Future<List<Drive>>? _drivesFuture;

  /// Address the most recent successful client used — drives the "LAN" vs
  /// "Tailscale" chip. `null` while unknown (offline / not yet pinged).
  bool? _isTailscaleActive;

  /// Wall-clock time the most recent ping resolved, used only to render a
  /// gentle relative "last checked" line — purely cosmetic, doesn't affect the
  /// online/offline determination itself.
  DateTime? _lastChecked;

  /// Last-seen timestamp loaded from the store, shown when offline.
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    _lastSeen = widget.store.getLastSeen(widget.host.id);
    _pingFuture = _ping();
  }

  Future<Health?> _ping() async {
    AgentClient? client;
    try {
      client = await buildClientForHost(
        ref.read,
        widget.host.id,
        probeLanFirst: true,
      );
      final health = await client.health().timeout(const Duration(seconds: 8));
      await _learnAddresses(health);
      final now = DateTime.now();
      await widget.store.setLastSeen(widget.host.id, now);
      if (mounted) {
        setState(() {
          _lastChecked = now;
          _lastSeen = now;
          _isTailscaleActive = client!.isActiveAddressTailscale;
        });
      }
      _drivesFuture = _loadDrives(client);
      return health;
    } catch (_) {
      if (mounted) setState(() => _lastChecked = DateTime.now());
      return null;
    } finally {
      client?.close();
    }
  }

  /// Fetches drives for the gauges. Returns an empty list (no gauge section)
  /// on any error — including a 404 from agents that predate `/system/drives`
  /// — so a missing endpoint never produces an error card.
  Future<List<Drive>> _loadDrives(AgentClient client) async {
    try {
      return await client.drives();
    } catch (_) {
      return const [];
    }
  }

  /// Adopts any LAN/Tailscale address or MAC the agent reports that we don't
  /// already know, so a host paired before Wave 2 (or paired only via one
  /// network) gradually learns to be reachable both at home and away — and
  /// the app caches the MAC for Wake-on-LAN when the host is asleep.
  Future<void> _learnAddresses(Health health) async {
    final newTailscale = health.tailscaleAddress;
    final newMac = health.macAddress;

    final tailscaleChanged =
        newTailscale != null &&
        newTailscale != widget.host.tailscaleAddress &&
        newTailscale != widget.host.address;
    final macChanged = newMac != null && newMac != widget.host.macAddress;

    if (!tailscaleChanged && !macChanged) return;

    var updated = widget.host;
    if (tailscaleChanged) {
      updated = updated.copyWith(tailscaleAddress: newTailscale);
    }
    if (macChanged) {
      updated = updated.copyWith(macAddress: newMac);
    }
    await widget.store.addHost(updated);
  }

  /// Opens the explorer for this host. If the most recent `/health` ping
  /// reported a Windows host, opens the drive list ([DrivesView]) first
  /// instead of a `/`-rooted listing, since `/` isn't a meaningful path on
  /// Windows. Any other (or unknown) OS keeps the existing `/`-rooted
  /// behaviour.
  Future<void> _openExplorer(BuildContext context) async {
    final health = await _pingFuture;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => explorerRootFor(health, widget.host)),
    );
  }

  /// Opens search for this host with a short-lived client, closed once the
  /// search screen is popped.
  Future<void> _openSearch(BuildContext context) async {
    AgentClient? client;
    try {
      client = await buildClientForHost(ref.read, widget.host.id);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => SearchScreen(
                host: widget.host,
                client: client!,
                currentPath: '/',
              ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotReachComputer)),
        );
      }
    } finally {
      client?.close();
    }
  }

  void _openTransfers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TransferManagerSheet(),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(host: widget.host)),
    );
  }

  void _openStorage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StorageInsightsScreen(host: widget.host),
      ),
    );
  }

  Future<void> _openDiagnostics(BuildContext context) async {
    final store = await ref.read(hostStoreProvider.future);
    final token = await store.getToken(widget.host.id);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) =>
              ConnectionDiagnosticsSheet(host: widget.host, deviceToken: token),
    );
  }

  Future<void> _sendWol(BuildContext context) async {
    final mac = widget.host.macAddress;
    if (mac == null) return;
    final sent = await sendWakeOnLan(mac);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? context.l10n.wolPacketSent(widget.host.label)
              : context.l10n.wolPacketFailed,
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
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
                child: Text(ctx.l10n.forgetButton),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await widget.store.removeHost(widget.host.id);
      ref.invalidate(hostStoreProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<Health?>(
      future: _pingFuture,
      builder: (context, snap) {
        final online = snap.data != null;
        final checking = snap.connectionState == ConnectionState.waiting;

        return Container(
          margin: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: Radii.lgR,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: Radii.lgR,
            onTap: () => _openExplorer(context),
            onLongPress: () => _confirmRemove(context),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HostHeader(
                    host: widget.host,
                    snapshot: snap,
                    checking: checking,
                    online: online,
                    isTailscaleActive: _isTailscaleActive,
                    lastChecked: _lastChecked,
                    lastSeen: _lastSeen,
                  ),
                  if (online && snap.data?.readOnly == true)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: Spacing.xs),
                          Text(
                            'Read-only',
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (online) ..._buildGauges(context),
                  const SizedBox(height: Spacing.md),
                  _QuickActions(
                    online: online,
                    canWake:
                        !online && !checking && widget.host.macAddress != null,
                    onBrowse: () => _openExplorer(context),
                    onSearch: () => _openSearch(context),
                    onWake: () => _sendWol(context),
                    onStorage: () => _openStorage(context),
                    onTransfers: () => _openTransfers(context),
                    onDiagnostics: () => _openDiagnostics(context),
                    onSettings: () => _openSettings(context),
                    onForget: () => _confirmRemove(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Storage gauge rows (up to [_maxVisibleDrives], with a "+N more" expander)
  /// for the drives reported by `AgentClient.drives()`. Renders nothing while
  /// loading, on error, or if the agent reports no drives — never an error
  /// block, per the graceful-fallback requirement.
  List<Widget> _buildGauges(BuildContext context) {
    final future = _drivesFuture;
    if (future == null) return const [];

    final threshold =
        ref.read(settingsProvider).valueOrNull?.app.lowDiskThresholdBytes ?? 0;

    return [
      const SizedBox(height: Spacing.sm),
      FutureBuilder<List<Drive>>(
        future: future,
        builder: (context, snap) {
          final drives = snap.data ?? const <Drive>[];
          if (drives.isEmpty) return const SizedBox.shrink();
          final hasLowDisk =
              threshold > 0 &&
              drives.any(
                (d) => d.freeBytes != null && d.freeBytes! < threshold,
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasLowDisk)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        context.l10n.lowDiskWarning,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              _DriveGauges(drives: drives),
            ],
          );
        },
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Header: icon block, name, status dot/label, version + network chip
// ---------------------------------------------------------------------------

class _HostHeader extends StatelessWidget {
  const _HostHeader({
    required this.host,
    required this.snapshot,
    required this.checking,
    required this.online,
    required this.isTailscaleActive,
    required this.lastChecked,
    required this.lastSeen,
  });

  final Host host;
  final AsyncSnapshot<Health?> snapshot;
  final bool checking;
  final bool online;
  final bool? isTailscaleActive;
  final DateTime? lastChecked;
  final DateTime? lastSeen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final health = snapshot.data;

    // The host name always renders at full opacity, even when offline.
    final nameText = Text(
      host.label,
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis,
    );

    final iconBlock = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: Radii.cardR,
      ),
      child: Icon(Icons.computer_rounded, color: scheme.onPrimaryContainer),
    );

    final statusLabel = _StatusLabel(checking: checking, online: online);

    final subtitleText = Text(
      _subtitle(context, health),
      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      overflow: TextOverflow.ellipsis,
    );

    final detailText =
        checking
            ? null
            : Text(
              _statusDetail(context),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            );

    // Offline hosts render dimmed to 60% opacity EXCEPT the host name, which
    // always stays fully legible. Everything else — the icon block, the
    // status label, and the subtitle/detail lines — is individually wrapped
    // in `Opacity(0.6)` when offline (and left untouched while
    // online/checking).
    final dimmed = !online && !checking;
    Widget maybeDim(Widget child) =>
        dimmed ? Opacity(opacity: 0.6, child: child) : child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        maybeDim(iconBlock),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: nameText),
                  const SizedBox(width: Spacing.sm),
                  maybeDim(statusLabel),
                ],
              ),
              const SizedBox(height: Spacing.xs / 2),
              maybeDim(subtitleText),
              if (detailText != null) ...[
                const SizedBox(height: Spacing.xs / 2),
                maybeDim(detailText),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// "v1.1.0 · Tailscale" / "v1.1.0 · LAN" when online and we know which
  /// address is active; falls back to the raw address when offline or
  /// unknown.
  String _subtitle(BuildContext context, Health? health) {
    final l = context.l10n;
    if (health != null) {
      final network =
          isTailscaleActive == true ? l.networkTailscale : l.networkLan;
      if (health.version.isEmpty) return network;
      return l.hostSubtitleVersionNetwork(health.version, network);
    }
    return host.address;
  }

  String _statusDetail(BuildContext context) {
    final l = context.l10n;
    if (online) {
      final relative = _relative(context, lastChecked);
      return relative == null
          ? l.onlineStatus
          : l.statusCheckedRelative(relative);
    }
    final relative = _relative(context, lastSeen);
    return relative == null
        ? l.offlineStatus
        : l.statusOfflineLastSeen(relative);
  }

  String? _relative(BuildContext context, DateTime? at) {
    if (at == null) return null;
    final l = context.l10n;
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 5) return l.relativeJustNow;
    if (diff.inMinutes < 1) return l.relativeSecondsAgo(diff.inSeconds);
    if (diff.inHours < 1) return l.relativeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l.relativeHoursAgo(diff.inHours);
    return l.relativeDaysAgo(diff.inDays);
  }
}

/// "● Online" / "● Offline" / "Checking…" status label with a coloured dot.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.checking, required this.online});

  final bool checking;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (checking) {
      return Text(
        context.l10n.checkingStatus,
        style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    final color = online ? Brand.online : Brand.offline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: Spacing.xs),
        Text(
          online ? context.l10n.onlineStatus : context.l10n.offlineStatus,
          style: textTheme.labelLarge?.copyWith(
            color: online ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Storage gauges (tertiaryContainer accent block — the card's one accent)
// ---------------------------------------------------------------------------

class _DriveGauges extends StatefulWidget {
  const _DriveGauges({required this.drives});

  final List<Drive> drives;

  @override
  State<_DriveGauges> createState() => _DriveGaugesState();
}

class _DriveGaugesState extends State<_DriveGauges> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final drives = widget.drives;
    final visible =
        _expanded ? drives : drives.take(_maxVisibleDrives).toList();
    final remaining = drives.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final drive in visible) StorageGauge(drive: drive),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: InkWell(
              borderRadius: Radii.chipR,
              onTap: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Spacing.xs / 2,
                  horizontal: Spacing.xs,
                ),
                child: Text(
                  context.l10n.nMoreDrives(remaining),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions row: Browse (filled), Search (tonal), ⋯ menu
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.online,
    required this.canWake,
    required this.onBrowse,
    required this.onSearch,
    required this.onWake,
    required this.onStorage,
    required this.onTransfers,
    required this.onDiagnostics,
    required this.onSettings,
    required this.onForget,
  });

  final bool online;
  final bool canWake;
  final VoidCallback onBrowse;
  final VoidCallback onSearch;
  final VoidCallback onWake;
  final VoidCallback onStorage;
  final VoidCallback onTransfers;
  final VoidCallback onDiagnostics;
  final VoidCallback onSettings;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Browse stays enabled offline — cached/offline browsing works.
        // `Expanded` splits the row evenly between Browse and Search (the ⋯
        // menu keeps its intrinsic width); ellipsis is kept as a fallback for
        // extreme a11y text-scale values (1.3×–2.0×).
        Expanded(
          child: FilledButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(
              context.l10n.browseButton,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        if (canWake) ...[
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: onWake,
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: Text(
                context.l10n.wakeButton,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ] else ...[
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: online ? onSearch : null,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: Text(
                context.l10n.searchButton,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        const SizedBox(width: Spacing.sm),
        PopupMenuButton<String>(
          tooltip: context.l10n.moreTooltip,
          shape: const RoundedRectangleBorder(borderRadius: Radii.smR),
          onSelected: (v) {
            switch (v) {
              case 'wake':
                onWake();
              case 'storage':
                onStorage();
              case 'transfers':
                onTransfers();
              case 'diagnostics':
                onDiagnostics();
              case 'settings':
                onSettings();
              case 'forget':
                onForget();
            }
          },
          itemBuilder:
              (ctx) => [
                if (online)
                  PopupMenuItem(
                    value: 'storage',
                    child: Text(ctx.l10n.storageMenuItem),
                  ),
                PopupMenuItem(
                  value: 'transfers',
                  child: Text(ctx.l10n.transfersMenuItem),
                ),
                PopupMenuItem(
                  value: 'diagnostics',
                  child: Text(ctx.l10n.diagnosticsMenuItem),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Text(ctx.l10n.settingsMenuItem),
                ),
                PopupMenuItem(
                  value: 'forget',
                  child: Text(ctx.l10n.forgetComputerMenuItem),
                ),
              ],
        ),
      ],
    );
  }
}
