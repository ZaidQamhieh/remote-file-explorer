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
import '../../../core/ui/pressable.dart';
import '../../explorer/drives_view.dart';
import '../../explorer/explorer_screen.dart';
import '../../home/home_state.dart';
import '../../settings/settings_screen.dart';
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

/// A single host's row: icon-badge with a status dot, name/subtitle line, a
/// storage-usage bar when online, and a trailing gear button into
/// [SettingsScreen] — matches the mockup's Devices tab exactly (every host
/// renders as the same uniform rounded card; there is no more "hero" row for
/// the most-recently-used host).
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
  });

  final Host host;
  final HostStore store;

  /// Reports this host's online/offline state up to the parent list once
  /// known, so it can render the "N paired · N online now" header subtitle.
  /// Purely a display callback — doesn't affect the ping/health logic below.
  final ValueChanged<bool>? onOnlineChanged;

  @override
  ConsumerState<HostCard> createState() => _HostCardState();
}

class _HostCardState extends ConsumerState<HostCard> {
  late Future<Health?> _pingFuture;
  Future<List<Drive>>? _drivesFuture;

  /// Address the most recent successful client used — drives the "· Tailscale"
  /// subtitle suffix. `null` while unknown (offline / not yet pinged).
  bool? _isTailscaleActive;

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
          _isTailscaleActive = client!.isActiveAddressTailscale;
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
        return _CardBody(
          host: widget.host,
          health: snap.data,
          online: online,
          checking: checking,
          isTailscaleActive: _isTailscaleActive,
          lastSeen: _lastSeen,
          drivesFuture: _drivesFuture,
          lowDiskThresholdBytes:
              ref
                  .watch(settingsProvider)
                  .valueOrNull
                  ?.app
                  .lowDiskThresholdBytes ??
              0,
          onTap: () {
            if (online) {
              _openExplorer(context);
            } else if (widget.host.macAddress != null) {
              _sendWol(context);
            }
          },
          onLongPress: () => _confirmRemove(context),
          onSettingsTap: () => _openSettings(context),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Card body — rebuilt directly from the mockup's actual CSS (docs/mockup-
// reference/mockup.css): `.card` (background/1px border/r-lg/14px padding,
// no Material Card/elevation), `.avatar`+`.pulse-dot` (40x40 gradient box,
// r-md, with an 11x11 ring-bordered status dot overlapping its corner),
// `.row-title`/`.row-sub` (14px/500 and 11.5px sizes), `.progress` (5px
// full-round bar), and a trailing `.iconbtn` (34x34 circular tap target,
// online) or `.badge.neutral` pill (offline) — no ListTile/IconButton/
// ShadCard, no Material ripple (see [Pressable]).
// ---------------------------------------------------------------------------

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.host,
    required this.health,
    required this.online,
    required this.checking,
    required this.isTailscaleActive,
    required this.lastSeen,
    required this.drivesFuture,
    required this.lowDiskThresholdBytes,
    required this.onTap,
    required this.onLongPress,
    required this.onSettingsTap,
  });

  final Host host;
  final Health? health;
  final bool online;
  final bool checking;
  final bool? isTailscaleActive;
  final DateTime? lastSeen;
  final Future<List<Drive>>? drivesFuture;
  final int lowDiskThresholdBytes;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSettingsTap;

  /// `runtime.GOOS` as reported by `/health` ("windows"/"linux"/"darwin"),
  /// capitalized. The mockup shows a full OS+version string ("Windows 11",
  /// "Ubuntu 24.04") — the agent's `/health` endpoint only reports the bare
  /// OS name, no version, so that detail can't be shown without fabricating
  /// it.
  String? _osLabel() {
    final os = health?.os;
    if (os == null || os.isEmpty) return null;
    return os[0].toUpperCase() + os.substring(1);
  }

  String _subtitle(BuildContext context) {
    if (checking) return context.l10n.checkingStatus;
    if (!online) {
      return lastSeen != null
          ? context.l10n.statusOfflineLastSeen(_relative(context, lastSeen!))
          : context.l10n.offlineStatus;
    }
    final parts = <String>[host.address];
    final os = _osLabel();
    if (os != null) parts.add(os);
    if (isTailscaleActive == true) parts.add(context.l10n.networkTailscale);
    return parts.join(' · ');
  }

  String _relative(BuildContext context, DateTime at) {
    final l = context.l10n;
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 5) return l.relativeJustNow;
    if (diff.inMinutes < 1) return l.relativeSecondsAgo(diff.inSeconds);
    if (diff.inHours < 1) return l.relativeMinutesAgo(diff.inHours);
    if (diff.inDays < 1) return l.relativeHoursAgo(diff.inHours);
    return l.relativeDaysAgo(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readOnly = online && health?.readOnly == true;
    final dimmed = !online && !checking;
    final cardColor = scheme.surface;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Pressable(
        onTap: checking ? null : onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: Radii.cardR,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(online: online, checking: checking, cardColor: cardColor),
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
                            host.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (readOnly) ...[
                          const SizedBox(width: 4),
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
                    const SizedBox(height: 1),
                    Text(
                      _subtitle(context),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (online && drivesFuture != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: SizedBox(
                          width: 140,
                          child: _StorageBar(drivesFuture: drivesFuture!),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              if (online)
                _IconButton(
                  icon: LucideIcons.settings,
                  tooltip: context.l10n.settingsMenuItem,
                  onTap: onSettingsTap,
                )
              else
                _OfflineBadge(label: context.l10n.offlineStatus),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mockup's `.avatar`: a 40x40 `--r-md` gradient box (`--surface-3` to
/// `--surface-2`) with an icon, plus its `.pulse-dot`: an 11x11 circle
/// overlapping the bottom-right corner, ringed by a border matching the
/// surrounding card so it reads as a cutout rather than a solid dot on top.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.online,
    required this.checking,
    required this.cardColor,
  });

  final bool online;
  final bool checking;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor =
        checking
            ? scheme.outlineVariant
            : (online ? Brand.online : Brand.offline);
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surfaceContainerHighest,
                  scheme.surfaceContainerHigh,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              LucideIcons.monitor,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                border: Border.all(color: cardColor, width: 2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.iconbtn`: a bare 34x34 circular tap target, no fill, no
/// Material ripple — just the icon with [Pressable]'s scale-down feedback.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The mockup's `.badge.neutral` pill — replaces the gear button on offline
/// cards.
class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The mockup's `.progress`: a 5px, fully-rounded track+fill bar. Reuses
/// [aggregateUsage] (shared with [StorageInsightsScreen]) for the real
/// storage-usage figure; renders nothing while unresolved or when the agent
/// has no usable capacity data (e.g. predates `/system/drives`).
class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.drivesFuture});

  final Future<List<Drive>> drivesFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Drive>>(
      future: drivesFuture,
      builder: (context, snap) {
        final drives = snap.data;
        if (drives == null) return const SizedBox.shrink();
        final usage = aggregateUsage(drives);
        if (usage == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        // Amber past 70% used, matching the mockup's high-usage example.
        final fillColor = usage.usedFraction >= 0.7 ? Brand.amber : Brand.seed;
        return Container(
          height: 5,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: Radii.stadiumR,
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: usage.usedFraction.clamp(0, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: Radii.stadiumR,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small inline warning icon shown next to the host name when any drive is
/// under the configured threshold. Full per-drive detail lives in
/// [StorageInsightsScreen], reachable from the settings screen. Not part of
/// the mockup (which has no live drive data to show one for) — a real,
/// working addition rather than a fabricated one.
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
