import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/ui/pressable.dart';
import '../explorer_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ExplorerSelectionAppBar extends StatelessWidget {
  const ExplorerSelectionAppBar({
    super.key,
    required this.state,
    required this.onClose,
    required this.onBatchRename,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onInvertSelection,
  });

  final ExplorerState state;
  final VoidCallback onClose;
  final VoidCallback onBatchRename;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onInvertSelection;

  @override
  Widget build(BuildContext context) {
    final allSelected =
        state.selected.length == state.entries.length &&
        state.entries.isNotEmpty;
    return AppBar(
      key: const ValueKey('selection_app_bar'),
      leading: _IconBtn(
        icon: LucideIcons.x,
        tooltip: context.l10n.clearSelectionTooltip,
        onTap: onClose,
      ),
      title: Text(
        context.l10n.nSelected(state.selected.length),
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.19,
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(44),
        child: SizedBox.shrink(),
      ),
      actions: [
        _IconBtn(
          icon: LucideIcons.filePen,
          tooltip: context.l10n.batchRenameTooltip,
          onTap: onBatchRename,
        ),
        _IconBtn(
          icon: allSelected ? LucideIcons.square : LucideIcons.checkSquare,
          tooltip:
              allSelected
                  ? context.l10n.deselectAllTooltip
                  : context.l10n.selectAllTooltip,
          onTap: allSelected ? onClearSelection : onSelectAll,
        ),
        _IconBtn(
          icon: Icons.flip_to_back_rounded,
          tooltip: context.l10n.invertSelectionTooltip,
          onTap: onInvertSelection,
        ),
      ],
    );
  }
}

/// The mockup's `.iconbtn`: 34x34, transparent, 19px icon, scale-.92 press.
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Pressable(
      onTap: onTap,
      pressedScale: 0.92,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
