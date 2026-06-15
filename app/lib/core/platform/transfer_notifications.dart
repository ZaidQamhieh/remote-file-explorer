import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/transfers/transfer_state.dart';

/// Bridge between the in-app transfer queue and an Android **foreground
/// service** + notification, so transfers keep running when the app is
/// backgrounded and the user sees live progress.
///
/// The actual transfer work stays in Dart (the existing engine in
/// `transfer_state.dart`); this only keeps the process alive via a foreground
/// service and mirrors aggregate progress into its ongoing notification,
/// posting a one-off completion notification when the queue drains. Pause /
/// resume / cancel remain the in-app controls (swipe actions in the transfers
/// center).
///
/// All platform calls are best-effort: on non-Android platforms, in tests, or
/// before the native side is registered they no-op (MissingPluginException is
/// swallowed), so this is safe to wire unconditionally.
class TransferNotifications {
  TransferNotifications([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('rfe/transfers');

  final MethodChannel _channel;
  bool _serviceRunning = false;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Reconciles the foreground service + notification with the current [tasks].
  void sync(List<TransferTask> tasks) {
    if (!_supported) return;

    final active =
        tasks
            .where(
              (t) =>
                  t.status == TransferStatus.running ||
                  t.status == TransferStatus.queued,
            )
            .toList();

    if (active.isNotEmpty) {
      final total = active.fold<int>(0, (s, t) => s + t.totalBytes);
      final done = active.fold<int>(0, (s, t) => s + t.transferredBytes);
      final pct = total > 0 ? (done * 100 / total).round().clamp(0, 100) : 0;
      final text =
          active.length == 1
              ? active.first.displayName
              : '${active.length} transfers in progress';
      _invoke('start', {
        'title': 'Transferring…',
        'text': text,
        'progress': pct,
      });
      _serviceRunning = true;
      return;
    }

    // No active transfers: stop the service and, if a batch just finished,
    // post a completion notification.
    if (_serviceRunning) {
      _serviceRunning = false;
      _invoke('stop');
      final completed =
          tasks.where((t) => t.status == TransferStatus.completed).length;
      final failed =
          tasks.where((t) => t.status == TransferStatus.failed).length;
      if (completed > 0 || failed > 0) {
        final parts = <String>[
          if (completed > 0) '$completed done',
          if (failed > 0) '$failed failed',
        ];
        _invoke('complete', {'text': parts.join(' · ')});
      }
    }
  }

  void _invoke(String method, [Map<String, dynamic>? args]) {
    // Fire-and-forget; ignore the missing-plugin case (non-Android / tests).
    _channel.invokeMethod(method, args).catchError((Object e) {
      if (e is! MissingPluginException) {
        // Swallow other platform errors too — a notification glitch must never
        // break the transfer itself — but only in release; assert in debug.
        assert(() {
          debugPrint('TransferNotifications.$method failed: $e');
          return true;
        }());
      }
      return null;
    });
  }
}

/// Keeps the foreground-service notification in sync with the transfer queue.
/// Instantiated by watching it once near the app root; it listens to
/// [transferQueueProvider] and drives [TransferNotifications].
final transferNotificationsProvider = Provider<TransferNotifications>((ref) {
  final notifications = TransferNotifications();
  ref.listen<List<TransferTask>>(transferQueueProvider, (_, next) {
    notifications.sync(next);
  }, fireImmediately: true);
  return notifications;
});
