import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
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
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.qrCode),
                const SizedBox(width: Spacing.sm),
                Text(
                  context.l10n.qrHandoffSheetTitle,
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Center(child: QrImageView(data: payload, size: 240)),
            const SizedBox(height: Spacing.md),
            Text(
              name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
