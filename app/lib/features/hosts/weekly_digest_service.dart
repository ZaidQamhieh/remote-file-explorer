/// Orchestrates the weekly storage digest (L4): the impure side (settings,
/// host store, network, notifications) around the pure compare/format logic
/// in `weekly_digest.dart`.
///
/// There is no OS-level background scheduler for this — L3's boot-completed /
/// exact-alarm permissions are wired only to the SSE-driven watched-folder
/// feature, not a generic periodic check, and adding a new background-service
/// dependency for a "nice to have" weekly notification is out of scope. So
/// this only fires when the user actually opens (or resumes) the app at
/// least once a week, gated by [shouldShowDigest].
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/providers.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/storage/host_store.dart';
import 'weekly_digest.dart';
import 'widgets/storage_gauge.dart' show aggregateUsage;

const _kLastShownAt = 'digest.lastShownAt.v1';
const _kSnapshot = 'digest.snapshot.v1';

class WeeklyDigestService {
  WeeklyDigestService(this._ref);

  final Ref _ref;

  /// No-op unless the setting is on and a week has passed since the last
  /// digest. Reaches only currently-online hosts; unreachable ones are
  /// skipped silently rather than failing the whole digest.
  Future<void> checkAndShow() async {
    final settings = _ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.app.weeklyDigestEnabled) return;

    final prefs = await SharedPreferences.getInstance();
    final lastMillis = prefs.getInt(_kLastShownAt);
    final lastShownAt =
        lastMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastMillis);
    if (!shouldShowDigest(lastShownAt, DateTime.now())) return;

    final store = await _ref.read(hostStoreProvider.future);
    final previous = _readSnapshot(prefs);
    final current = <String, HostUsage>{};

    for (final host in store.listHosts()) {
      try {
        final client = await buildClientForHost(_ref.read, host.id);
        try {
          await client.health().timeout(const Duration(seconds: 8));
          final usage = aggregateUsage(await client.drives());
          if (usage != null) current[host.label] = usage;
        } finally {
          client.close();
        }
      } catch (_) {
        // Host unreachable/asleep — skip it, don't fail the whole digest.
      }
    }

    // Record the attempt regardless, so an all-offline week doesn't re-check
    // on every resume — it just waits for the next 7-day window.
    await prefs.setInt(_kLastShownAt, DateTime.now().millisecondsSinceEpoch);
    if (current.isEmpty) return;

    final summary = buildDigestSummary(current, previous);
    await _ref.read(notificationServiceProvider).showWeeklyDigest(summary);
    await _writeSnapshot(prefs, current);
  }

  Map<String, HostUsage> _readSnapshot(SharedPreferences prefs) {
    final raw = prefs.getString(_kSnapshot);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((label, v) {
      final m = v as Map<String, dynamic>;
      return MapEntry(label, (
        totalBytes: m['totalBytes'] as int,
        freeBytes: m['freeBytes'] as int,
        usedFraction: (m['usedFraction'] as num).toDouble(),
      ));
    });
  }

  Future<void> _writeSnapshot(
    SharedPreferences prefs,
    Map<String, HostUsage> snapshot,
  ) {
    final encoded = snapshot.map(
      (label, u) => MapEntry(label, {
        'totalBytes': u.totalBytes,
        'freeBytes': u.freeBytes,
        'usedFraction': u.usedFraction,
      }),
    );
    return prefs.setString(_kSnapshot, jsonEncode(encoded));
  }
}

final weeklyDigestServiceProvider = Provider<WeeklyDigestService>(
  (ref) => WeeklyDigestService(ref),
);

/// Wraps [child] and triggers [WeeklyDigestService.checkAndShow] on cold
/// start and on every app resume — mirrors `LockGate`'s app-lifecycle pattern
/// since there's no periodic background scheduler for this feature.
class WeeklyDigestChecker extends ConsumerStatefulWidget {
  const WeeklyDigestChecker({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WeeklyDigestChecker> createState() =>
      _WeeklyDigestCheckerState();
}

class _WeeklyDigestCheckerState extends ConsumerState<WeeklyDigestChecker>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() => ref.read(weeklyDigestServiceProvider).checkAndShow();

  @override
  Widget build(BuildContext context) => widget.child;
}
