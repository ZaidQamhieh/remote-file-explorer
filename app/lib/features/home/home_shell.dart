import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../explorer/explorer_screen.dart';
import '../hosts/host_list_screen.dart';
import '../hosts/widgets/host_card.dart' show explorerRootFor;
import '../settings/app_settings_screen.dart';
import '../transfers/transfer_journal_screen.dart';
import '../transfers/transfer_manager.dart';
import 'home_state.dart';

/// Persistent 4-tab shell: Servers / Files / Transfers / Settings. Replaces
/// the old push-based flow where opening a host pushed [ExplorerScreen] on
/// top of [HostListScreen].
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabIndexProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          HostListScreen(),
          _FilesTab(),
          _TransfersTab(),
          AppSettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected:
            (i) => ref.read(selectedTabIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: 'Servers',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_rounded),
            label: 'Transfers',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
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
    if (active.initialPath != null) {
      return ExplorerScreen(host: active.host, initialPath: active.initialPath);
    }
    return explorerRootFor(active.health, active.host);
  }
}

class _TransfersTab extends StatelessWidget {
  const _TransfersTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
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
