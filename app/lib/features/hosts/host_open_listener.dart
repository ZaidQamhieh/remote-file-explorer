/// Tasker / automation hook: jump straight to a paired host's explorer
/// screen via the native `OPEN_HOST` intent action (see MainActivity.kt's
/// `actionOpenHost`).
///
/// [HostOpenListener] wraps the app's `home` widget and, once mounted:
///  - pulls `getInitialHostId` over the `rfe/intents` channel for a cold
///    start (the app was launched directly by the intent);
///  - listens for `openHost` calls pushed from native for a warm start (app
///    already running, intent delivered via `onNewIntent`).
///
/// Mirrors [ShareIntakeListener]'s pull-for-cold-start / push-for-warm-start
/// split: a method-channel call pushed from native before the Dart-side
/// handler is registered is dropped, not queued, so cold start must be a
/// pull instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/ui/feedback.dart';
import '../home/home_state.dart';

/// Returns the [Host] in [hosts] whose `id` is [hostId], or `null` if it's
/// not paired (or was removed since the intent was sent).
Host? resolveHostById(List<Host> hosts, String hostId) {
  for (final host in hosts) {
    if (host.id == hostId) return host;
  }
  return null;
}

class HostOpenListener extends ConsumerStatefulWidget {
  const HostOpenListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<HostOpenListener> createState() => _HostOpenListenerState();
}

class _HostOpenListenerState extends ConsumerState<HostOpenListener> {
  static const _channel = MethodChannel('rfe/intents');

  @override
  void initState() {
    super.initState();

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openHost') {
        await _openHost(call.arguments as String?);
      }
    });

    // Cold start: the app was launched via the OPEN_HOST intent. Defer to
    // after the first frame so navigatorKey.currentContext is available.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hostId = await _channel.invokeMethod<String>('getInitialHostId');
      if (hostId != null) {
        await _openHost(hostId);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _openHost(String? hostId) async {
    if (hostId == null) return;

    final context = widget.navigatorKey.currentContext;
    if (context == null) return;

    final store = await ref.read(hostStoreProvider.future);
    final host = resolveHostById(store.listHosts(), hostId);

    if (host == null) {
      if (!context.mounted) return;
      showInfo(context, 'Host not found — was it unpaired?');
      ref.read(selectedTabIndexProvider.notifier).state = 0;
      return;
    }

    ref.read(activeHostProvider.notifier).state = ActiveHost(host: host);
    ref.read(selectedTabIndexProvider.notifier).state = 1;
  }
}
