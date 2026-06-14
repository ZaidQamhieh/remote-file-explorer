import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/format.dart';
import 'transfer_state.dart';

/// UI-side speed/ETA estimation for transfers.
///
/// The transfer engine ([TransferQueueNotifier]) deliberately knows nothing
/// about wall-clock speed — it only tracks byte counts. Everything in this
/// file is a *read-only observer* of that state: it samples
/// `transferredBytes` over time and derives a rolling-average speed
/// (bytes/sec) and an ETA (seconds) without ever mutating a [TransferTask].
///
/// The two pieces are intentionally separate:
///
///  * [computeSpeedEta] is a **pure function** over a list of samples, so it
///    can be unit-tested exhaustively (zero/one sample, steady rate, unknown
///    total, stalled) with no timers, no Riverpod, and no clock.
///  * [TransferSamplerNotifier] is the live wiring: it watches the queue, keeps
///    a short ring buffer of samples per task id, and drives a periodic timer
///    that only ticks while something is active (and stops cleanly when idle,
///    so it never leaks).

// ---------------------------------------------------------------------------
// Pure computation
// ---------------------------------------------------------------------------

/// A derived speed/ETA reading for a single task.
@immutable
class SpeedEta {
  const SpeedEta({this.bytesPerSecond, this.etaSeconds});

  /// Rolling-average throughput in bytes/sec, or `null` when there aren't
  /// enough samples (or no time has elapsed) to estimate one.
  final double? bytesPerSecond;

  /// Estimated seconds remaining, or `null` when it can't be computed
  /// (unknown total, zero/negative speed, or already complete).
  final double? etaSeconds;

  /// An empty reading — no speed, no ETA.
  static const SpeedEta unknown = SpeedEta();

  /// Human-readable speed, e.g. `12.4 MB/s`, or `null` when unknown.
  String? get speedLabel {
    final bps = bytesPerSecond;
    if (bps == null || bps <= 0) return null;
    return '${formatSize(bps.round())}/s';
  }

  /// Human-readable ETA, e.g. `~2m 30s` / `~45s`, or `null` when unknown.
  String? get etaLabel {
    final secs = etaSeconds;
    if (secs == null || secs.isInfinite || secs.isNaN || secs < 0) return null;
    return '~${formatDuration(secs.round())}';
  }
}

/// Formats a whole number of [seconds] compactly: `45s`, `2m 30s`, `1h 5m`.
String formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Computes a rolling-average speed and ETA from a list of `(ms, bytes)`
/// samples, oldest first.
///
/// [samples] is a window of `(elapsedMs, transferredBytes)` readings. The
/// speed is the average over the *whole supplied window* — the caller is
/// responsible for keeping the window short (a handful of recent samples /
/// ~last couple of seconds) so the result is a recent rolling average rather
/// than a lifetime average. Using the window's span (rather than the gap
/// between the last two points) keeps the figure stable instead of jittering
/// on every tick.
///
/// Edge cases:
///  * 0 or 1 sample → no speed, no ETA ([SpeedEta.unknown]).
///  * No time elapsed across the window (all same timestamp) → no speed.
///  * A stalled transfer (bytes flat across the window) → speed 0, no ETA.
///  * [totalBytes] null/0 → speed still reported, but ETA is `null`.
SpeedEta computeSpeedEta(List<(int ms, int bytes)> samples, {int? totalBytes}) {
  if (samples.length < 2) return SpeedEta.unknown;

  final first = samples.first;
  final last = samples.last;

  final elapsedMs = last.$1 - first.$1;
  if (elapsedMs <= 0) return SpeedEta.unknown;

  final deltaBytes = last.$2 - first.$2;
  // A regressing byte count (shouldn't happen, but a resumed-from-0 restart
  // could momentarily produce one) is treated as a stall, not negative speed.
  final bytesPerSecond = deltaBytes <= 0 ? 0.0 : deltaBytes / (elapsedMs / 1000);

  double? etaSeconds;
  if (totalBytes != null && totalBytes > 0 && bytesPerSecond > 0) {
    final remaining = totalBytes - last.$2;
    etaSeconds = remaining <= 0 ? 0.0 : remaining / bytesPerSecond;
  }

  return SpeedEta(bytesPerSecond: bytesPerSecond, etaSeconds: etaSeconds);
}

