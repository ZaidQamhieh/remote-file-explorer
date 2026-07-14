import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
import '../../../core/ui/sheet_chrome.dart';
import '../../explorer/drives_view.dart';
import '../../explorer/explorer_screen.dart';
import '../../home/home_state.dart';
import '../../search/search_screen.dart';
import '../../settings/settings_screen.dart';
import '../../transfers/transfer_manager.dart';
import '../storage_insights_screen.dart';
import 'connection_diagnostics_sheet.dart';

/// Curated accent palette for [hostAccentColor] — picked hues rather than raw
/// hash→HSL so every result stays legible on both light and dark surfaces.
const List<Color> _hostAccentPalette = [
  Color(0xFF4285F4), // blue
  Color(0xFF34A853), // green
  Color(0xFFEA4335), // red
  Color(0xFFFBBC05), // amber
  Color(0xFF9C27B0), // purple
  Color(0xFF00ACC1), // cyan
  Color(0xFFFF7043), // orange
  Color(0xFF5C6BC0), // indigo
];

/// Deterministic string hash (djb2). Used instead of [Object.hashCode], which
/// Dart doesn't guarantee to stay fixed across SDK versions — this keeps a
/// host's accent color stable across app runs/restarts.
int _stableHash(String s) {
  var hash = 5381;
  for (final code in s.codeUnits) {
    hash = ((hash << 5) + hash + code) & 0x7fffffff;
  }
  return hash;
}

/// A stable accent color for [hostId], so hosts stay visually distinguishable
/// at a glance across the list. Pure — same [hostId] always yields the same
/// color, and the picked colors are drawn from a fixed palette rather than
/// generated ad hoc so they never clash with the M3 surface underneath.
Color hostAccentColor(String hostId) =>
    _hostAccentPalette[_stableHash(hostId) % _hostAccentPalette.length];

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

/// A single host's list row: icon, name, status dot + detail line, and a
/// trailing Wake button (offline hosts only) / ⋯ menu for the rest of the
/// actions.
///
/// Pings the host's `/health` on mount to determine online/offline state and,
/// when online, fetches `AgentClient.drives()` to know whether any drive is
/// low on space (gracefully skipped if the agent predates that endpoint).
class HostCard extends ConsumerStatefulWidget {
  const HostCard({
    super.key,
    required this.host,
    required this.store,
    this.isFirst = false,
  });

  final Host host;
  final HostStore store;

  /// Whether this is the first (most-recently-used) host in the list —
  /// renders as the big "focused" hero (icon badge, name, status, and an
  /// Open/Search/Transfers/Settings quick-action row) instead of the compact
  /// row the rest of the list uses.
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

  /// Fetches drives for the low-disk indicator. Returns an empty list on any
  /// error — including a 404 from agents that predate `/system/drives` — so a
  /// missing endpoint never produces an error state.
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

  /// Promotes this host to the hero slot (top of the list) without
  /// navigating anywhere — tapping a row under "Also paired" just brings
  /// that host to focus, it doesn't open it.
  Future<void> _promote() async {
    await widget.store.touchHost(widget.host.id);
    ref.invalidate(hostStoreProvider);
  }

