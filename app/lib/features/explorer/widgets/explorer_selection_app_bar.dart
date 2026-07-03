import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
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
      leading: IconButton(
        icon: const Icon(LucideIcons.x),
        tooltip: context.l10n.clearSelectionTooltip,
        onPressed: onClose,
      ),
      title: Text(
        context.l10n.nSelected(state.selected.length),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(44),
        child: SizedBox.shrink(),
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.filePen),
          tooltip: context.l10n.batchRenameTooltip,
          onPressed: onBatchRename,
        ),
        IconButton(
          icon: Icon(
            allSelected ? LucideIcons.square : LucideIcons.checkSquare,
          ),
          tooltip:
              allSelected
                  ? context.l10n.deselectAllTooltip
                  : context.l10n.selectAllTooltip,
          onPressed: allSelected ? onClearSelection : onSelectAll,
        ),
        IconButton(
          icon: const Icon(Icons.flip_to_back_rounded),
          tooltip: context.l10n.invertSelectionTooltip,
          onPressed: onInvertSelection,
        ),
      ],
    );
  }
}
