import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
import '../explorer/explorer_screen.dart';
import '../explorer/explorer_state.dart' show explorerProvider;
import '../hosts/host_list_screen.dart';
import '../hosts/widgets/host_card.dart' show explorerRootFor;
import '../settings/app_settings_screen.dart';
import '../transfers/transfer_journal_screen.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_state.dart';
import 'home_state.dart';
import 'widgets/app_bottom_nav.dart';

/// Persistent 4-tab shell: Servers / Files / Transfers / Settings. Replaces
/// the old push-based flow where opening a host pushed [ExplorerScreen] on
/// top of [HostListScreen].
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabIndexProvider);
    final active = ref.watch(activeHostProvider);

    // Does the Files tab render ExplorerScreen rooted at '/' directly (not
    // DrivesView, which has no folder-depth/selection state of its own)?
    // Mirrors the windows check in `explorerRootFor`.
    final showsExplorerRoot =
        active != null &&
        (active.initialPath != null ||
            active.health?.os.toLowerCase() != 'windows');

    (bool atRoot, bool multiSelect)? explorer;
    if (showsExplorerRoot) {
      explorer = ref.watch(
        explorerProvider((
          hostId: active.host.id,
          rootPath: '/',
        )).select((s) => (s.atRoot, s.multiSelect)),
      );
    }

    final filesMultiSelect = shouldHideTabBar(
      selectedIndex: index,
      explorerMultiSelect: explorer?.$2 ?? false,
    );
    final returnToServersOnBack = shouldReturnToServersOnBack(
      selectedIndex: index,
      showsExplorerRoot: showsExplorerRoot,
      explorerAtRoot: explorer?.$1 ?? false,
      explorerMultiSelect: explorer?.$2 ?? false,
    );

    return PopScope(
      canPop: !returnToServersOnBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && returnToServersOnBack) {
          ref.read(selectedTabIndexProvider.notifier).state = 0;
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: const [
            HostListScreen(),
            _FilesTab(),
            _TransfersTab(),
            AppSettingsScreen(),
          ],
        ),
        bottomNavigationBar:
            filesMultiSelect
                ? null
                : AppBottomNav(
                  selectedIndex: index,
                  onDestinationSelected:
                      (i) =>
                          ref.read(selectedTabIndexProvider.notifier).state = i,
                  onAddPressed: () => HostListScreen.addComputer(context, ref),
                  destinations: const [
                    AppBottomNavDestination(
                      icon: LucideIcons.database,
                      label: 'Devices',
                    ),
                    AppBottomNavDestination(
                      icon: LucideIcons.folder,
                      selectedIcon: LucideIcons.folderOpen,
                      label: 'Files',
                    ),
                    AppBottomNavDestination(
                      icon: LucideIcons.activity,
                      label: 'Transfers',
                    ),
                    AppBottomNavDestination(
                      icon: LucideIcons.settings,
                      label: 'Settings',
                    ),
                  ],
                ),
      ),
    );
  }
}

/// Files tab body: an empty state until a host is picked from the Servers
/// tab (or a bookmark/intent sets [activeHostProvider]), then the same
/// drives-vs-explorer root [explorerRootFor] already picks for a direct push.
class _FilesTab extends ConsumerWidget {
  const _FilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeHostProvider);
    if (active == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.server,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              const Text('Select a server to browse its files'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed:
                    () => ref.read(selectedTabIndexProvider.notifier).state = 0,
                icon: const Icon(LucideIcons.server),
                label: const Text('Go to Devices'),
              ),
            ],
          ),
        ),
      );
    }
    final body =
        active.initialPath != null
            ? ExplorerScreen(host: active.host, initialPath: active.initialPath)
            : explorerRootFor(active.health, active.host);
    // Keyed on the ActiveHost instance (a fresh object every "open" action):
    // without this, re-selecting a different bookmark/host while this tab's
    // ExplorerScreen is already mounted only updates its widget properties
    // (didUpdateWidget), so ExplorerScreen's initState-only initialPath jump
    // never re-fires and the second navigation silently does nothing.
    return KeyedSubtree(key: ObjectKey(active), child: body);
  }
}

class _TransfersTab extends ConsumerWidget {
  const _TransfersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount =
        ref
            .watch(transferQueueProvider)
            .where(
              (t) =>
                  t.status == TransferStatus.running ||
                  t.status == TransferStatus.paused,
            )
            .length;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: ScreenHeader(
          'Transfers',
          subtitle: activeCount > 0 ? '$activeCount active' : null,
        ),
        actions: [
          _AppbarIconBtn(
            icon: LucideIcons.history,
            tooltip: 'Transfer history',
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TransferJournalScreen(),
                  ),
                ),
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: const Column(
        children: [
          TransferStatGrid(),
          Expanded(child: TransferGroupedList(showTitle: false)),
        ],
      ),
    );
  }
}

/// The mockup's `.iconbtn`: 34x34, 19px glyph — replaces a raw [IconButton]
/// in this tab's app bar actions.
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
