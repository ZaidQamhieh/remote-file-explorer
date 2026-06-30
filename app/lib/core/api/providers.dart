import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/host.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../storage/host_store.dart';
import 'agent_client.dart';

// ---------------------------------------------------------------------------
// Host lookup
// ---------------------------------------------------------------------------

/// Looks up a paired [Host] by [hostId] from the host store.
///
/// Returns `null` if no host with that id is paired (e.g. it was just
/// removed). `autoDispose` so a stale lookup doesn't linger after the screen
/// that needed it is gone.
final hostByIdProvider = FutureProvider.family.autoDispose<Host?, String>((
  ref,
  hostId,
) async {
  final store = await ref.watch(hostStoreProvider.future);
  final hosts = store.listHosts();
  for (final h in hosts) {
    if (h.id == hostId) return h;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Agent client
// ---------------------------------------------------------------------------

/// The shape shared by [Ref.read] (used inside providers) and [WidgetRef.read]
/// (used in widgets) — both are generic methods with this exact signature, but
/// `Ref` and `WidgetRef` have no common supertype in Riverpod 2.x. Accepting
/// this function type lets [buildClientForHost] be called from either context
/// by passing the `read` method tear-off.
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// Resolves the [Host] record and device token for [hostId] and constructs a
/// fresh [AgentClient].
///
/// This is the single store→token→client construction path used both by
/// [clientProvider] and by one-shot call sites that need a short-lived
/// client (e.g. a settings screen action or an update check). Those callers
/// own the returned client and should call [AgentClient.close] when done;
/// screens that need a client for their whole lifetime should prefer
/// watching [clientProvider] instead, which closes it automatically.
///
/// [read] is the `read` method tear-off from either a provider's [Ref] or a
/// widget's `WidgetRef` (e.g. `ref.read`).
///
/// Throws if [hostId] doesn't correspond to a paired host.
Future<AgentClient> buildClientForHost(
  RefReader read,
  String hostId, {
  bool probeLanFirst = false,
}) async {
  final host = await read(hostByIdProvider(hostId).future);
  if (host == null) {
    throw StateError('No paired host with id "$hostId"');
  }
  final store = await read(hostStoreProvider.future);
  final token = await store.getToken(hostId);
  final client = AgentClient(
    host,
    deviceToken: token,
    probeLanFirst: probeLanFirst,
  );
  final settings = read(settingsProvider).valueOrNull ?? const SettingsState();
  client.compressDownloadsOnCellular = settings.app.compressDownloadsOnCellular;
  return client;
}

/// Builds (and owns) an [AgentClient] for the host identified by [hostId].
///
/// Intended for screens that [Ref.watch] this continuously for their whole
/// lifetime (e.g. the explorer screen): the client is closed via
/// [AgentClient.close] when this provider is disposed (`autoDispose` — i.e.
/// once nothing watches it anymore). Do not [Ref.read] this for a one-shot
/// operation — with no watcher the provider (and its client) may be disposed
/// before the operation finishes. Use [buildClientForHost] for that instead.
///
/// Throws if [hostId] doesn't correspond to a paired host.
final clientProvider = FutureProvider.family.autoDispose<AgentClient, String>((
  ref,
  hostId,
) async {
  final client = await buildClientForHost(ref.read, hostId);
  ref.onDispose(client.close);
  return client;
});