// ---------------------------------------------------------------------------
// Live sampler
// ---------------------------------------------------------------------------

/// How many recent samples to retain per task. At a ~400ms tick this is a
/// ~2s window — long enough to smooth out chunk-boundary bursts, short enough
/// to stay responsive when the rate changes.
const int _kWindowSize = 5;

/// Tick interval for the sampler. Only runs while at least one task is active.
const Duration _kSampleInterval = Duration(milliseconds: 400);

/// A `(elapsedMs, transferredBytes)` sample. `elapsedMs` is measured from the
/// sampler's epoch (first observation) so values stay small and monotonic.
typedef _Sample = (int ms, int bytes);

/// Watches [transferQueueProvider] and maintains, per running task id, a short
/// ring buffer of byte-count samples — exposing a [SpeedEta] map the UI reads
/// for live speed/ETA without touching the engine.
///
/// The clock is injectable for deterministic tests; production uses
/// [DateTime.now]. The driving [Timer] only runs while something is active and
/// is cancelled the moment the queue goes idle (and on [dispose]), so it never
/// leaks across screens.
class TransferSamplerNotifier extends Notifier<Map<String, SpeedEta>> {
  TransferSamplerNotifier({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Ring buffer of recent samples per task id.
  final Map<String, List<_Sample>> _samples = {};

  /// Epoch the sampler measures `elapsedMs` from (lazily set on first sample).
  DateTime? _epoch;

  Timer? _timer;

  @override
  Map<String, SpeedEta> build() {
    // React to queue changes: (re)start the timer when work appears, stop it
    // when the queue drains, and prune samples for tasks that left.
    ref.listen<List<TransferTask>>(
      transferQueueProvider,
      (_, next) => _onQueueChanged(next),
      fireImmediately: true,
    );
    ref.onDispose(_stop);
    return const {};
  }

  void _onQueueChanged(List<TransferTask> tasks) {
    final activeIds = tasks
        .where((t) => t.status == TransferStatus.running)
        .map((t) => t.id)
        .toSet();

    // Drop sample history + derived readings for tasks that are no longer
    // running (completed/failed/paused/removed) so the maps don't grow.
    _samples.removeWhere((id, _) => !activeIds.contains(id));
    if (state.keys.any((id) => !activeIds.contains(id))) {
      state = {
        for (final e in state.entries)
          if (activeIds.contains(e.key)) e.key: e.value,
      };
    }

    if (activeIds.isEmpty) {
      _stop();
    } else {
      _ensureRunning();
      // Take an immediate sample so the first reading isn't a full tick away.
      _sample();
    }
  }

  void _ensureRunning() {
    _timer ??= Timer.periodic(_kSampleInterval, (_) => _sample());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _epoch = null;
    _samples.clear();
    if (state.isNotEmpty) state = const {};
  }

  /// Records one sample per running task and recomputes the [SpeedEta] map.
  void _sample() {
    final tasks = ref.read(transferQueueProvider);
    final running =
        tasks.where((t) => t.status == TransferStatus.running).toList();
    if (running.isEmpty) {
      _stop();
      return;
    }

    final now = _clock();
    _epoch ??= now;
    final elapsedMs = now.difference(_epoch!).inMilliseconds;

    final next = <String, SpeedEta>{};
    for (final task in running) {
      final buf = _samples.putIfAbsent(task.id, () => <_Sample>[]);
      buf.add((elapsedMs, task.transferredBytes));
      if (buf.length > _kWindowSize) buf.removeAt(0);
      next[task.id] = computeSpeedEta(
        buf,
        totalBytes: task.totalBytes > 0 ? task.totalBytes : null,
      );
    }
    state = next;
  }
}

/// Live speed/ETA per task id, keyed by [TransferTask.id]. Empty while idle.
final transferSamplerProvider =
    NotifierProvider<TransferSamplerNotifier, Map<String, SpeedEta>>(
  TransferSamplerNotifier.new,
);
