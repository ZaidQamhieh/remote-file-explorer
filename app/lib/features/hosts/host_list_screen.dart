import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/ui/feedback.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/screen_header.dart';
import '../handoff/qr_scan_screen.dart';
import '../pairing/pairing_screen.dart';
import '../settings/update_banner.dart';
import 'widgets/host_card.dart';

/// Displays all paired hosts as a dashboard of [HostCard]s.
class HostListScreen extends ConsumerStatefulWidget {
  const HostListScreen({super.key});

  @override
  ConsumerState<HostListScreen> createState() => _HostListScreenState();

  /// Pushes the pairing flow and reloads the host store on return. Public
  /// (and static) so the persistent bottom nav's center Add button — shared
  /// across all 4 tabs, not just this screen — can trigger the same flow.
  static Future<void> addComputer(
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

class _HostListScreenState extends ConsumerState<HostListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(hostStoreProvider);
    final scheme = Theme.of(context).colorScheme;
    final hostCount = storeAsync.valueOrNull?.listHosts().length ?? 0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: ScreenHeader(
          'Devices',
          subtitle:
              hostCount > 0
                  ? '$hostCount computer${hostCount == 1 ? '' : 's'}'
                  : null,
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.l10n.refreshTooltip,
            onPressed: () => ref.invalidate(hostStoreProvider),
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.sm,
            ),
            child: _DeviceSearchBar(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const UpdateBanner(),
          Expanded(
            child: storeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (e, _) => Center(
                    child: Text(context.l10n.errorLabel(humanizeError(e))),
                  ),
              data: (store) {
                final allHosts = store.listHosts();
                if (allHosts.isEmpty) {
                  return _EmptyState(
                    scheme: scheme,
                    onScan: () => HostListScreen.addComputer(context, ref),
                  );
                }
                final query = _query.trim().toLowerCase();
                final hosts =
                    query.isEmpty
                        ? allHosts
                        : allHosts
                            .where(
                              (h) =>
                                  h.label.toLowerCase().contains(query) ||
                                  h.address.toLowerCase().contains(query),
                            )
                            .toList();
                if (hosts.isEmpty) {
                  return Center(
                    child: Text(
                      'No devices match "$_query"',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(hostStoreProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.sm,
                      Spacing.md,
                      Spacing.sm,
                      Spacing.xl * 2,
                    ),
                    children: [
                      AppearListItem(
                        index: 0,
                        child: HostCard(
                          key: ValueKey(hosts[0].id),
                          host: hosts[0],
                          store: store,
                          isFirst: true,
                        ),
                      ),
                      if (hosts.length > 1) ...[
                        const SizedBox(height: Spacing.md),
                        SectionLabel('Also paired · ${hosts.length - 1}'),
                        GroupedCard(
                          padded: false,
                          children: [
                            for (int i = 1; i < hosts.length; i++) ...[
                              if (i > 1)
                                Divider(
                                  height: 1,
                                  indent: Spacing.md,
                                  endIndent: Spacing.md,
                                  color: scheme.outlineVariant,
                                ),
                              AppearListItem(
                                index: i,
                                child: HostCard(
                                  key: ValueKey(hosts[i].id),
                                  host: hosts[i],
                                  store: store,
                                  isFirst: false,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Persistent search field — filters the list in place, no navigation
// ---------------------------------------------------------------------------

class _DeviceSearchBar extends StatelessWidget {
  const _DeviceSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShadInput(
      controller: controller,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      placeholder: Text(
        'Search devices…',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: scheme.outline),
      ),
      leading: Padding(
        padding: const EdgeInsets.only(left: Spacing.sm),
        child: Icon(Icons.search_rounded, size: 18, color: scheme.outline),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.md,
      ),
      decoration: ShadDecoration(
        color: scheme.surfaceContainerHigh,
        border: ShadBorder.all(color: Colors.transparent, radius: Radii.lgR),
        focusedBorder: ShadBorder.all(
          color: Colors.transparent,
          radius: Radii.lgR,
        ),
      ),
    );
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