  /// Opens the explorer for this host. If the most recent `/health` ping
  /// reported a Windows host, opens the drive list ([DrivesView]) first
  /// instead of a `/`-rooted listing, since `/` isn't a meaningful path on
  /// Windows. Any other (or unknown) OS keeps the existing `/`-rooted
  /// behaviour.
  Future<void> _openExplorer(BuildContext context) async {
    final health = await _pingFuture;
    if (!context.mounted) return;
    ref.read(activeHostProvider.notifier).state = ActiveHost(
      host: widget.host,
      health: health,
    );
    ref.read(selectedTabIndexProvider.notifier).state = 1;
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

  /// The host's action sheet (⋯ menu), restyled with the shared MetaSheet
  /// chrome: a [SheetHero] tinted [Brand.online]/[Brand.offline], a
  /// [QuickActionRow] for the most-used actions, and an [ActionListCard] for
  /// the rest. Replaces the old [PopupMenuButton] — same actions, same
  /// handlers, just presented as a sheet instead of a dropdown.
  void _openActions(BuildContext context, {required bool online}) {
    final l = context.l10n;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;

        void run(void Function(BuildContext) action) {
          Navigator.pop(sheetContext);
          action(context);
        }

        final quick = <GradientActionCircle>[
          if (online)
            GradientActionCircle(
              icon: LucideIcons.search,
              label: l.searchButton,
              gradient: [Colors.blue.shade400, Colors.blue.shade800],
              onTap: () => run(_openSearch),
            ),
          if (online)
            GradientActionCircle(
              icon: LucideIcons.hardDrive,
              label: l.storageMenuItem,
              gradient: [Colors.green.shade400, Colors.green.shade800],
              onTap: () => run(_openStorage),
            ),
          GradientActionCircle(
            icon: LucideIcons.settings,
            label: l.settingsMenuItem,
            gradient: [Colors.purple.shade300, Colors.purple.shade700],
            onTap: () => run(_openSettings),
          ),
          GradientActionCircle(
            icon: LucideIcons.userX,
            label: l.forgetComputerMenuItem,
            gradient: [Colors.red.shade400, Colors.red.shade800],
            onTap: () => run(_confirmRemove),
          ),
        ];

        return SafeArea(
          child: SingleChildScrollView(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: Radii.sheetTopR,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetHero(
                    badge: const Icon(LucideIcons.monitor),
                    tint: online ? Brand.online : Brand.offline,
                    title: widget.host.label,
                    subtitle:
                        '${online ? l.onlineStatus : l.offlineStatus} · '
                        '${widget.host.address}',
                    onClose: () => Navigator.pop(sheetContext),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      0,
                      Spacing.lg,
                      Spacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        QuickActionRow(actions: quick),
                        const SizedBox(height: Spacing.md),
                        ActionListCard(
                          children: [
                            ActionListTile(
                              icon: LucideIcons.arrowLeftRight,
                              label: l.transfersMenuItem,
                              onTap: () => run(_openTransfers),
                            ),
                            ActionListTile(
                              icon: LucideIcons.activity,
                              label: l.diagnosticsMenuItem,
                              onTap: () => run(_openDiagnostics),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Health?>(
      future: _pingFuture,
      builder: (context, snap) {
        final online = snap.data != null;
        final checking = snap.connectionState == ConnectionState.waiting;
        final canWake = !online && !checking && widget.host.macAddress != null;

        if (widget.isFirst) {
          return _buildHero(context, online: online);
        }

        // Thin list row for every host after the first — matches the Figma
        // mockup's simple row instead of the old dashboard-style card.
        // Dashboard-only content (uptime, per-drive gauges, full-width
        // action buttons) has been demoted to the Storage/Diagnostics
        // screens reachable from the ⋯ menu.
        return InkWell(
          onTap: _promote,
          onLongPress: () => _confirmRemove(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HostRowContent(
                  host: widget.host,
                  snapshot: snap,
                  checking: checking,
                  online: online,
                  isTailscaleActive: _isTailscaleActive,
                  lastChecked: _lastChecked,
                  lastSeen: _lastSeen,
                  drivesFuture: _drivesFuture,
                  lowDiskThresholdBytes:
                      ref
                          .watch(settingsProvider)
                          .valueOrNull
                          ?.app
                          .lowDiskThresholdBytes ??
                      0,
                ),
                if (canWake) ...[
                  const SizedBox(width: Spacing.sm),
                  IconButton.filledTonal(
                    icon: const Icon(LucideIcons.power, size: 18),
                    tooltip: context.l10n.wakeButton,
                    onPressed: () => _sendWol(context),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// The focused-host hero (Servers redesign v2): a flat tinted-border card —
  /// same recipe as [SettingsHero] — with a big icon badge, name/status, and
  /// an Open/Search/Transfers/Settings quick-action row so the most-recently-
  /// used PC's primary actions are one tap away instead of behind the ⋯ menu.
  Widget _buildHero(BuildContext context, {required bool online}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const tint = Colors.blue;

    Widget quickAction({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      return Expanded(
        child: Material(
          color: scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: Radii.smR,
          child: InkWell(
            onTap: onTap,
            borderRadius: Radii.smR,
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: tint),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _openExplorer(context),
      onLongPress: () => _confirmRemove(context),
      borderRadius: Radii.lgR,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.lgR,
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.22),
                    borderRadius: Radii.cardR,
                    boxShadow: [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(LucideIcons.monitor, size: 24, color: tint),
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
                              widget.host.label,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.moreVertical),
                            tooltip: context.l10n.moreTooltip,
                            onPressed:
                                () => _openActions(context, online: online),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _HostRowContent(
                          host: widget.host,
                          snapshot: AsyncSnapshot.withData(
                            ConnectionState.done,
                            null,
                          ),
                          checking: false,
                          online: online,
                          isTailscaleActive: _isTailscaleActive,
                          lastChecked: _lastChecked,
                          lastSeen: _lastSeen,
                          drivesFuture: null,
                          lowDiskThresholdBytes: 0,
                          showIdentity: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                quickAction(
                  icon: LucideIcons.folderOpen,
                  label: context.l10n.openButton,
                  onTap: () => _openExplorer(context),
                ),
                const SizedBox(width: Spacing.sm),
                quickAction(
                  icon: LucideIcons.search,
                  label: context.l10n.searchButton,
                  onTap: online ? () => _openSearch(context) : null,
                ),
                const SizedBox(width: Spacing.sm),
                quickAction(
                  icon: LucideIcons.arrowLeftRight,
                  label: context.l10n.transfersMenuItem,
                  onTap: () => _openTransfers(context),
                ),
                const SizedBox(width: Spacing.sm),
                quickAction(
                  icon: LucideIcons.settings,
                  label: context.l10n.settingsMenuItem,
                  onTap: () => _openSettings(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row content: icon chip, name (+ read-only / low-disk inline badges), and a
// single status/detail line.
// ---------------------------------------------------------------------------

class _HostRowContent extends StatelessWidget {
  const _HostRowContent({
    required this.host,
    required this.snapshot,
    required this.checking,
    required this.online,
    required this.isTailscaleActive,
    required this.lastChecked,
    required this.lastSeen,
    required this.drivesFuture,
    required this.lowDiskThresholdBytes,
    this.showIdentity = true,
  });

  final Host host;
  final AsyncSnapshot<Health?> snapshot;
  final bool checking;
  final bool online;
  final bool? isTailscaleActive;
  final DateTime? lastChecked;
  final DateTime? lastSeen;
  final Future<List<Drive>>? drivesFuture;
  final int lowDiskThresholdBytes;

  /// Whether to render the icon chip + host name. The hero card already
  /// renders its own big icon badge and name above this widget, so it passes
  /// `false` to get just the status line instead of a duplicate row.
  final bool showIdentity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final health = snapshot.data;
    final readOnly = online && health?.readOnly == true;

    // Offline hosts render dimmed to 60% opacity EXCEPT the host name, which
    // always stays fully legible.
    final dimmed = !online && !checking;
    Widget maybeDim(Widget child) =>
        dimmed ? Opacity(opacity: 0.6, child: child) : child;

    final iconChip = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hostAccentColor(host.id),
        borderRadius: Radii.chipR,
      ),
      child: const Icon(LucideIcons.monitor, color: Colors.white, size: 20),
    );

    final statusLine = maybeDim(
      checking
          ? Text(
            context.l10n.checkingStatus,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
          : Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? Brand.online : Brand.offline,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _statusWord(context),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              online
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(text: ' · ${_subtitle(context)}'),
                    ],
                  ),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
    );

    if (!showIdentity) {
      return statusLine;
    }

    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          maybeDim(iconChip),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        host.label,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (readOnly) ...[
                      const SizedBox(width: Spacing.xs),
                      Tooltip(
                        message: 'Read-only',
                        child: Icon(
                          LucideIcons.lock,
                          size: 14,
                          color: scheme.onSurfaceVariant,
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
                const SizedBox(height: 2),
                statusLine,
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusWord(BuildContext context) {
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

  /// "v1.1.0 · Tailscale" / "v1.1.0 · LAN" when online and we know which
  /// address is active; falls back to the raw address when offline or
  /// unknown.
  String _subtitle(BuildContext context) {
    final l = context.l10n;
    final health = snapshot.data;
    if (health != null) {
      final network =
          isTailscaleActive == true ? l.networkTailscale : l.networkLan;
      if (health.version.isEmpty) return network;
      return l.hostSubtitleVersionNetwork(health.version, network);
    }
    return host.address;
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

/// Small inline warning dot (replacing the old full-width low-disk banner)
/// shown next to the host name when any drive is under the configured
/// threshold. The full per-drive detail lives in [StorageInsightsScreen],
/// reachable from the row's ⋯ menu — the tooltip carries the same copy the
/// banner used to show.
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
            child: Icon(
              LucideIcons.triangleAlert,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
  }
}
