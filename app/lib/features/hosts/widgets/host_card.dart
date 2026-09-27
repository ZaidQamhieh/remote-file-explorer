import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
import '../../../core/ui/feedback.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/pressable.dart';
import '../../explorer/drives_view.dart';
import '../../explorer/explorer_screen.dart';
import '../../home/home_state.dart';
import '../../search/search_screen.dart';
import '../../settings/settings_screen.dart';
import '../host_apps_screen.dart';
import 'storage_gauge.dart';

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

/// A host dashboard card with status, active route/version, drive gauges, and
/// direct Browse/Search/Transfers/Settings actions.
///
/// Pings the host's `/health` on mount to determine online/offline state and,
/// when online, fetches `AgentClient.drives()` for the storage bar (gracefully
/// skipped if the agent predates that endpoint).
class HostCard extends ConsumerStatefulWidget {
  const HostCard({
    super.key,
    required this.host,
    required this.store,
    this.onOnlineChanged,
    this.isHero = false,
  });

  final Host host;
  final HostStore store;

  /// Reports this host's online/offline state up to the parent list once
  /// known, so it can render the "N paired · N online now" header subtitle.
  /// Purely a display callback — doesn't affect the ping/health logic below.
  final ValueChanged<bool>? onOnlineChanged;

  /// Gives the first, most-recently-paired host a slightly stronger title
  /// hierarchy while keeping the same dashboard layout and actions.
  final bool isHero;

  @override
  ConsumerState<HostCard> createState() => _HostCardState();
}

class _HostCardState extends ConsumerState<HostCard> {
  late Future<Health?> _pingFuture;
  Future<List<Drive>>? _drivesFuture;

