import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n_ext.dart';
import '../clipboard_state.dart';

/// Figma's stacked-pill FAB cluster: ghost dark pills for secondary actions
/// (paste, upload) + a solid accent pill for the primary "new" action.
class ExplorerFab extends StatelessWidget {
  const ExplorerFab({
    super.key,
    required this.clipboard,
    required this.hostId,
    required this.multiSelect,
    required this.onPaste,
    required this.onUpload,
    required this.onNew,
  });

  final FileClipboard? clipboard;
  final String hostId;
  final bool multiSelect;
  final VoidCallback onPaste;
  final VoidCallback onUpload;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final showPaste =
        clipboard != null &&
        !clipboard!.isEmpty &&
        clipboard!.hostId == hostId &&
        !multiSelect;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showPaste) ...[
          _GhostPill(
            icon: LucideIcons.clipboardPaste,
            label: context.l10n.pasteNItems(clipboard!.paths.length),
            onPressed: onPaste,
          ),
          const SizedBox(height: 8),
        ],
        _GhostPill(
          icon: LucideIcons.upload,
          label: context.l10n.uploadFileTooltip,
          onPressed: onUpload,
        ),
        const SizedBox(height: 8),
        _SolidPill(
          icon: LucideIcons.plus,
          label: context.l10n.newButton,
          onPressed: onNew,
        ),
      ],
    );
  }
}

/// Dark ghost pill — `bg #27272a`, `border #3f3f46`.
class _GhostPill extends StatelessWidget {
  const _GhostPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF27272A),
      shape: const StadiumBorder(side: BorderSide(color: Color(0xFF3F3F46))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Solid accent pill — the primary action.
class _SolidPill extends StatelessWidget {
  const _SolidPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
