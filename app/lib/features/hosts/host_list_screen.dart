import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../pairing/pairing_screen.dart';
import '../settings/app_settings_screen.dart';
import '../settings/update_banner.dart';
import 'widgets/host_card.dart';

/// Displays all paired hosts as a dashboard of [HostCard]s.
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(hostStoreProvider),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'App settings',
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AppSettingsScreen(),
                  ),
                ),
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(
            child: storeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (store) {
                final hosts = store.listHosts();
                if (hosts.isEmpty) {
                  return _EmptyState(
                    scheme: scheme,
                    onScan: () => _addComputer(context, ref),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.md,
                  ),
                  itemCount: hosts.length,
                  itemBuilder:
                      (ctx, i) => AppearListItem(
                        index: i,
                        child: HostCard(
                          host: hosts[i],
                          store: store,
                          isFirst: i == 0,
                        ),
                      ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add computer'),
        onPressed: () => _addComputer(context, ref),
      ),
    );
  }

  Future<void> _addComputer(BuildContext context, WidgetRef ref) async {
    await Navigator.of(
      context,
    ).push<Host>(MaterialPageRoute(builder: (_) => const PairingScreen()));
    // Reload the host store after pairing
    ref.invalidate(hostStoreProvider);
  }
}

// ---------------------------------------------------------------------------
// Empty state — "pair your first PC" hero
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme, required this.onScan});

  final ColorScheme scheme;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              child: Icon(
                Icons.devices_rounded,
                size: 56,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Pair your first PC',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Scan the pairing QR code shown by the desktop agent to connect '
              'this phone over your network or Tailscale.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR code'),
            ),
          ],
        ),
      ),
    );
  }
}
