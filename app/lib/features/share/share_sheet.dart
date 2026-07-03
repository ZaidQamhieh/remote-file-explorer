import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/agent_client.dart';
import '../../core/l10n_ext.dart';
import '../../core/models/share_link.dart';
import '../../core/ui/feedback.dart';
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
        showError(context, context.l10n.shareLinkFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expired = _remaining == Duration.zero;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.link),
                const SizedBox(width: 8),
                Text(
                  context.l10n.shareLinkSheetTitle,
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: SelectableText(widget.link.url, maxLines: 2)),
                IconButton(
                  icon: const Icon(LucideIcons.copy),
                  tooltip: context.l10n.copyButton,
                  onPressed: () => _copy(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              expired
                  ? context.l10n.shareLinkExpired
                  : context.l10n.shareLinkExpiresIn(_format(_remaining)),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: expired ? scheme.error : null,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(LucideIcons.unlink),
                label: Text(context.l10n.shareLinkRevokeButton),
                onPressed: () => _revoke(context),
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
