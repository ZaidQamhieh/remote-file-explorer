import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/sheet_chrome.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet showing a QR code that hands one file off to another phone
/// already paired to the same agent — see `qr_scan_screen.dart` for the
/// receiving side. Payload: `{certFingerprint, path, name}` — no token, no
/// address, since the receiver is separately paired to this same host and
/// already knows how to reach it.
class QrGenerateSheet extends StatelessWidget {
  const QrGenerateSheet({
    super.key,
    required this.certFingerprint,
    required this.path,
    required this.name,
  });

  final String certFingerprint;
  final String path;
  final String name;

  @override
  Widget build(BuildContext context) {
    final payload = jsonEncode({
      'certFingerprint': certFingerprint,
      'path': path,
      'name': name,
    });
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHero(
            badge: const Icon(LucideIcons.qrCode),
            title: name,
            subtitle: context.l10n.qrHandoffSheetTitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              children: [
                // White backing box: QR codes render solid black on
                // transparent by default, which is unreadable (and
                // unscannable) against this app's dark surfaces — matches
                // the mockup's white QR tile too.
                Container(
                  padding: const EdgeInsets.all(Spacing.md2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: Radii.cardR,
                  ),
                  child: QrImageView(
                    data: payload,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                _GhostBlockButton(
                  label: context.l10n.qrHandoffCopyButton,
                  icon: LucideIcons.copy,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: payload));
                    if (context.mounted) {
                      showSuccess(context, context.l10n.qrHandoffCopied);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block`: full-width, `surface-2`
/// background, 1px border, text then a trailing icon.
class _GhostBlockButton extends StatelessWidget {
  const _GhostBlockButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
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
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, size: 16, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}
