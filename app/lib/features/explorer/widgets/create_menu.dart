import 'package:flutter/material.dart';

import '../../../core/ui/feedback.dart';
import '../explorer_state.dart';

/// Bottom-sheet menu for the "New" FAB: create a folder or an empty file in
/// the current directory.
class CreateMenu extends StatelessWidget {
  const CreateMenu({super.key, required this.notifier});
  final ExplorerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder'),
            onTap: () {
              Navigator.pop(context);
              _showNameDialog(context, 'New folder', isFolder: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('New file'),
            onTap: () {
              Navigator.pop(context);
              _showNameDialog(context, 'New file', isFolder: false);
            },
          ),
        ],
      ),
    );
  }

  void _showNameDialog(BuildContext context, String title,
      {required bool isFolder}) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
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
                if (context.mounted) showSuccess(context, 'Created $name');
              } catch (e) {
                if (context.mounted) {
                  showError(context, 'Couldn\'t create $name: $e');
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
