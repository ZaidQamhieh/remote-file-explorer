import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  destinations: const [
                    AppBottomNavDestination(
                      icon: Icons.dns_outlined,
                      selectedIcon: Icons.dns_rounded,
                      label: 'Servers',
                    ),
                    AppBottomNavDestination(
                      icon: Icons.folder_outlined,
                      selectedIcon: Icons.folder_rounded,
                      label: 'Files',
                    ),
                    AppBottomNavDestination(
                      icon: Icons.swap_vert_rounded,
                      label: 'Transfers',
                    ),
                    AppBottomNavDestination(
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings_rounded,
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
      return const Scaffold(
        body: Center(child: Text('Select a server from the Servers tab')),
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
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Transfer history',
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TransferJournalScreen(),
                  ),
                ),
          ),
        ],
      ),
      body: const TransferGroupedList(showTitle: false),
    );
  }
}
