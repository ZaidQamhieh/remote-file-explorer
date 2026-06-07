import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';

/// Hardware-stable device id (Android ID), used so re-pairing the same phone
/// reuses its device row on the agent instead of creating a duplicate. Returns
/// null on non-Android platforms or if it can't be read.
Future<String?> _deviceId() async {
  if (!Platform.isAndroid) return null;
  try {
    return await const MethodChannel('rfe/downloads')
        .invokeMethod<String>('getDeviceId');
  } catch (_) {
    return null;
  }
}

/// Entry point for pairing a new host. Shows a tab bar with QR scan and
/// manual-entry options.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add computer'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR'),
            Tab(icon: Icon(Icons.keyboard), text: 'Manual'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _QrPairingTab(),
          _ManualPairingTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR pairing tab
// ---------------------------------------------------------------------------

/// QR payload: `{"address":"host:port","certFingerprint":"...","pairingCode":"..."}`
class _QrPairingTab extends ConsumerStatefulWidget {
  const _QrPairingTab();

  @override
  ConsumerState<_QrPairingTab> createState() => _QrPairingTabState();
}

class _QrPairingTabState extends ConsumerState<_QrPairingTab> {
  bool _processing = false;
  String? _error;

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    Map<String, dynamic> qr;
    try {
      qr = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _error = 'Invalid QR code format.');
      return;
    }

    final address = qr['address'] as String?;
    final certFingerprint = qr['certFingerprint'] as String?;
    final pairingCode = qr['pairingCode'] as String?;

    if (address == null || pairingCode == null) {
      setState(() => _error = 'QR missing required fields.');
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    await _doPair(
      address: address,
      pairingCode: pairingCode,
      expectedFingerprint: certFingerprint,
    );
  }

  Future<void> _doPair({
    required String address,
    required String pairingCode,
    String? expectedFingerprint,
  }) async {
    // Probe host — no fingerprint yet (TOFU)
    final probeHost = Host(
      id: 'pairing_probe',
      label: 'probe',
      address: address,
      certFingerprint: expectedFingerprint,
    );
    final client = AgentClient(probeHost);

    try {
      final resp = await client.pair(
        pairingCode: pairingCode,
        deviceLabel: 'Mobile App',
        clientPublicKey: 'placeholder-key',
        deviceId: await _deviceId(),
      );

      final capturedFp = client.lastSeenFingerprint;

      // If QR included a fingerprint, verify TOFU matches
      if (expectedFingerprint != null &&
          capturedFp != null &&
          capturedFp != expectedFingerprint) {
        throw CertPinMismatch(expectedFingerprint, capturedFp);
      }

      final host = Host(
        id: resp.deviceId,
        label: resp.agentName,
        address: address,
        certFingerprint: capturedFp ?? resp.certFingerprint,
        // The agent reports both addresses it knows about itself, so the
        // host is immediately reachable both at home (LAN) and away
        // (Tailscale) — no separate "add as second host" step needed.
        tailscaleAddress: resp.tailscaleAddress,
      );

      final store = await ref.read(hostStoreProvider.future);
      await store.addHost(host);
      await store.setToken(host.id, resp.deviceToken);
      if (host.certFingerprint != null) {
        await store.setFingerprint(host.id, host.certFingerprint!);
      }

      if (mounted) {
        showSuccess(context, 'Paired with ${host.label}');
        Navigator.of(context).pop(host);
      }
    } on CertPinMismatch catch (e) {
      if (mounted) setState(() => _error = 'Fingerprint mismatch: $e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Pairing failed: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(onDetect: _onBarcodeDetected),
        if (_processing)
          const Center(child: CircularProgressIndicator()),
        if (_error != null)
          Positioned(
            bottom: Spacing.xl,
            left: Spacing.md,
            right: Spacing.md,
            child: _InlineErrorCard(message: _error!),
          ),
      ],
    );
  }
}

/// Styled inline error card — rounded, on the scheme's error container, used
/// to surface pairing failures consistently across both tabs.
class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: Radii.cardR,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm + Spacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual pairing tab
// ---------------------------------------------------------------------------

class _ManualPairingTab extends ConsumerStatefulWidget {
  const _ManualPairingTab();

  @override
  ConsumerState<_ManualPairingTab> createState() => _ManualPairingTabState();
}

class _ManualPairingTabState extends ConsumerState<_ManualPairingTab> {
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final probeHost = Host(
      id: 'pairing_probe',
      label: 'probe',
      address: _addressCtrl.text.trim(),
    );
    final client = AgentClient(probeHost);

    try {
      final resp = await client.pair(
        pairingCode: _codeCtrl.text.trim(),
        deviceLabel: 'Mobile App',
        clientPublicKey: 'placeholder-key',
        deviceId: await _deviceId(),
      );

      final capturedFp = client.lastSeenFingerprint;
      final host = Host(
        id: resp.deviceId,
        label: resp.agentName,
        address: _addressCtrl.text.trim(),
        certFingerprint: capturedFp ?? resp.certFingerprint,
        tailscaleAddress: resp.tailscaleAddress,
      );

      final store = await ref.read(hostStoreProvider.future);
      await store.addHost(host);
      await store.setToken(host.id, resp.deviceToken);
      if (host.certFingerprint != null) {
        await store.setFingerprint(host.id, host.certFingerprint!);
      }

      if (mounted) {
        showSuccess(context, 'Paired with ${host.label}');
        Navigator.of(context).pop(host);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Pairing failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Agent address',
                hintText: '192.168.1.10:8765',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Pairing code',
                hintText: '123456',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              _InlineErrorCard(message: _error!),
              const SizedBox(height: Spacing.sm + Spacing.xs),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Pair'),
            ),
          ],
        ),
      ),
    );
  }
}
