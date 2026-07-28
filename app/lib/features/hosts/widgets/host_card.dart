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
import '../../../core/ui/format.dart';
import '../../../core/ui/pressable.dart';
import '../../explorer/drives_view.dart';
import '../../explorer/explorer_screen.dart';
import '../../home/home_state.dart';
import '../../settings/settings_screen.dart';
import 'hero_ring.dart';
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
/// storage-usage bar when online, and a trailing overflow-menu kebab into
/// [SettingsScreen]/forget — matches the confirmed "Floating profile" Devices
/// mockup (`wiki/entities/remote-file-explorer.md`, 2026-07-23).
///
/// When [isHero] is true, the same ping/health/drives state instead feeds
/// [_HeroCardBody] — the confirmed "Circular Orbit" hero shell — for the
/// first (most-recently-paired) host in the list. Every network call and tap
/// handler is shared between the two shells; only the outer visuals differ.
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

  /// Renders the confirmed "Circular Orbit" hero shell instead of the
  /// regular row. Set by [HostListScreen] for the first host only.
  final bool isHero;

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

  /// Switches to the Transfers tab (index 2, see [selectedTabIndexProvider]'s
  /// doc comment) — the hero shell's "Transfers" cardinal action.
  void _openTransfers() {
    ref.read(selectedTabIndexProvider.notifier).state = 2;
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
        if (widget.isHero) {
          return _HeroCardBody(
            host: widget.host,
            online: online,
            checking: checking,
            drivesFuture: _drivesFuture,
            onOpen: onTap,
            onSettingsTap: () => _openSettings(context),
            onTransfersTap: _openTransfers,
            onRefresh: () => setState(() => _pingFuture = _ping()),
            onForget: () => _confirmRemove(context),
          );
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
          onTap: onTap,
          onLongPress: () => _confirmRemove(context),
          onSettingsTap: () => _openSettings(context),
          onForget: () => _confirmRemove(context),
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
    required this.onForget,
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
  final VoidCallback onForget;

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
          // Mockup `.row.flt`: diagonal gradient + drop shadow for visual
          // weight (owner: "too plain"). Ported as theme-relative surface
          // tones rather than the mockup's fixed dark hex, so it still reads
          // correctly in light theme.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.surfaceContainerHigh, cardColor],
            ),
            borderRadius: Radii.cardR,
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: .25),
                offset: const Offset(0, 6),
                blurRadius: 14,
              ),
            ],
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
                        child: _StorageBar(drivesFuture: drivesFuture!),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              _KebabMenu(
                onSettingsTap: onSettingsTap,
                onForgetTap: onForget,
                vertical: true,
                dimmed: !online,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mockup's `.flt-badge`: a 38x38 circular blue-tinted badge that bobs
/// continuously while online (`floatY`, 2.4s ease-in-out), plus `.flt-led`:
/// a 9x9 corner dot that glows via a pulsing box-shadow (`floatLedGlow`,
/// 2.2s) while online. Both animations stop and the badge/dot mute to grey
/// when offline or still checking.
class _Avatar extends StatefulWidget {
  const _Avatar({
    required this.online,
    required this.checking,
    required this.cardColor,
  });

  final bool online;
  final bool checking;
  final Color cardColor;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animate = widget.online && !widget.checking;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final bob = animate ? -6 * Curves.easeInOut.transform(_c.value) : 0.0;
        return Transform.translate(offset: Offset(0, bob), child: child);
      },
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    animate
                        ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Brand.seed.withValues(alpha: .32),
                            Brand.seed.withValues(alpha: .08),
                          ],
                        )
                        : null,
                color:
                    animate
                        ? null
                        : scheme.onSurfaceVariant.withValues(alpha: .14),
                border: Border.all(
                  color:
                      animate
                          ? Brand.seed.withValues(alpha: .35)
                          : scheme.onSurfaceVariant.withValues(alpha: .22),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.cloud,
                size: 18,
                color: animate ? Brand.seed : scheme.onSurfaceVariant,
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: _PresenceDot(
                cardColor: widget.cardColor,
                checking: widget.checking,
                animate: animate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceDot extends StatefulWidget {
  const _PresenceDot({
    required this.cardColor,
    required this.checking,
    required this.animate,
  });

  final Color cardColor;
  final bool checking;
  final bool animate;

  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        widget.checking
            ? scheme.outlineVariant
            : (widget.animate ? Brand.online : Brand.offline);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final glow = widget.animate ? _c.value : 0.0;
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: widget.cardColor, width: 1.5),
            boxShadow:
                widget.animate
                    ? [
                      BoxShadow(
                        color: Brand.online.withValues(alpha: .6),
                        blurRadius: 4 + glow * 6,
                        spreadRadius: glow * 3,
                      ),
                    ]
                    : null,
          ),
        );
      },
    );
  }
}

