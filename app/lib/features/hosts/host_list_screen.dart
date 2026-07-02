import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/grouped_card.dart';
import '../handoff/qr_scan_screen.dart';
import '../home/home_state.dart';
import '../pairing/pairing_screen.dart';
import '../search/cross_host_search_screen.dart';
import '../settings/update_banner.dart';
import 'mdns_discovery.dart';
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
                Text(context.l10n.appTitle),
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
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: context.l10n.receiveFileTooltip,
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const QrScanScreen()),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search all hosts',
            onPressed: () {
              final store = storeAsync.valueOrNull;
              if (store == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (_) => CrossHostSearchScreen(hosts: store.listHosts()),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.l10n.refreshTooltip,
            onPressed: () => ref.invalidate(hostStoreProvider),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.appSettingsTooltip,
            onPressed:
                () => ref.read(selectedTabIndexProvider.notifier).state = 3,
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
              error:
                  (e, _) => Center(child: Text(context.l10n.errorLabel('$e'))),
              data: (store) {
                final hosts = store.listHosts();
                if (hosts.isEmpty) {
                  return _EmptyState(
                    scheme: scheme,
                    onScan: () => _addComputer(context, ref),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(hostStoreProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.md,
                    ),
                    children: [
                      _DiscoveredHostsSection(
                        pairedAddresses: hosts.map((h) => h.address).toSet(),
                        onAdd:
                            (address) => _addComputer(
                              context,
                              ref,
                              prefillAddress: address,
                            ),
                      ),
                      const SectionLabel('Your computers'),
                      GroupedCard(
                        padded: false,
                        children: [
                          for (int i = 0; i < hosts.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                indent: Spacing.md,
                                endIndent: Spacing.md,
                                color: scheme.outlineVariant,
                              ),
                            AppearListItem(
                              index: i,
                              child: HostCard(
                                host: hosts[i],
                                store: store,
                                isFirst: i == 0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.addComputerButton),
        onPressed: () => _addComputer(context, ref),
      ),
    );
  }

  Future<void> _addComputer(
    BuildContext context,
    WidgetRef ref, {
    String? prefillAddress,
  }) async {
    await Navigator.of(context).push<Host>(
      MaterialPageRoute(
        builder: (_) => PairingScreen(prefillAddress: prefillAddress),
      ),
    );
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
              context.l10n.emptyStatePairTitle,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              context.l10n.emptyStatePairBody,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(context.l10n.scanQrCodeButton),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discovered agents section — mDNS `_rfe._tcp`
// ---------------------------------------------------------------------------

class _DiscoveredHostsSection extends ConsumerWidget {
  const _DiscoveredHostsSection({
    required this.pairedAddresses,
    required this.onAdd,
  });

  final Set<String> pairedAddresses;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovered = ref.watch(mdnsDiscoveryProvider);
    return discovered.when(
      data: (agents) {
        final unpaired =
            agents
                .where((a) => !pairedAddresses.contains(a.hostAddress))
                .toList();
        if (unpaired.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.xs,
              ),
              child: Text(
                'Discovered on network',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final agent in unpaired)
              ListTile(
                leading: const Icon(Icons.computer_rounded),
                title: Text(agent.name),
                subtitle: Text(agent.hostAddress),
                trailing: FilledButton.tonal(
                  onPressed: () => onAdd(agent.hostAddress),
                  child: const Text('Add'),
                ),
              ),
            const Divider(),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
