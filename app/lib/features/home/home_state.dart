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
