import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../clipboard_state.dart';

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
          FloatingActionButton.small(
            heroTag: 'fab_paste',
            tooltip: context.l10n.pasteNItems(clipboard!.paths.length),
            onPressed: onPaste,
            child: const Icon(Icons.content_paste),
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton.small(
          heroTag: 'fab_upload',
          tooltip: context.l10n.uploadFileTooltip,
          onPressed: onUpload,
          child: const Icon(Icons.upload_file),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'fab_new',
          onPressed: onNew,
          icon: const Icon(Icons.add),
          label: Text(context.l10n.newButton),
        ),
      ],
    );
  }
}
