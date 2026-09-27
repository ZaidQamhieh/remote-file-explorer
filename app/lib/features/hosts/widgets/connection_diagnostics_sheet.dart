import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/models/health.dart';
import '../../../core/models/host.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';

class ConnectionDiagnosticsSheet extends StatefulWidget {
  const ConnectionDiagnosticsSheet({
    super.key,
    required this.host,
    required this.deviceToken,
    required this.secureFingerprint,
  });

  final Host host;
  final String? deviceToken;
  final String? secureFingerprint;

  @override
  State<ConnectionDiagnosticsSheet> createState() =>
      _ConnectionDiagnosticsSheetState();
}

class _ProbeResult {
  const _ProbeResult({
    required this.route,
    required this.address,
    this.latencyMs,
    this.health,
    this.failure = _ProbeFailure.none,
    this.auth = _AuthOutcome.notChecked,
  });

  final HostRoute route;
  final String address;
  final int? latencyMs;
  final Health? health;
  final _ProbeFailure failure;
  final _AuthOutcome auth;

  bool get reachable => health != null;
  bool get certMismatch => failure == _ProbeFailure.pinMismatch;
}

enum _ProbeFailure { none, missingPin, pinMismatch, dns, unreachable, other }

enum _AuthOutcome { notChecked, accepted, denied }

