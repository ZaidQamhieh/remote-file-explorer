import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/health.dart';
import '../../core/models/host.dart';

/// Index of the selected [HomeShell] bottom-nav tab
/// (0 = Servers, 1 = Files, 2 = Transfers, 3 = Settings).
final selectedTabIndexProvider = StateProvider<int>((ref) => 0);

/// The host currently browsed in the Files tab, the path to jump to on open
/// (set by a bookmark), and the last-known [Health] ping (picks the drive
/// list vs a `/`-rooted listing for Windows hosts — see [explorerRootFor]).
/// Null means no host has been opened yet — the Files tab shows an empty
/// state.
class ActiveHost {
  const ActiveHost({required this.host, this.health, this.initialPath});

  final Host host;
  final Health? health;
  final String? initialPath;
}

final activeHostProvider = StateProvider<ActiveHost?>((ref) => null);

/// Whether [HomeShell]'s own bottom tab bar should be hidden. ExplorerScreen
/// nests its own Scaffold (SelectionBar as *its* bottomNavigationBar) inside
/// HomeShell's body, so multi-select would otherwise show two bottom bars
/// stacked.
bool shouldHideTabBar({
  required int selectedIndex,
  required bool explorerMultiSelect,
}) => selectedIndex == 1 && explorerMultiSelect;

/// Whether a system back-press on [HomeShell] should return to the Servers
/// tab (index 0) instead of letting the pop through. The Files/Transfers/
/// Settings tabs no longer live behind their own pushed route — they're
/// nested directly in HomeShell's IndexedStack, sharing its single route —
/// so once a tab has nothing left of its own to intercept, a back-press
/// would otherwise pop the app's *only* route and exit it. Only deferred to
/// ExplorerScreen's own PopScope when it's mid-navigation (not at folder
/// root) or mid-multi-select — both cases it already handles itself.
bool shouldReturnToServersOnBack({
  required int selectedIndex,
  required bool showsExplorerRoot,
  bool explorerAtRoot = false,
  bool explorerMultiSelect = false,
}) {
  if (selectedIndex == 0) return false;
  if (selectedIndex != 1) return true;
  if (!showsExplorerRoot) return true;
  return explorerAtRoot && !explorerMultiSelect;
}