/// The confirmed "Circular Orbit" hero shell (`wiki/entities/remote-file-
/// explorer.md`, 2026-07-23): a slow-spinning dashed ring ([HeroOrbitRing])
/// around a center plate ([_Avatar] + name + status), with 4 real actions —
/// Open, Transfers, Settings, Refresh — at the ring's cardinal points
/// ([HeroActionRing]), plus a static overflow kebab top-right.
///
/// Rendered for the first (most-recently-paired) host only; every other host
/// still renders as the regular [_CardBody] row. Shares its parent
/// [_HostCardState]'s ping/health/drives state — this widget adds no network
/// calls of its own.
class _HeroCardBody extends StatelessWidget {
  const _HeroCardBody({
    required this.host,
    required this.online,
    required this.checking,
    required this.drivesFuture,
    required this.onOpen,
    required this.onSettingsTap,
    required this.onTransfersTap,
    required this.onRefresh,
    required this.onForget,
  });

  final Host host;
  final bool online;
  final bool checking;
  final Future<List<Drive>>? drivesFuture;
  final VoidCallback onOpen;
  final VoidCallback onSettingsTap;
  final VoidCallback onTransfersTap;
  final VoidCallback onRefresh;
  final VoidCallback onForget;

  /// "N% used" once drive usage resolves; otherwise a plain online/offline/
  /// checking word. There's no real "battery"-style percentage for a PC, so
  /// unlike the original mockup's placeholder "43%" this always ties to an
  /// actual number when one is available.
  Widget _statusLine(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (checking) {
      return Text(
        context.l10n.checkingStatus,
        style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
      );
    }
    if (!online || drivesFuture == null) {
      return Text(
        online ? context.l10n.onlineStatus : context.l10n.offlineStatus,
        style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
      );
    }
    return FutureBuilder<List<Drive>>(
      future: drivesFuture,
      builder: (context, snap) {
        final usage =
            snap.data == null ? null : aggregateUsage(snap.data!);
        final label =
            usage == null
                ? context.l10n.onlineStatus
                : '${(usage.usedFraction * 100).round()}% used';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.online,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const ringDiameter = 130.0;
    const plateDiameter = 76.0;
    return Padding(
      padding: const EdgeInsets.all(Spacing.md2),
      child: SizedBox(
        // Tall enough to contain HeroActionRing's own box (2×76 + 68) — a
        // shorter parent constrains it back down and the top/bottom actions
        // land outside it again, which makes them untappable.
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const HeroOrbitRing(diameter: ringDiameter),
            Container(
              width: plateDiameter,
              height: plateDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerLow,
              ),
              alignment: Alignment.center,
              child: Pressable(
                onTap: checking ? null : onOpen,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Avatar(online: online, checking: checking, cardColor: scheme.surfaceContainerLow),
                    const SizedBox(height: 5),
                    Text(
                      host.label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    _statusLine(context),
                  ],
                ),
              ),
            ),
            HeroActionRing(
              radius: 76,
              actions: [
                _HeroAction(
                  icon: LucideIcons.folderOpen,
                  label: context.l10n.openButton,
                  onTap: checking ? null : onOpen,
                ),
                _HeroAction(
                  icon: LucideIcons.arrowLeftRight,
                  label: context.l10n.transfersMenuItem,
                  onTap: onTransfersTap,
                ),
                _HeroAction(
                  icon: LucideIcons.settings,
                  label: context.l10n.settingsMenuItem,
                  onTap: onSettingsTap,
                ),
                _HeroAction(
                  icon: LucideIcons.refreshCw,
                  label: context.l10n.refreshTooltip,
                  onTap: checking ? null : onRefresh,
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: _KebabMenu(
                onSettingsTap: onSettingsTap,
                onForgetTap: onForget,
                vertical: false,
                dimmed: !online,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the hero ring's 4 cardinal actions: icon over a small label,
/// matching the mockup's `.act` — no fill, [Pressable]'s scale-down for
/// feedback instead of Material ripple.
class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: scheme.primary),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: .85),
              ),
            ),
          ],
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              height: 4,
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
            ),
            const SizedBox(height: 3),
            Text(
              '${formatSize(usage.totalBytes - usage.freeBytes)} / '
              '${formatSize(usage.totalBytes)}',
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
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
      child: _DotsChip(vertical: vertical, dimmed: dimmed),
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
