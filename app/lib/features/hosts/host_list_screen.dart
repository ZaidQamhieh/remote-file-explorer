import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/gradient_button.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/screen_header.dart';
import '../handoff/qr_scan_screen.dart';
import '../pairing/pairing_screen.dart';
import '../settings/update_banner.dart';
import 'widgets/host_card.dart';

/// Displays every paired host as a flat list of uniform [HostCard] rows —
/// matches the mockup's Devices tab exactly: no "hero" row for the most-
/// recently-used host, just one card style throughout.
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
  bool _showSearch = false;

  /// Online/offline state reported up by each [HostCard] once its `/health`
  /// ping resolves, used only to render the "N paired · N online now"
  /// subtitle — doesn't affect the ping logic itself, which stays entirely
  /// inside [HostCard].
  final Map<String, bool> _online = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reportOnline(String hostId, bool online) {
    if (_online[hostId] == online) return;
    setState(() => _online[hostId] = online);
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(hostStoreProvider);
    final scheme = Theme.of(context).colorScheme;
    final hostCount = storeAsync.valueOrNull?.listHosts().length ?? 0;
    final onlineCount =
        storeAsync.valueOrNull
            ?.listHosts()
            .where((h) => _online[h.id] == true)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: ScreenHeader(
          'Devices',
          subtitle:
              hostCount > 0
                  ? '$hostCount paired · $onlineCount online now'
                  : null,
        ),
        actions: [
          _AppbarIconBtn(
            icon: _showSearch ? LucideIcons.x : LucideIcons.search,
            tooltip: context.l10n.searchButton,
            onTap: () => setState(() => _showSearch = !_showSearch),
          ),
          _AppbarIconBtn(
            icon: LucideIcons.scanQrCode,
            tooltip: context.l10n.receiveFileTooltip,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const QrScanScreen()),
                ),
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
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
                      Spacing.md,
                      Spacing.sm,
                      Spacing.md,
                      Spacing.xl * 2,
                    ),
                    children: [
                      for (int i = 0; i < hosts.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        AppearListItem(
                          index: i,
                          child: HostCard(
                            key: ValueKey(hosts[i].id),
                            host: hosts[i],
                            store: store,
                            onOnlineChanged:
                                (online) => _reportOnline(hosts[i].id, online),
                          ),
                        ),
                      ],
                      const SizedBox(height: Spacing.md),
                      const SectionLabel('This device'),
                      // The mockup's "Show my pairing code" button implies
                      // this phone displays a code for a PC to scan — but
                      // this app's actual TOFU pairing flow runs the other
                      // way (the agent mints the code, the phone scans it;
                      // see `agent pair` in CLAUDE.md). There's no real
                      // "phone shows its own code" flow to wire this to, so
                      // it opens the existing add-a-computer pairing flow
                      // instead of fabricating a fake code display.
                      _GhostButton(
                        icon: LucideIcons.qrCode,
                        label: 'Show my pairing code',
                        onTap: () => HostListScreen.addComputer(context, ref),
                      ),
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
// Persistent search field — filters the list in place, no navigation. Built
// directly from the mockup's `.searchbar` rule (docs/mockup-reference/
// mockup.css): flat pill, 1px border, 9/14 padding, 13.5px text — no
// ShadInput.
// ---------------------------------------------------------------------------

class _DeviceSearchBar extends StatelessWidget {
  const _DeviceSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: Radii.stadiumR,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search devices…',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.iconbtn`: bare 34x34 circular tap target, 19px icon, no
/// fill, no Material ripple ([Pressable]'s scale-down instead).
class _AppbarIconBtn extends StatelessWidget {
  const _AppbarIconBtn({
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
        pressedScale: 0.92,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The mockup's `.btn` + `.btn-ghost`: 1px bordered pill, `surface-2` fill,
/// 13.5px/600 label — no `OutlinedButton`.
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: Radii.smR,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: scheme.onSurface),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — "pair your first PC" hero. Not shown in the mockup (its
// Devices tab always has 3 mock hosts), so this keeps the existing hero
// rather than inventing a design that isn't specified anywhere.
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
            const GradientBlobHero(icon: LucideIcons.monitor, size: 120),
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
            GradientButton(
              onPressed: onScan,
              icon: const Icon(LucideIcons.scanQrCode),
              child: Text(context.l10n.scanQrCodeButton),
            ),
          ],
        ),
      ),
    );
  }
}
