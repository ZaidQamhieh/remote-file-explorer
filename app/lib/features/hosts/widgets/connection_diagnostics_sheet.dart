import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/models/health.dart';
import '../../../core/models/host.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';

class ConnectionDiagnosticsSheet extends StatefulWidget {
  const ConnectionDiagnosticsSheet({
    super.key,
    required this.host,
    required this.deviceToken,
  });

  final Host host;
  final String? deviceToken;

  @override
  State<ConnectionDiagnosticsSheet> createState() =>
      _ConnectionDiagnosticsSheetState();
}

class _ProbeResult {
  const _ProbeResult({
    required this.address,
    required this.label,
    this.latencyMs,
    this.health,
    this.error,
    this.certMismatch = false,
  });

  final String address;
  final String label;
  final int? latencyMs;
  final Health? health;
  final String? error;

  /// Whether the failure was specifically a pinned-fingerprint mismatch
  /// ([CertPinMismatch]), rather than an unreachable host — used to tell
  /// "TLS fingerprint pinned" apart from a plain connection failure.
  final bool certMismatch;

  bool get reachable => health != null;
}

class _ConnectionDiagnosticsSheetState
    extends State<ConnectionDiagnosticsSheet> {
  List<_ProbeResult>? _results;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _runProbes();
  }

  Future<_ProbeResult> _probe(String address, String label) async {
    final client = AgentClient(
      Host(
        id: widget.host.id,
        label: widget.host.label,
        address: address,
        certFingerprint: widget.host.certFingerprint,
      ),
      deviceToken: widget.deviceToken,
    );
    try {
      final sw = Stopwatch()..start();
      final health = await client.health().timeout(const Duration(seconds: 5));
      sw.stop();
      return _ProbeResult(
        address: address,
        label: label,
        latencyMs: sw.elapsedMilliseconds,
        health: health,
      );
    } catch (e) {
      final msg =
          e is TimeoutException
              ? 'Timed out'
              : humanizeError(e).replaceFirst('Exception: ', '');
      return _ProbeResult(
        address: address,
        label: label,
        error: msg,
        certMismatch: e is CertPinMismatch,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _runProbes() async {
    setState(() {
      _probing = true;
      _results = null;
    });

    final futures = <Future<_ProbeResult>>[];
    futures.add(_probe(widget.host.address, 'LAN'));
    final ts = widget.host.tailscaleAddress;
    if (ts != null && ts != widget.host.address) {
      futures.add(_probe(ts, 'Tailscale'));
    }

    final results = await Future.wait(futures);
    if (mounted) {
      setState(() {
        _results = results;
        _probing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final results = _results;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: Radii.stadiumR,
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.connectionDiagnosticsTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${widget.host.label} · ${widget.host.address}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (_probing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (results != null)
              // One block of checks per probed address. The mockup shows a
              // single fixed set of 4 checks for one connection; this app
              // genuinely probes both LAN and Tailscale addresses when both
              // are known, so both render (labelled) rather than dropping
              // the second address's real diagnostic data.
              for (var i = 0; i < results.length; i++) ...[
                if (results.length > 1) ...[
                  if (i > 0) const SizedBox(height: Spacing.md),
                  Text(
                    results[i].label,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                ],
                _DiagChecks(host: widget.host, result: results[i]),
              ],
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _probing ? null : _runProbes,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: Text(context.l10n.runAgainButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 4-row check list for one probed address — the mockup's fixed
/// DNS/TLS/Latency/Path rows, adapted to what this app can actually verify:
///
/// - "Host reachable" replaces the mockup's "DNS resolves": the app connects
///   by raw IP (LAN) or Tailscale address, never a DNS name, so there's no
///   real DNS-resolution step to report — reachability is the closest real
///   analog (and is literally the first thing the probe checks).
/// - "TLS fingerprint pinned" reflects the TOFU pin check
///   (`CertPinMismatch`) — a successful `/health` call already proves the
///   pin matched, since the client's `badCertificateCallback` would have
///   rejected the connection otherwise.
/// - "Latency" and "Path" are the probe's own real measurements.
class _DiagChecks extends StatelessWidget {
  const _DiagChecks({required this.host, required this.result});

  final Host host;
  final _ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reachable = result.reachable;

    final fingerprint = host.certFingerprint;
    final fingerprintPreview =
        fingerprint == null
            ? null
            : (fingerprint.length > 12
                ? '${fingerprint.substring(0, 12)}…'
                : fingerprint);

    return Column(
      children: [
        _DiagRow(
          icon: reachable ? LucideIcons.check : LucideIcons.x,
          tint: reachable ? Brand.online : Brand.red,
          title: l.diagHostReachable,
          subtitle: result.address,
          badgeText: reachable ? l.diagOkBadge : (result.error ?? l.probeError),
          badgeColor: reachable ? Brand.online : Brand.red,
        ),
        _DiagRow(
          icon:
              result.certMismatch
                  ? LucideIcons.x
                  : (reachable ? LucideIcons.check : LucideIcons.shield),
          tint:
              result.certMismatch
                  ? Brand.red
                  : (reachable ? Brand.online : Colors.grey),
          title: l.diagTlsPinned,
          subtitle: fingerprintPreview,
          badgeText:
              result.certMismatch
                  ? l.diagMismatchBadge
                  : (reachable ? l.diagPinnedBadge : l.diagUnknownBadge),
          badgeColor:
              result.certMismatch
                  ? Brand.red
                  : (reachable ? Brand.online : Colors.grey),
        ),
        _DiagRow(
          icon: LucideIcons.gauge,
          tint: reachable ? Brand.online : Colors.grey,
          title: l.diagLatency,
          badgeText: reachable ? l.probeLatencyMs(result.latencyMs!) : '—',
          badgeColor: reachable ? Brand.online : Colors.grey,
          mono: true,
        ),
        _DiagRow(
          icon: LucideIcons.route,
          tint: Brand.seed,
          title: l.diagPath,
          badgeText:
              reachable
                  ? (result.label == 'Tailscale'
                      ? l.networkTailscale
                      : l.diagLanDirect)
                  : l.offlineStatus,
          badgeColor: reachable ? Brand.seed : Colors.grey,
        ),
      ],
    );
  }
}

/// One diagnostic row: tinted icon, title (+ optional mono subtitle), and a
/// trailing colour-matched badge — the mockup's `.row` + `.badge` pattern.
class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    this.mono = false,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final String badgeText;
  final Color badgeColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: Spacing.md2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.16),
              borderRadius: Radii.stadiumR,
            ),
            child: Text(
              badgeText,
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: badgeColor,
                fontFamily: mono ? 'JetBrains Mono' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
