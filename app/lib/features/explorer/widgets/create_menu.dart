import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/sheet_chrome.dart';
import '../explorer_state.dart';

/// Bottom-sheet menu for the "New" FAB: create a folder or an empty file in
/// the current directory, plus (when provided) upload and paste — the
/// mockup's `.files-fab` tap only ever shows a mock toast, so this sheet's
/// contents have no literal markup to match; it keeps its existing
/// quick-action-circle shape and just gains the two extra real actions.
class CreateMenu extends StatelessWidget {
  const CreateMenu({
    super.key,
    required this.notifier,
    this.onUpload,
    this.onPaste,
    this.pasteLabel,
  });
  final ExplorerNotifier notifier;
  final VoidCallback? onUpload;
  final VoidCallback? onPaste;
  final String? pasteLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetGrabber(),
            const SizedBox(height: Spacing.md),
            QuickActionRow(
              actions: [
                GradientActionCircle(
                  icon: LucideIcons.folderPlus,
                  label: context.l10n.newFolderButton,
                  gradient: [Colors.blue.shade400, Colors.blue.shade800],
                  onTap: () {
                    Navigator.pop(context);
                    _showNameDialog(
                      context,
                      context.l10n.newFolderButton,
                      isFolder: true,
                    );
                  },
                ),
                GradientActionCircle(
                  icon: LucideIcons.filePlus,
                  label: context.l10n.newFileButton,
                  gradient: [Colors.green.shade400, Colors.green.shade800],
                  onTap: () {
                    Navigator.pop(context);
                    _showNameDialog(
                      context,
                      context.l10n.newFileButton,
                      isFolder: false,
                    );
                  },
                ),
                if (onUpload != null)
                  GradientActionCircle(
                    icon: LucideIcons.upload,
                    label: context.l10n.uploadFileTooltip,
                    gradient: [Colors.orange.shade400, Colors.orange.shade800],
                    onTap: () {
                      Navigator.pop(context);
                      onUpload!();
                    },
                  ),
                if (onPaste != null)
                  GradientActionCircle(
                    icon: LucideIcons.clipboardPaste,
                    label: pasteLabel!,
                    gradient: [Colors.purple.shade400, Colors.purple.shade800],
                    onTap: () {
                      Navigator.pop(context);
                      onPaste!();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showNameDialog(
    BuildContext context,
    String title, {
    required bool isFolder,
  }) {
    final ctrl = TextEditingController();
    showShadDialog<void>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () async {
                  final name = ctrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    if (isFolder) {
                      await notifier.createFolder(name);
                    } else {
                      await notifier.createFile(name);
                    }
                    if (context.mounted) {
                      showSuccess(context, context.l10n.createdName(name));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showError(
                        context,
                        context.l10n.createFailed(name, humanizeError(e)),
                      );
                    }
                  }
                },
                child: Text(ctx.l10n.createButton),
              ),
            ],
            child: ShadInput(
              controller: ctrl,
              autofocus: true,
              placeholder: Text(ctx.l10n.nameHint),
            ),
          ),
    );
  }
}
