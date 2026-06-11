import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/health.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/update/update_service.dart';
import '../explorer/explorer_screen.dart';
import '../pairing/pairing_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/update_tile.dart';

/// Displays all paired hosts with online/offline indicators.
class HostListScreen extends ConsumerWidget {
  const HostListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(hostStoreProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final v = snap.data?.version;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Remote File Explorer'),
                if (v != null)
                  Text(
                    'v$v',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                  ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(hostStoreProvider),
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: storeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (store) {
          final hosts = store.listHosts();
          if (hosts.isEmpty) {
            return _EmptyState(scheme: scheme);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.md,
            ),
            itemCount: hosts.length,
            itemBuilder: (ctx, i) => AppearListItem(
              index: i,
              child: _HostCard(host: hosts[i], store: store, isFirst: i == 0),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add computer'),
        onPressed: () => _addComputer(context, ref),
      ),
    );
  }

  Future<void> _addComputer(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<Host>(
      MaterialPageRoute(builder: (_) => const PairingScreen()),
    );
    // Reload the host store after pairing
    ref.invalidate(hostStoreProvider);
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withValues(alpha: 0.5),
              ),
              child: Icon(
                Icons.computer_outlined,
                size: 44,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'No paired computers yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Tap “Add computer” to pair one over your network or Tailscale.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Host card with online/offline ping
// ---------------------------------------------------------------------------

class _HostCard extends ConsumerStatefulWidget {
  const _HostCard({
    required this.host,
    required this.store,
    this.isFirst = false,
  });

  final Host host;
  final HostStore store;

  /// Whether this is the first (most-recently-used) host — only that card
  /// kicks off the best-effort launch-time update check.
  final bool isFirst;

  @override
  ConsumerState<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends ConsumerState<_HostCard> {
  late Future<Health?> _pingFuture;

  /// Wall-clock time the most recent ping resolved, used only to render a
  /// gentle relative "last checked" line — purely cosmetic, doesn't affect the
  /// online/offline determination itself.
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _pingFuture = _ping();
    if (widget.isFirst && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeOfferUpdate(context);
      });
    }
  }

  /// Best-effort: check the host for a newer APK and show a dismissible banner.
  /// Swallows all errors so a missing/old agent never blocks the host list.
  Future<void> _maybeOfferUpdate(BuildContext context) async {
    if (!Platform.isAndroid) return;
    AgentClient? client;
    try {
      client = await buildClientForHost(ref.read, widget.host.id);
      final rel = await client.latestRelease();
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;
      if (!isUpdateAvailable(installedBuild: installed, release: rel)) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text('Update available → v${rel!.versionName}'),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UpdateScreen(host: widget.host),
                ));
              },
              child: const Text('Update'),
            ),
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Later'),
            ),
          ],
        ),
      );
    } catch (_) {
      // best-effort; never block the host list
    } finally {
      client?.close();
    }
  }

  Future<Health?> _ping() async {
    AgentClient? client;
    try {
      client = await buildClientForHost(ref.read, widget.host.id);
      final health = await client.health().timeout(const Duration(seconds: 5));
      await _learnAddresses(health);
      if (mounted) setState(() => _lastChecked = DateTime.now());
      return health;
    } catch (_) {
      if (mounted) setState(() => _lastChecked = DateTime.now());
      return null;
    } finally {
      client?.close();
    }
  }

  /// Adopts any LAN/Tailscale address the agent reports that we don't already
  /// know, so a host paired before Wave 2 (or paired only via one network)
  /// gradually learns to be reachable both at home and away.
  Future<void> _learnAddresses(Health health) async {
    final learnedTailscale = health.tailscaleAddress;
    if (learnedTailscale == null) return;
    if (learnedTailscale == widget.host.tailscaleAddress) return;
    if (learnedTailscale == widget.host.address) return;

    final updated = widget.host.copyWith(tailscaleAddress: learnedTailscale);
    await widget.store.addHost(updated);
  }

  Future<void> _openExplorer(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExplorerScreen(host: widget.host),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this computer?'),
        content: Text(
            'Remove "${widget.host.label}"? You can re-add it later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Forget')),
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
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        borderRadius: Radii.cardR,
        onTap: () => _openExplorer(context),
        onLongPress: () => _confirmRemove(context),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<Health?>(
                future: _pingFuture,
                builder: (context, snap) => _StatusDot(snapshot: snap),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.host.label,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.xs / 2),
                    Text(
                      widget.host.tailscaleAddress != null
                          ? '${widget.host.address}  ·  ${widget.host.tailscaleAddress} (Tailscale)'
                          : widget.host.address,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.sm),
                    FutureBuilder<Health?>(
                      future: _pingFuture,
                      builder: (context, snap) => _StatusLine(
                        snapshot: snap,
                        lastChecked: _lastChecked,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                shape: RoundedRectangleBorder(borderRadius: Radii.cardR),
                onSelected: (v) {
                  if (v == 'open') _openExplorer(context);
                  if (v == 'settings') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettingsScreen(host: widget.host),
                    ));
                  }
                  if (v == 'update') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => UpdateScreen(host: widget.host),
                    ));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                  const PopupMenuItem(value: 'settings', child: Text('Settings')),
                  if (Platform.isAndroid)
                    const PopupMenuItem(
                        value: 'update', child: Text('Check for updates')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status indicator: a small dot inside a tonal circle
// ---------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.snapshot});

  final AsyncSnapshot<Health?> snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (snapshot.connectionState == ConnectionState.waiting) {
      return Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
        ),
        child: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final online = snapshot.data != null;
    final dotColor = online ? Brand.online : Brand.offline;

    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor.withValues(alpha: 0.16),
      ),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dotColor,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status line: a colour pill ("Online"/"Offline"/"Checking…") plus a relative
// "last checked" hint.
// ---------------------------------------------------------------------------

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.snapshot, required this.lastChecked});

  final AsyncSnapshot<Health?> snapshot;
  final DateTime? lastChecked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (snapshot.connectionState == ConnectionState.waiting) {
      return _Pill(
        label: 'Checking…',
        color: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHighest,
      );
    }

    final online = snapshot.data != null;
    final pill = online
        ? _Pill(label: 'Online', color: Brand.online)
        : _Pill(label: 'Offline', color: Brand.offline);

    final relative = _relativeLastSeen(lastChecked);
    if (relative == null) return pill;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill,
        const SizedBox(width: Spacing.sm),
        Flexible(
          child: Text(
            online ? 'Checked $relative' : 'Last seen $relative',
            style: textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String? _relativeLastSeen(DateTime? at) {
    if (at == null) return null;
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// A small rounded status badge. [background] defaults to a tonal wash of
/// [color] so it reads consistently in both light and dark.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.background});

  final String label;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.16),
        borderRadius: Radii.chipR,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
