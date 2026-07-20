import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/share_link.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/sheet_chrome.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet shown after minting an R1 one-time share link: the URL with
/// a copy button, a live expiry countdown, and a Revoke button.
class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.client, required this.link});

  final AgentClient client;
  final ShareLink link;

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
            SheetHero(
              badge: const Icon(LucideIcons.link),
              title: context.l10n.shareLinkSheetTitle,
              subtitle: widget.link.url,
              onClose: () => Navigator.pop(context),
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
                  QuickActionRow(
                    actions: [
                      GradientActionCircle(
                        icon: LucideIcons.copy,
                        label: context.l10n.copyButton,
                        gradient: const [Brand.seed, Brand.accent],
                        onTap: () => _copy(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  ActionListCard(
                    children: [
                      ActionListTile(
                        icon: LucideIcons.clock,
                        label:
                            expired
                                ? context.l10n.shareLinkExpired
                                : context.l10n.shareLinkExpiresIn(
                                  _format(_remaining),
                                ),
                        tint: expired ? scheme.error : null,
                        trailing: const SizedBox.shrink(),
                        onTap: () {},
                      ),
                      ActionListTile(
                        icon: LucideIcons.unlink,
                        label: context.l10n.shareLinkRevokeButton,
                        tint: scheme.error,
                        onTap: () => _revoke(context),
                      ),
                    ],
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