  /// Address used by the most recent successful client, so the card can show
  /// whether it is reached over LAN, Tailscale, or the direct HTTPS route.
  String? _activeAddress;

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
          _lastSeen = now;
          _activeAddress = client!.activeAddress;
        });
      }
      // _drivesFuture stays in flight after _ping returns (its own
      // FutureBuilder resolves independently, so the online/offline status
      // above isn't held up waiting for it) — the client must stay open
      // until IT finishes, not close as soon as _ping does (PR-36: this used
      // to close in a `finally` here regardless, racing this still-pending
      // request against a closed connection).
      _drivesFuture = _loadDrives(client).whenComplete(client.close);
      return health;
    } catch (_) {
      client?.close();
      return null;
    }
  }

  /// Fetches drives for the storage-usage bar. Returns an empty list on any
  /// error — including a 404 from agents that predate `/system/drives` — so a
  /// missing endpoint just skips the bar instead of showing an error state.
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

  /// Opens the explorer for this host (the mockup's card `onclick` switches
  /// to the Files tab). If the most recent `/health` ping reported a Windows
  /// host, opens the drive list ([DrivesView]) first instead of a `/`-rooted
  /// listing, since `/` isn't a meaningful path on Windows.
  Future<void> _openExplorer(BuildContext context) async {
    final health = await _pingFuture;
    if (!context.mounted) return;
    ref.read(activeHostProvider.notifier).state = ActiveHost(
      host: widget.host,
      health: health,
    );
    ref.read(selectedTabIndexProvider.notifier).state = 1;
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(host: widget.host)),
    );
  }

  void _openApps(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostAppsScreen(host: widget.host)),
    );
  }

  /// Switches to the Transfers tab (index 2, see [selectedTabIndexProvider]'s
  /// doc comment) while keeping this host selected for per-host transfer views.
  void _openTransfers() {
    ref.read(activeHostProvider.notifier).state = ActiveHost(
      host: widget.host,
      health: null,
    );
    ref.read(selectedTabIndexProvider.notifier).state = 2;
  }

  /// Opens the same full search screen as the explorer's search action. If a
  /// result is chosen, switch to Files at that result's parent directory.
  Future<void> _openSearch(BuildContext context) async {
    final health = await _pingFuture;
    if (!mounted || health == null) return;

    AgentClient? client;
    try {
      client = await buildClientForHost(ref.read, widget.host.id);
      if (!context.mounted) return;
      final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder:
              (_) => SearchScreen(
                host: widget.host,
                client: client!,
                currentPath: '/',
              ),
        ),
      );
      if (!mounted || path == null) return;
      ref.read(activeHostProvider.notifier).state = ActiveHost(
        host: widget.host,
        health: health,
        initialPath: path,
      );
      ref.read(selectedTabIndexProvider.notifier).state = 1;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.errorLabel(humanizeError(error))),
          ),
        );
      }
    } finally {
      client?.close();
    }
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
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(ctx.l10n.forgetComputerTitle),
            description: Text(
              ctx.l10n.forgetComputerConfirm(widget.host.label),
            ),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton.destructive(
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
    return FutureBuilder<Health?>(
      future: _pingFuture,
      builder: (context, snap) {
        final online = snap.data != null;
        final checking = snap.connectionState == ConnectionState.waiting;
        if (!checking) {
          // Report the resolved status up to the list header once known.
          // Deferred a frame so this never calls setState during the parent's
          // own build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onOnlineChanged?.call(online);
          });
        }
        void onTap() {
          if (online) {
            _openExplorer(context);
          } else if (widget.host.macAddress != null) {
            _sendWol(context);
          }
        }

        return _CardBody(
          host: widget.host,
          health: snap.data,
          online: online,
          checking: checking,
          activeAddress: _activeAddress,
          lastSeen: _lastSeen,
          drivesFuture: _drivesFuture,
          isFeatured: widget.isHero,
          lowDiskThresholdBytes:
              ref
                  .watch(settingsProvider)
                  .valueOrNull
                  ?.app
                  .lowDiskThresholdBytes ??
              0,
          onTap:
              checking || (!online && widget.host.macAddress == null)
                  ? null
                  : onTap,
          onBrowseTap: () => _openExplorer(context),
          onSearchTap: () => _openSearch(context),
          onTransfersTap: _openTransfers,
          onAppsTap: () => _openApps(context),
          onSettingsTap: () => _openSettings(context),
          onRefresh: () => setState(() => _pingFuture = _ping()),
          onForget: () => _confirmRemove(context),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Expressive M3 host dashboard card.
// ---------------------------------------------------------------------------

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.host,
    required this.health,
    required this.online,
    required this.checking,
    required this.activeAddress,
    required this.lastSeen,
    required this.drivesFuture,
    required this.isFeatured,
    required this.lowDiskThresholdBytes,
    required this.onTap,
    required this.onBrowseTap,
    required this.onSearchTap,
    required this.onTransfersTap,
    required this.onAppsTap,
    required this.onSettingsTap,
    required this.onRefresh,
    required this.onForget,
  });

  final Host host;
  final Health? health;
  final bool online;
  final bool checking;
  final String? activeAddress;
  final DateTime? lastSeen;
  final Future<List<Drive>>? drivesFuture;
  final bool isFeatured;
  final int lowDiskThresholdBytes;
  final VoidCallback? onTap;
  final VoidCallback onBrowseTap;
  final VoidCallback onSearchTap;
  final VoidCallback onTransfersTap;
  final VoidCallback onAppsTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onRefresh;
  final VoidCallback onForget;

  String _routeLabel(BuildContext context) {
    final route = host.routeForAddress(activeAddress ?? host.address);
    return switch (route) {
      HostRoute.lan => context.l10n.networkLan,
      HostRoute.tailscale => context.l10n.networkTailscale,
      HostRoute.directHttps => context.l10n.networkInternet,
      HostRoute.custom => 'Custom route',
    };
  }

  String _subtitle(BuildContext context) {
    if (!online || checking) return '';
    final version = health?.version.trim() ?? '';
    final route = _routeLabel(context);
    return version.isEmpty ? route : 'v$version · $route';
  }

  String _statusLabel(BuildContext context) {
    if (checking) return context.l10n.checkingStatus;
    if (online) return context.l10n.onlineStatus;
    return lastSeen != null
        ? context.l10n.statusOfflineLastSeen(_relative(context, lastSeen!))
        : context.l10n.offlineStatus;
  }

  String _relative(BuildContext context, DateTime at) {
    final l = context.l10n;
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 5) return l.relativeJustNow;
    if (diff.inMinutes < 1) return l.relativeSecondsAgo(diff.inSeconds);
    if (diff.inHours < 1) return l.relativeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l.relativeHoursAgo(diff.inHours);
    return l.relativeDaysAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final readOnly = online && health?.readOnly == true;
    final statusColor =
        checking
            ? scheme.outline
            : online
            ? Brand.online
            : scheme.onSurfaceVariant;
    final subtitle = _subtitle(context);
    final quickActionStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      onTap: onTap,
      label: '${host.label}, ${_statusLabel(context)}',
      child: Opacity(
        opacity: online ? 1 : 0.55,
        child: Pressable(
          onTap: onTap,
          onLongPress: onForget,
          child: Container(
            padding: EdgeInsets.all(isFeatured ? Spacing.md3 : Spacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        LucideIcons.monitor,
                        size: 24,
                        color:
                            online ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  host.label,
                                  style:
                                      isFeatured
                                          ? textTheme.headlineSmall
                                          : textTheme.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (readOnly) ...[
                                const SizedBox(width: Spacing.xs),
                                Tooltip(
                                  message: 'Read-only',
                                  child: SizedBox.square(
                                    dimension: 48,
                                    child: Center(
                                      child: Icon(
                                        LucideIcons.lock,
                                        size: 16,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (online && drivesFuture != null)
                                _LowDiskBadge(
                                  drivesFuture: drivesFuture!,
                                  thresholdBytes: lowDiskThresholdBytes,
                                ),
                            ],
                          ),
                          const SizedBox(height: Spacing.xs),
                          Semantics(
                            label:
                                subtitle.isEmpty
                                    ? _statusLabel(context)
                                    : '${_statusLabel(context)} · $subtitle',
                            excludeSemantics: true,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: Spacing.xs),
                                Text(
                                  _statusLabel(context),
                                  style: textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: Spacing.sm),
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    IconButton(
                      tooltip: context.l10n.refreshTooltip,
                      onPressed: checking ? null : onRefresh,
                      icon: const Icon(LucideIcons.refreshCw, size: 18),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                    ),
                    _KebabMenu(
                      onSettingsTap: onSettingsTap,
                      onForgetTap: onForget,
                      vertical: true,
                      dimmed: !online,
                    ),
                  ],
                ),
                if (online && drivesFuture != null) ...[
                  const SizedBox(height: Spacing.md),
                  _DriveGaugeList(drivesFuture: drivesFuture!),
                ] else if (!online && !checking) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Browse cached files while this computer is offline.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: checking ? null : onBrowseTap,
                          style: quickActionStyle,
                          icon: const Icon(LucideIcons.folderOpen, size: 18),
                          label: Text(
                            online ? context.l10n.openButton : 'Browse cache',
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: online && !checking ? onSearchTap : null,
                          style: quickActionStyle,
                          icon: const Icon(LucideIcons.search, size: 18),
                          label: Text(context.l10n.searchButton),
                        ),
                        const SizedBox(width: Spacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: onTransfersTap,
                          style: quickActionStyle,
                          icon: const Icon(
                            LucideIcons.arrowLeftRight,
                            size: 18,
                          ),
                          label: Text(context.l10n.transfersMenuItem),
                        ),
                        const SizedBox(width: Spacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: onSettingsTap,
                          style: quickActionStyle,
                          icon: const Icon(LucideIcons.settings, size: 18),
                          label: Text(context.l10n.settingsMenuItem),
                        ),
                        const SizedBox(width: Spacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: online && !checking ? onAppsTap : null,
                          style: quickActionStyle,
                          icon: const Icon(LucideIcons.monitor, size: 18),
                          label: Text(context.l10n.hostAppsButton),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows up to three real per-drive gauges on a host card, with an explicit
/// expansion affordance for machines that report more roots or volumes.
class _DriveGaugeList extends StatefulWidget {
  const _DriveGaugeList({required this.drivesFuture});

  final Future<List<Drive>> drivesFuture;

  @override
  State<_DriveGaugeList> createState() => _DriveGaugeListState();
}

class _DriveGaugeListState extends State<_DriveGaugeList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Drive>>(
      future: widget.drivesFuture,
      builder: (context, snap) {
        final drives =
            (snap.data ?? const <Drive>[])
                .where((drive) => usedFraction(drive) != null)
                .toList();
        if (drives.isEmpty) return const SizedBox.shrink();
        final visible = _expanded ? drives : drives.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final drive in visible) ...[
              _DriveGauge(drive: drive),
              const SizedBox(height: Spacing.sm),
            ],
            if (drives.length > 3)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                ),
                icon: Icon(
                  _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                ),
                label: Text(
                  _expanded
                      ? 'Show fewer drives'
                      : '+${drives.length - 3} more drives',
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Exposes a drive's name, used percentage, and capacity as one meaningful
/// screen-reader item while retaining the visible label and progress bar.
class _DriveGauge extends StatelessWidget {
  const _DriveGauge({required this.drive});

  final Drive drive;

  @override
  Widget build(BuildContext context) {
    final fraction = usedFraction(drive);
    if (fraction == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = drive.label?.isNotEmpty == true ? drive.label! : drive.path;
    final free = drive.freeBytes!;
    final total = drive.totalBytes!;
    final value =
        '${(fraction * 100).round()}% used · ${formatSize(free)} free of '
        '${formatSize(total)}';

    return Semantics(
      label: label,
      value: value,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  '${formatSize(free)} free · ${formatSize(total)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            ClipRRect(
              borderRadius: Radii.stadiumR,
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: scheme.tertiaryContainer,
                valueColor: AlwaysStoppedAnimation(scheme.tertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The confirmed mockup's overflow kebab — a real menu (Settings/Forget),
/// styled as the mockup's `.flt-orbits`/`.hero-menu` chip: 3 small dots (not
/// a single glyph) in their own translucent chip surface. [vertical] picks
/// the row's stacked layout vs. the hero's horizontal one; the hover-driven
/// colour-sweep dot animation from the mockup is dropped since touch phones
/// have no hover state to trigger it.
class _KebabMenu extends StatelessWidget {
  const _KebabMenu({
    required this.onSettingsTap,
    required this.onForgetTap,
    required this.vertical,
    required this.dimmed,
  });

  final VoidCallback onSettingsTap;
  final VoidCallback onForgetTap;
  final bool vertical;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<VoidCallback>(
      tooltip: context.l10n.moreOptionsTooltip,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: Radii.chipR),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: _DotsChip(vertical: vertical, dimmed: dimmed)),
      ),
      onSelected: (action) => action(),
      itemBuilder:
          (context) => [
            PopupMenuItem(
              value: onSettingsTap,
              child: Row(
                children: [
                  Icon(LucideIcons.settings, size: 16),
                  const SizedBox(width: Spacing.sm),
                  Text(context.l10n.settingsMenuItem),
                ],
              ),
            ),
            PopupMenuItem(
              value: onForgetTap,
              child: Row(
                children: [
                  Icon(LucideIcons.trash2, size: 16, color: scheme.error),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    context.l10n.forgetButton,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
              ),
            ),
          ],
    );
  }
}

/// The mockup's 3-dot chip surface (`.flt-orbits` / `.hero-menu`): small dots
/// in a translucent rounded chip, laid out vertically for the row's kebab or
/// horizontally for the hero's.
class _DotsChip extends StatelessWidget {
  const _DotsChip({required this.vertical, required this.dimmed});

  final bool vertical;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = scheme.onSurfaceVariant.withValues(
      alpha: dimmed ? .4 : .7,
    );
    final dots = [
      for (var i = 0; i < 3; i++)
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .03),
        border: Border.all(color: scheme.onSurface.withValues(alpha: .05)),
        borderRadius: BorderRadius.circular(9),
      ),
      child:
          vertical
              ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < dots.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    dots[i],
                  ],
                ],
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < dots.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    dots[i],
                  ],
                ],
              ),
    );
  }
}

/// Screen-reader labeled warning when a volume falls below the configured
/// free-space threshold. Full per-drive detail is shown in the storage gauges.
class _LowDiskBadge extends StatelessWidget {
  const _LowDiskBadge({
    required this.drivesFuture,
    required this.thresholdBytes,
  });

  final Future<List<Drive>> drivesFuture;
  final int thresholdBytes;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Drive>>(
      future: drivesFuture,
      builder: (context, snap) {
        final drives = snap.data ?? const <Drive>[];
        final hasLowDisk =
            thresholdBytes > 0 &&
            drives.any(
              (d) => d.freeBytes != null && d.freeBytes! < thresholdBytes,
            );
        if (!hasLowDisk) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: Spacing.xs),
          child: Tooltip(
            message: context.l10n.lowDiskWarning,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Icon(
                  LucideIcons.triangleAlert,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