class _ConnectionDiagnosticsSheetState
    extends State<ConnectionDiagnosticsSheet> {
  List<_ProbeResult>? _results;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _runProbes();
  }

  Future<_ProbeResult> _probe(HostRoute route, String address) async {
    final fingerprint = AgentClient.normalizeFingerprint(
      widget.secureFingerprint,
    );
    if (fingerprint == null) {
      return _ProbeResult(
        route: route,
        address: address,
        failure: _ProbeFailure.missingPin,
      );
    }
    final client = AgentClient(
      Host(
        id: widget.host.id,
        label: widget.host.label,
        address: address,
        certFingerprint: fingerprint,
      ),
      deviceToken: widget.deviceToken,
    );
    try {
      final sw = Stopwatch()..start();
      final health = await client.health().timeout(const Duration(seconds: 5));
      sw.stop();
      var auth = _AuthOutcome.notChecked;
      try {
        await client.fetchStatus().timeout(const Duration(seconds: 5));
        auth = _AuthOutcome.accepted;
      } on AgentApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          auth = _AuthOutcome.denied;
        }
      } on CertPinMismatch {
        rethrow;
      } on MissingCertPin {
        rethrow;
      } catch (_) {
        // Health already established route reachability and pinned TLS. If an
        // auth-only check fails for a transient or legacy reason, report its
        // outcome as unknown instead of misclassifying the route as offline.
      }
      return _ProbeResult(
        route: route,
        address: address,
        latencyMs: sw.elapsedMilliseconds,
        health: health,
        auth: auth,
      );
    } catch (e) {
      return _ProbeResult(
        route: route,
        address: address,
        failure: _probeFailure(e),
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

    final futures = [
      for (final route in widget.host.routeAddresses)
        _probe(route.route, route.address),
    ];
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
                    for (var i = 0; i < results.length; i++) ...[
                      if (results.length > 1) ...[
                        if (i > 0) const SizedBox(height: Spacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _routeName(context, results[i].route),
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
                      _DiagChecks(
                        fingerprint: AgentClient.normalizeFingerprint(
                          widget.secureFingerprint,
                        ),
                        result: results[i],
                      ),
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

  String _routeName(BuildContext context, HostRoute route) => switch (route) {
    HostRoute.lan => context.l10n.routeLanName,
    HostRoute.tailscale => context.l10n.routeTailscaleName,
    HostRoute.directHttps => context.l10n.routeInternetName,
    HostRoute.custom => context.l10n.routeCustomName,
  };
}

_ProbeFailure _probeFailure(Object error) {
  if (error is CertPinMismatch) return _ProbeFailure.pinMismatch;
  if (error is MissingCertPin) return _ProbeFailure.missingPin;

  Object? cause;
  DioExceptionType? dioType;
  if (error is AgentApiException) {
    cause = error.cause;
    dioType = error.dioType;
  } else if (error is DioException) {
    cause = error.error;
    dioType = error.type;
  }
  if (_containsPinMismatch(cause)) return _ProbeFailure.pinMismatch;
  if (_isDnsFailure(cause)) return _ProbeFailure.dns;
  if (error is TimeoutException ||
      dioType == DioExceptionType.connectionTimeout ||
      dioType == DioExceptionType.connectionError ||
      dioType == DioExceptionType.sendTimeout ||
      dioType == DioExceptionType.receiveTimeout) {
    return _ProbeFailure.unreachable;
  }
  return _ProbeFailure.other;
}

bool _containsPinMismatch(Object? error) {
  var cause = error;
  while (cause != null) {
    if (cause is CertPinMismatch) return true;
    if (cause is DioException) {
      cause = cause.error;
    } else if (cause is AgentApiException) {
      cause = cause.cause;
    } else {
      return false;
    }
  }
  return false;
}

bool _isDnsFailure(Object? error) {
  var cause = error;
  while (cause != null) {
    if (cause is SocketException) {
      final message =
          '${cause.message} ${cause.osError?.message ?? ''}'.toLowerCase();
      return message.contains('failed host lookup') ||
          message.contains('name or service not known') ||
          message.contains('nodename nor servname') ||
          message.contains('no address associated with hostname');
    }
    if (cause is DioException) {
      cause = cause.error;
    } else if (cause is AgentApiException) {
      cause = cause.cause;
    } else {
      return false;
    }
  }
  return false;
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

/// Reports DNS/reachability, pinned TLS, authenticated access, latency, and
/// route metadata for one independently probed address.
class _DiagChecks extends StatelessWidget {
  const _DiagChecks({required this.fingerprint, required this.result});

  final String? fingerprint;
  final _ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reachable = result.reachable;
    final failureBadge = switch (result.failure) {
      _ProbeFailure.none => l.diagOkBadge,
      _ProbeFailure.missingPin => l.diagPinRequiredBadge,
      _ProbeFailure.pinMismatch => l.diagMismatchBadge,
      _ProbeFailure.dns => l.probeDnsFailedBadge,
      _ProbeFailure.unreachable => l.probeNoResponseBadge,
      _ProbeFailure.other => l.probeError,
    };

    final fingerprintPreview =
        fingerprint == null
            ? null
            : (fingerprint.length > 12
                ? '${fingerprint.substring(0, 12)}…'
                : fingerprint);

    final rows = [
      _DiagRow(
        icon: reachable ? LucideIcons.check : LucideIcons.x,
        tint:
            reachable
                ? Brand.online
                : (result.failure == _ProbeFailure.pinMismatch
                    ? Brand.red
                    : Colors.grey),
        title: l.diagHostReachable,
        subtitle: result.address,
        badgeText: failureBadge,
        badgeColor:
            reachable
                ? Brand.online
                : (result.failure == _ProbeFailure.pinMismatch
                    ? Brand.red
                    : Colors.grey),
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
                : (reachable
                    ? l.diagPinnedBadge
                    : (result.failure == _ProbeFailure.missingPin
                        ? l.diagPinRequiredBadge
                        : l.diagUnknownBadge)),
        badgeColor:
            result.certMismatch
                ? Brand.red
                : (reachable ? Brand.online : Colors.grey),
      ),
      _DiagRow(
        icon:
            result.auth == _AuthOutcome.accepted
                ? LucideIcons.check
                : (result.auth == _AuthOutcome.denied
                    ? LucideIcons.x
                    : LucideIcons.shield),
        tint:
            result.auth == _AuthOutcome.accepted
                ? Brand.online
                : (result.auth == _AuthOutcome.denied
                    ? Brand.red
                    : Colors.grey),
        title: l.diagAuthentication,
        badgeText: switch (result.auth) {
          _AuthOutcome.accepted => l.diagAuthAcceptedBadge,
          _AuthOutcome.denied => l.diagAuthDeniedBadge,
          _AuthOutcome.notChecked => l.diagAuthUnknownBadge,
        },
        badgeColor:
            result.auth == _AuthOutcome.accepted
                ? Brand.online
                : (result.auth == _AuthOutcome.denied
                    ? Brand.red
                    : Colors.grey),
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
        badgeText: switch (result.route) {
          HostRoute.lan => l.diagLanDirect,
          HostRoute.tailscale => l.networkTailscale,
          HostRoute.directHttps => l.routeInternetName,
          HostRoute.custom => l.routeCustomName,
        },
        badgeColor: reachable ? Brand.seed : Colors.grey,
        showDivider: false,
      ),
    ];
    final hint = switch (result.failure) {
      _ProbeFailure.pinMismatch => l.probePinMismatchHint,
      _ProbeFailure.missingPin => l.probeMissingPinHint,
      _ProbeFailure.dns => l.probeDnsHint,
      _ProbeFailure.unreachable => l.probeReachabilityHint,
      _ProbeFailure.other => l.probeGenericHint,
      _ProbeFailure.none when result.auth == _AuthOutcome.denied =>
        l.probeAuthRejectedHint,
      _ProbeFailure.none => null,
    };
    return Column(
      children: [
        ...rows,
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hint,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ),
      ],
    );
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
