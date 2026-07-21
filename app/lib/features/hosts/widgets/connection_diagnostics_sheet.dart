import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/models/health.dart';
import '../../../core/models/host.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/pressable.dart';

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
    final results = _results;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The mockup's `.sheet-handle`: 36x4 pill, `--border-strong`.
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: Radii.stadiumR,
              ),
            ),
          ),
          // The mockup's `.sheet-head`: 16px bold h3 + a 12px mono faint
          // subtitle line.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.connectionDiagnosticsTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.host.label} · ${widget.host.address}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_probing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (results != null)
                    // One block of checks per probed address. The mockup
                    // shows a single fixed set of 4 checks for one
                    // connection; this app genuinely probes both LAN and
                    // Tailscale addresses when both are known, so both
                    // render (labelled) rather than dropping the second
                    // address's real diagnostic data.
                    for (var i = 0; i < results.length; i++) ...[
                      if (results.length > 1) ...[
                        if (i > 0) const SizedBox(height: Spacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            results[i].label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.945,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                      ],
                      _DiagChecks(host: widget.host, result: results[i]),
                    ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                    child: _RunAgainButton(onTap: _probing ? null : _runProbes),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block` — text then a trailing refresh
/// icon, matching the literal markup order (`Run again<svg
/// refresh-cw/>`).
class _RunAgainButton extends StatelessWidget {
  const _RunAgainButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: Radii.smR,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.l10n.runAgainButton,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 7),
              Icon(LucideIcons.refreshCw, size: 16, color: scheme.onSurface),
            ],
          ),
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

    final rows = [
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
        showDivider: false,
      ),
    ];
    return Column(children: rows);
  }
}

/// One diagnostic row: a 38x38 tinted rounded-square icon, title (+
/// optional mono subtitle), and a trailing colour-matched badge — the
/// mockup's literal `.row` (11px vertical / 4px horizontal padding, 12px
/// gap, 1px bottom border except the last row) + `.row-icon` + `.badge`.
class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    this.mono = false,
    this.showDivider = true,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final String badgeText;
  final Color badgeColor;
  final bool mono;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        border:
            showDivider
                ? Border(bottom: BorderSide(color: scheme.outlineVariant))
                : null,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: Radii.smR,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md2),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: Radii.stadiumR,
              ),
              child: Text(
                badgeText,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  // JetBrains Mono only bundles 400/500 — w700 corrupts its
                  // glyphs via Skia's synthetic-bold fallback (see pairing
                  // screen's code boxes for the same fix).
                  fontWeight: mono ? FontWeight.w500 : FontWeight.w700,
                  color: badgeColor,
                  fontFamily: mono ? 'JetBrains Mono' : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
