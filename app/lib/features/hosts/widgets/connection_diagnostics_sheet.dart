import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/models/health.dart';
import '../../../core/models/host.dart';
import '../../../core/theme/tokens.dart';

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
  });

  final String address;
  final String label;
  final int? latencyMs;
  final Health? health;
  final String? error;

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
    final host = widget.host.copyWith(address: address);
    final client = AgentClient(
      Host(
        id: host.id,
        label: host.label,
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
              : e.toString().replaceFirst('Exception: ', '');
      return _ProbeResult(address: address, label: label, error: msg);
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

    return SafeArea(
      child: Padding(
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
              widget.host.label,
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
            else if (_results != null)
              ..._results!.map((r) => _ProbeRow(result: r)),
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _probing ? null : _runProbes,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.l10n.retestButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbeRow extends StatelessWidget {
  const _ProbeRow({required this.result});

  final _ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reachable = result.reachable;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Radii.cardR,
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reachable ? Brand.online : Brand.offline,
              ),
            ),
            const SizedBox(width: Spacing.md2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.label,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.address,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              reachable
                  ? context.l10n.probeLatencyMs(result.latencyMs!)
                  : result.error ?? context.l10n.probeError,
              style: textTheme.labelMedium?.copyWith(
                color: reachable ? Brand.online : scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
