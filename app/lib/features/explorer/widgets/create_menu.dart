import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/sheet_chrome.dart';
import '../explorer_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom-sheet menu for the "New" FAB: create a folder or an empty file in
/// the current directory.
class CreateMenu extends StatelessWidget {
  const CreateMenu({super.key, required this.notifier});
  final ExplorerNotifier notifier;

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
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(hintText: ctx.l10n.nameHint),
            ),
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
          ),
    );
  }
}
