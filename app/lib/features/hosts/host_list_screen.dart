import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/agent_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/health.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
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
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.normal),
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
        ],
      ),
      body: storeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (store) {
          final hosts = store.listHosts();
          if (hosts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.computer_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'No paired computers yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to add a computer'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: hosts.length,
            itemBuilder: (ctx, i) =>
                _HostCard(host: hosts[i], store: store, isFirst: i == 0),
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
    try {
      final token = await widget.store.getToken(widget.host.id);
      final client = AgentClient(widget.host, deviceToken: token);
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
    }
  }

  Future<Health?> _ping() async {
    try {
      final token = await widget.store.getToken(widget.host.id);
      final client = AgentClient(widget.host, deviceToken: token);
      final health = await client.health().timeout(const Duration(seconds: 5));
      await _learnAddresses(health);
      return health;
    } catch (_) {
      return null;
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
    ref.read(activeHostProvider.notifier).setHost(widget.host);
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openExplorer(context),
        onLongPress: () => _confirmRemove(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _StatusIcon(pingFuture: _pingFuture),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.host.label,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      widget.host.tailscaleAddress != null
                          ? '${widget.host.address}  ·  ${widget.host.tailscaleAddress} (Tailscale)'
                          : widget.host.address,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
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

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.pingFuture});
  final Future<Health?> pingFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Health?>(
      future: pingFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final online = snap.data != null;
        return Icon(
          online ? Icons.circle : Icons.circle_outlined,
          color: online ? Colors.green : Theme.of(context).colorScheme.outline,
          size: 14,
        );
      },
    );
  }
}
