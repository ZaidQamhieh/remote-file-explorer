import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/share_link.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/sheet_chrome.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet shown after minting an R1 one-time share link: the URL with
/// a copy button, a live expiry countdown, and a Revoke button.
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.client,
    required this.link,
    required this.fileName,
  });

  final AgentClient client;
  final ShareLink link;

  /// Shown as the sheet's subtitle (mockup: "Share" / "Q3-roadmap.pdf") —
  /// the link URL is shown separately in the body's link row.
  final String fileName;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late final Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final remaining = widget.link.expiresAtDateTime.difference(DateTime.now());
    setState(
      () => _remaining = remaining.isNegative ? Duration.zero : remaining,
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.link.url));
    HapticFeedback.selectionClick();
    showInfo(context, context.l10n.copiedPath(widget.link.url));
  }

  Future<void> _revoke(BuildContext context) async {
    try {
      await widget.client.revokeShareLink(widget.link.tokenHash);
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) showInfo(context, context.l10n.shareLinkRevoked);
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.shareLinkFailed(humanizeError(e)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expired = _remaining == Duration.zero;
    return SafeArea(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Radii.sheetTopR,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHead(
              title: context.l10n.shareLinkSheetTitle,
              subtitle: widget.fileName,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Mockup's `.card` wrapping a link row + expiry row.
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: Radii.lgR,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        _LinkRow(
                          url: widget.link.url,
                          onCopy: () => _copy(context),
                          showDivider: true,
                        ),
                        _StatusRow(
                          icon: LucideIcons.clock,
                          label:
                              expired
                                  ? context.l10n.shareLinkExpired
                                  : context.l10n.shareLinkExpiresIn(
                                    _format(_remaining),
                                  ),
                          tint: expired ? scheme.error : null,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  _GhostBlockButton(
                    label: context.l10n.shareLinkRevokeButton,
                    icon: LucideIcons.unlink,
                    color: scheme.error,
                    onTap: () => _revoke(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mockup's `.row`: a mono URL title + a small `.btn-ghost.btn-sm`
/// "Copy" button, no leading icon (the mockup's link row is bare text).
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.url,
    required this.onCopy,
    required this.showDivider,
  });

  final String url;
  final VoidCallback onCopy;
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
          Expanded(
            child: Text(
              url,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Pressable(
            onTap: onCopy,
            pressedScale: 0.97,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: Radii.smR,
              ),
              child: Text(
                context.l10n.copyButton,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain icon + label row (the mockup's `.row` with no trailing action) —
/// used for the non-interactive expiry status line.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.showDivider,
    this.tint,
  });

  final IconData icon;
  final String label;
  final bool showDivider;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tint ?? scheme.onSurfaceVariant;
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
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block`, with an optional colour override
/// (e.g. destructive red for Revoke).
class _GhostBlockButton extends StatelessWidget {
  const _GhostBlockButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
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
                color: fg,
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}
