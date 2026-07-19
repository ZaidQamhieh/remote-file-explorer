import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/screen_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Fetches a fresh challenge nonce from [client] and signs it with this
/// device's permanent identity key — the (publicKey, nonce, signature)
/// triple every pair/register/login call needs. Shared by every tab.
Future<(String publicKey, String nonce, String signature)> _deviceProof(
  AgentClient client,
) async {
  final nonce = await client.challenge();
  final publicKey = await DeviceIdentity.instance.publicKeyBase64();
  final signature = await DeviceIdentity.instance.signBase64(nonce);
  return (publicKey, nonce, signature);
}

/// Hardware-stable device id (Android ID), used so re-pairing the same phone
/// reuses its device row on the agent instead of creating a duplicate. Returns
/// null on non-Android platforms or if it can't be read.
Future<String?> _deviceId() async {
  if (!Platform.isAndroid) return null;
  try {
    return await const MethodChannel(
      'rfe/downloads',
    ).invokeMethod<String>('getDeviceId');
  } catch (_) {
    return null;
  }
}

/// Entry point for pairing a new host. Shows a tab bar with QR scan and
/// manual-entry options.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key, this.prefillAddress});

  /// When non-null the manual-entry tab opens with this address pre-filled
  /// (e.g. from mDNS discovery) and the tab bar starts on "Manual".
  final String? prefillAddress;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      vsync: this,
      // Manual is the default landing tab (works with no camera); mDNS
      // prefill already targeted Manual too, so this is now unconditional.
      initialIndex: 1,
    );
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
        toolbarHeight: 72,
        title: ScreenHeader(context.l10n.addComputerTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              icon: const Icon(LucideIcons.scanQrCode),
              text: context.l10n.scanQrTab,
            ),
            Tab(
              icon: const Icon(LucideIcons.keyboard),
              text: context.l10n.manualTab,
            ),
            Tab(
              icon: const Icon(LucideIcons.userRound),
              text: context.l10n.loginTab,
            ),
            Tab(
              icon: const Icon(LucideIcons.userPlus),
              text: context.l10n.registerTab,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _QrPairingTab(),
          _ManualPairingTab(prefillAddress: widget.prefillAddress),
          _LoginTab(prefillAddress: widget.prefillAddress),
          _RegisterTab(prefillAddress: widget.prefillAddress),
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
      setState(() => _error = context.l10n.invalidQrFormat);
      return;
    }

    final address = qr['address'] as String?;
    final certFingerprint = qr['certFingerprint'] as String?;
    final pairingCode = qr['pairingCode'] as String?;

    if (address == null || pairingCode == null) {
      setState(() => _error = context.l10n.qrMissingFields);
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
    // Probe host — no fingerprint yet (TOFU). This host isn't in the store
    // yet (pairing hasn't completed), so it can't go through
    // buildClientForHost/clientProvider — those require a paired host record
    // to look up a device token. Construct directly and close when done.
    final probeHost = Host(
      id: 'pairing_probe',
      label: 'probe',
      address: address,
      certFingerprint: expectedFingerprint,
    );
    final client = AgentClient(probeHost);

    try {
      final (publicKey, nonce, signature) = await _deviceProof(client);
      final resp = await client.pair(
        pairingCode: pairingCode,
        deviceLabel: 'Mobile App',
        devicePublicKey: publicKey,
        nonce: nonce,
        signature: signature,
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
      await store.commitPairing(
        host,
        token: resp.deviceToken,
        fingerprint: host.certFingerprint,
      );

      if (mounted) {
        showSuccess(context, context.l10n.pairedWith(host.label));
        Navigator.of(context).pop(host);
      }
    } on CertPinMismatch catch (e) {
      if (mounted) {
        setState(
          () => _error = context.l10n.fingerprintMismatch(humanizeError(e)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = context.l10n.pairingFailed(humanizeError(e)));
      }
    } finally {
      client.close();
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(onDetect: _onBarcodeDetected),
        if (_processing) const Center(child: CircularProgressIndicator()),
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
            Icon(
              LucideIcons.circleAlert,
              size: 20,
              color: scheme.onErrorContainer,
            ),
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
  const _ManualPairingTab({this.prefillAddress});

  final String? prefillAddress;

  @override
  ConsumerState<_ManualPairingTab> createState() => _ManualPairingTabState();
}

class _ManualPairingTabState extends ConsumerState<_ManualPairingTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _addressCtrl;
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _addressCtrl = TextEditingController(text: widget.prefillAddress);
  }

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

    // Probe host — not yet in the store (pairing hasn't completed), so this
    // can't go through buildClientForHost/clientProvider. Construct directly
    // and close when done.
    final probeHost = Host(
      id: 'pairing_probe',
      label: 'probe',
      address: _addressCtrl.text.trim(),
    );
    final client = AgentClient(probeHost);

    try {
      final (publicKey, nonce, signature) = await _deviceProof(client);
      final resp = await client.pair(
        pairingCode: _codeCtrl.text.trim(),
        deviceLabel: 'Mobile App',
        devicePublicKey: publicKey,
        nonce: nonce,
        signature: signature,
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
      await store.commitPairing(
        host,
        token: resp.deviceToken,
        fingerprint: host.certFingerprint,
      );

      if (mounted) {
        showSuccess(context, context.l10n.pairedWith(host.label));
        Navigator.of(context).pop(host);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = context.l10n.pairingFailed(humanizeError(e)));
      }
    } finally {
      client.close();
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
              decoration: InputDecoration(
                labelText: context.l10n.agentAddressLabel,
                hintText: context.l10n.agentAddressHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.computer),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _codeCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.pairingCodeLabel,
                hintText: context.l10n.pairingCodeHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.lock),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              _InlineErrorCard(message: _error!),
              const SizedBox(height: Spacing.sm + Spacing.xs),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon:
                  _loading
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(LucideIcons.link),
              label: Text(context.l10n.pairButton),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login tab — an additional way to obtain a device token, alongside the
// one-time pairing code, using the account created via `rfe-agent adduser`.
// ---------------------------------------------------------------------------

class _LoginTab extends ConsumerStatefulWidget {
  const _LoginTab({this.prefillAddress});

  final String? prefillAddress;

  @override
  ConsumerState<_LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends ConsumerState<_LoginTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _addressCtrl;
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _addressCtrl = TextEditingController(text: widget.prefillAddress);
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Probe host — not yet in the store, same as _ManualPairingTab.
    final probeHost = Host(
      id: 'pairing_probe',
      label: 'probe',
      address: _addressCtrl.text.trim(),
    );
    final client = AgentClient(probeHost);

    try {
      final (publicKey, nonce, signature) = await _deviceProof(client);
      final resp = await client.login(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        deviceLabel: 'Mobile App',
        devicePublicKey: publicKey,
        nonce: nonce,
        signature: signature,
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
      await store.commitPairing(
        host,
        token: resp.deviceToken,
        fingerprint: host.certFingerprint,
      );

      if (mounted) {
        showSuccess(context, context.l10n.pairedWith(host.label));
        Navigator.of(context).pop(host);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = context.l10n.loginFailed(humanizeError(e)));
      }
    } finally {
      client.close();
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
              decoration: InputDecoration(
                labelText: context.l10n.agentAddressLabel,
                hintText: context.l10n.agentAddressHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.computer),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.usernameLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.userRound),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: context.l10n.passwordLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator:
                  (v) =>
                      (v == null || v.isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.loginHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              _InlineErrorCard(message: _error!),
              const SizedBox(height: Spacing.sm + Spacing.xs),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon:
                  _loading
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(LucideIcons.logIn),
              label: Text(context.l10n.loginButton),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Register tab — creates the account and pairs this device in one step.
// Requires the same one-time pairing code as Scan QR / Manual (see
// registerHandler on the agent) so a stranger on the network can't create an
// account before the owner does.
// ---------------------------------------------------------------------------

class _RegisterTab extends ConsumerStatefulWidget {
  const _RegisterTab({this.prefillAddress});

  final String? prefillAddress;

  @override
  ConsumerState<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends ConsumerState<_RegisterTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _addressCtrl;
  final _codeCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _addressCtrl = TextEditingController(text: widget.prefillAddress);
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _codeCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Probe host — not yet in the store, same as the other tabs.
    final probeHost = Host(
      id: 'pairing_probe',
      label: 'probe',
      address: _addressCtrl.text.trim(),
    );
    final client = AgentClient(probeHost);

    try {
      final (publicKey, nonce, signature) = await _deviceProof(client);
      final resp = await client.register(
        pairingCode: _codeCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        deviceLabel: 'Mobile App',
        devicePublicKey: publicKey,
        nonce: nonce,
        signature: signature,
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
      await store.commitPairing(
        host,
        token: resp.deviceToken,
        fingerprint: host.certFingerprint,
      );

      if (mounted) {
        showSuccess(context, context.l10n.pairedWith(host.label));
        Navigator.of(context).pop(host);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = context.l10n.registerFailed(humanizeError(e)));
      }
    } finally {
      client.close();
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
              decoration: InputDecoration(
                labelText: context.l10n.agentAddressLabel,
                hintText: context.l10n.agentAddressHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.computer),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _codeCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.pairingCodeLabel,
                hintText: context.l10n.pairingCodeHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.lock),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.usernameLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.userRound),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? context.l10n.requiredLabel
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: context.l10n.passwordLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return context.l10n.requiredLabel;
                if (v.length < 8) return context.l10n.passwordTooShort;
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: context.l10n.confirmPasswordLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.lock),
              ),
              validator:
                  (v) =>
                      v != _passwordCtrl.text
                          ? context.l10n.passwordMismatch
                          : null,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.registerHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              _InlineErrorCard(message: _error!),
              const SizedBox(height: Spacing.sm + Spacing.xs),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon:
                  _loading
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(LucideIcons.userPlus),
              label: Text(context.l10n.registerButton),
            ),
          ],
        ),
      ),
    );
  }
}
