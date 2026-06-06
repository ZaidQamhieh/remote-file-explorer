import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/host.dart';
import '../storage/host_store.dart';
import 'agent_client.dart';

// ---------------------------------------------------------------------------
// Active host
// ---------------------------------------------------------------------------

/// Holds the currently active [Host] (set when the user taps a host card).
class ActiveHostNotifier extends Notifier<Host?> {
  @override
  Host? build() => null;

  void setHost(Host? host) => state = host;
}

final activeHostProvider = NotifierProvider<ActiveHostNotifier, Host?>(
  ActiveHostNotifier.new,
);

// ---------------------------------------------------------------------------
// Active client
// ---------------------------------------------------------------------------

/// An [AgentClient] for the currently active host. Returns null when no host
/// is selected or when the host store hasn't loaded yet.
final activeClientProvider = FutureProvider<AgentClient?>((ref) async {
  final host = ref.watch(activeHostProvider);
  if (host == null) return null;

  final store = await ref.watch(hostStoreProvider.future);
  final token = await store.getToken(host.id);

  return AgentClient(host, deviceToken: token);
});
