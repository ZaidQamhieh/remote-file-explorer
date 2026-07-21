import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
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
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: payload));
                      if (context.mounted) {
                        showSuccess(context, context.l10n.qrHandoffCopied);
                      }
                    },
                    icon: const Icon(LucideIcons.copy),
                    label: Text(context.l10n.qrHandoffCopyButton),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
