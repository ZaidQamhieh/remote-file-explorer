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

/// Sentinel returned by [_PairingCameraScanScreen] when the user taps "enter
/// code manually instead" — tells [_PairingScreenState] to switch segments
/// rather than just popping back to whatever segment was already active.
class _SwitchToCode {
  const _SwitchToCode();
}

const _switchToCode = _SwitchToCode();

/// Entry point for pairing a new host. Landing UI matches the mockup: a
/// "Scan QR / Enter Code" segmented control over the primary flow, with
/// account Login/Register — real capabilities (see `_LoginTab`/
/// `_RegisterTab`) that have no equivalent in the mockup at all — reachable
/// as secondary links underneath rather than dropped.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key, this.prefillAddress});

  /// When non-null the code-entry panel opens with this address pre-filled
  /// (e.g. from mDNS discovery).
  final String? prefillAddress;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _codeMode = false;

  Future<void> _openCameraScan() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const _PairingCameraScanScreen(),
      ),
    );
    if (!mounted) return;
    if (result is Host) {
      Navigator.of(context).pop(result);
    } else if (result is _SwitchToCode) {
      setState(() => _codeMode = true);
    }
  }

  Future<void> _openLogin() async {
    final host = await Navigator.of(context).push<Host>(
      MaterialPageRoute<Host>(
        builder:
            (_) => Scaffold(
              appBar: AppBar(title: ScreenHeader(context.l10n.loginTab)),
              body: _LoginTab(prefillAddress: widget.prefillAddress),
            ),
      ),
    );
    if (!mounted) return;
    if (host != null) Navigator.of(context).pop(host);
  }

  Future<void> _openRegister() async {
    final host = await Navigator.of(context).push<Host>(
      MaterialPageRoute<Host>(
        builder:
            (_) => Scaffold(
              appBar: AppBar(title: ScreenHeader(context.l10n.registerTab)),
              body: _RegisterTab(prefillAddress: widget.prefillAddress),
            ),
      ),
    );
    if (!mounted) return;
    if (host != null) Navigator.of(context).pop(host);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: ScreenHeader(context.l10n.addComputerTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.sm,
            ),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(context.l10n.scanQrTab),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(context.l10n.enterCodeTab),
                ),
              ],
              selected: {_codeMode},
              showSelectedIcon: false,
              onSelectionChanged:
                  (sel) => setState(() => _codeMode = sel.first),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _codeMode ? 1 : 0,
              children: [
                _QrPairingPanel(onOpenCamera: _openCameraScan),
                _ManualPairingTab(prefillAddress: widget.prefillAddress),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _openLogin,
                  child: Text(context.l10n.loginTab),
                ),
                const SizedBox(width: Spacing.md),
                TextButton(
                  onPressed: _openRegister,
                  child: Text(context.l10n.registerTab),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "On the PC, open RFE and go to Settings → Pair a device..." hint
/// card, shown at the bottom of both the scan and code-entry panels.
class _PairingHintCard extends StatelessWidget {
  const _PairingHintCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: Radii.cardR,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: scheme.primary),
          const SizedBox(width: Spacing.md2),
          Expanded(
            child: Text(
              context.l10n.pairingHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan QR panel — static viewfinder placeholder + a button that opens the
// live full-screen scanner, matching the mockup's `pair-panel-scan` +
// `scr-qr-scan` pair (the live camera itself lives in
// `_PairingCameraScanScreen` below).
// ---------------------------------------------------------------------------

class _QrPairingPanel extends StatelessWidget {
  const _QrPairingPanel({required this.onOpenCamera});

  final Future<void> Function() onOpenCamera;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Radii.sheet),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: _CornerBracketBox(
                cornerSize: 26,
                borderWidth: 3,
                inset: 16,
                child: Icon(
                  LucideIcons.qrCode,
                  size: 64,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md2 + Spacing.xs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenCamera,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(context.l10n.openCameraViewfinder),
                  const SizedBox(width: Spacing.sm),
                  const Icon(LucideIcons.arrowRight, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          const _PairingHintCard(),
        ],
      ),
    );
  }
}

/// Four L-shaped corner brackets around a square viewfinder, with an
/// optional animated glowing scanline — the mockup's QR viewfinder chrome.
/// Shared by the static placeholder above ([_QrPairingPanel], no scanline)
/// and the live full-screen scanner below ([_PairingCameraScanScreen]).
class _CornerBracketBox extends StatefulWidget {
  const _CornerBracketBox({
    required this.cornerSize,
    required this.borderWidth,
    required this.inset,
    this.child,
    this.scanlineHeight,
  });

  final double cornerSize;
  final double borderWidth;
  final double inset;
  final Widget? child;

  /// When set, animates a glowing horizontal line up/down across this
  /// height, matching the mockup's `@keyframes scanline`. Null = static.
  final double? scanlineHeight;

  @override
  State<_CornerBracketBox> createState() => _CornerBracketBoxState();
}

class _CornerBracketBoxState extends State<_CornerBracketBox>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.scanlineHeight != null) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Widget _bracket(Alignment alignment) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    final side = BorderSide(color: Brand.seed, width: widget.borderWidth);
    return Positioned(
      top: isTop ? widget.inset : null,
      bottom: !isTop ? widget.inset : null,
      left: isLeft ? widget.inset : null,
      right: !isLeft ? widget.inset : null,
      child: SizedBox(
        width: widget.cornerSize,
        height: widget.cornerSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: isTop ? side : BorderSide.none,
              bottom: !isTop ? side : BorderSide.none,
              left: isLeft ? side : BorderSide.none,
              right: !isLeft ? side : BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanlineHeight = widget.scanlineHeight;
    return Stack(
      children: [
        if (widget.child != null) Center(child: widget.child),
        for (final a in const [
          Alignment.topLeft,
          Alignment.topRight,
          Alignment.bottomLeft,
          Alignment.bottomRight,
        ])
          _bracket(a),
        if (scanlineHeight != null && _ctrl != null)
          AnimatedBuilder(
            animation: _ctrl!,
            builder: (context, _) {
              final travel = scanlineHeight / 2 - 8;
              final y = travel * (2 * _ctrl!.value - 1);
              return Positioned(
                left: 8,
                right: 8,
                top: scanlineHeight / 2 + y,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Brand.seed,
                    boxShadow: [
                      BoxShadow(
                        color: Brand.seed.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Translucent circular icon button on a dark camera background — the
/// mockup's `.iconbtn` treatment for full-screen scanner appbars.
class _DarkIconButton extends StatelessWidget {
  const _DarkIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

/// Live full-screen QR scanner for the PC-pairing flow — pushed from
/// [_QrPairingPanel]'s "Open camera viewfinder" button, matching the
/// mockup's `scr-qr-scan` dark full-bleed scanner with a corner-bracket
/// viewfinder + scanline. Business logic (barcode parsing, TOFU check,
/// `AgentClient.pair`, committing to the host store) is unchanged from the
/// original embedded-in-tab scanner — only the container moved.
class _PairingCameraScanScreen extends ConsumerStatefulWidget {
  const _PairingCameraScanScreen();

  @override
  ConsumerState<_PairingCameraScanScreen> createState() =>
      _PairingCameraScanScreenState();
}

class _PairingCameraScanScreenState
    extends ConsumerState<_PairingCameraScanScreen> {
  bool _processing = false;
  String? _error;
  final _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onBarcodeDetected),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  child: Row(
                    children: [
                      _DarkIconButton(
                        icon: LucideIcons.arrowLeft,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      Text(
                        context.l10n.scanQrTab,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _DarkIconButton(
                        icon: LucideIcons.flashlight,
                        onTap: () => _controller.toggleTorch(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Center(
                  child: SizedBox(
                    width: 230,
                    height: 230,
                    child: _CornerBracketBox(
                      cornerSize: 36,
                      borderWidth: 4,
                      inset: 0,
                      scanlineHeight: 230,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.md,
                  ),
                  child: Text(
                    context.l10n.pairingScanHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.xl,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(_switchToCode),
                      child: Text(context.l10n.enterCodeManuallyButton),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Positioned(
              bottom: 110,
              left: Spacing.md,
              right: Spacing.md,
              child: _InlineErrorCard(message: _error!),
            ),
          if (_processing)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Styled inline error card — rounded, on the scheme's error container, used
/// to surface pairing failures consistently across every panel.
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
// Enter Code panel — an 8-character alphanumeric code grid (matching the
// agent's real pairing-code format — `agent/internal/pairing/pairing.go`'s
// `codeLen = 8` over a 32-character alphabet — not the mockup's 6-digit
// numeric grid, which doesn't match what the backend actually issues) plus
// the address field the API requires (the mockup's "Enter Code" panel has
// no address field at all — pairing can't identify a host without one, so
// this is kept, just placed above the code grid).
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
    if (_codeCtrl.text.trim().length < 8) {
      setState(() => _error = context.l10n.requiredLabel);
      return;
    }
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
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: Spacing.lg),
            _CodeBoxRow(controller: _codeCtrl),
            const SizedBox(height: Spacing.lg),
            const _PairingHintCard(),
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

/// 8 single-character boxes that feed a shared [controller] — the mockup's
/// digit-entry grid, sized for the agent's real 8-character alphanumeric
/// pairing code (see the file-level comment above `_ManualPairingTab`).
/// Auto-advances focus forward on entry and back on backspace.
class _CodeBoxRow extends StatefulWidget {
  const _CodeBoxRow({required this.controller});

  final TextEditingController controller;

  @override
  State<_CodeBoxRow> createState() => _CodeBoxRowState();
}

class _CodeBoxRowState extends State<_CodeBoxRow> {
  static const _length = 8;
  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _boxes = List.generate(_length, (_) => TextEditingController());
    _nodes = List.generate(_length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _sync() => widget.controller.text = _boxes.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          SizedBox(
            width: 34,
            height: 48,
            child: Semantics(
              label: 'Pairing code, character ${i + 1} of $_length',
              child: TextField(
                controller: _boxes[i],
                focusNode: _nodes[i],
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 1,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(1),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                decoration: const InputDecoration(counterText: ''),
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                onChanged: (v) {
                  _sync();
                  if (v.isNotEmpty && i < _length - 1) {
                    _nodes[i + 1].requestFocus();
                  } else if (v.isEmpty && i > 0) {
                    _nodes[i - 1].requestFocus();
                  }
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Login tab — an additional way to obtain a device token, alongside the
// one-time pairing code, using the account created via `rfe-agent adduser`.
// Not modeled in the mockup at all (see `PairingScreen` doc comment) —
// reachable via the "Log in" link below the segmented control.
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
// Requires the same one-time pairing code as Scan QR / Enter Code (see
// registerHandler on the agent) so a stranger on the network can't create an
// account before the owner does. Not modeled in the mockup at all (see
// `PairingScreen` doc comment) — reachable via the "Register" link below the
// segmented control.
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
