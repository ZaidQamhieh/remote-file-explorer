import 'package:flutter/material.dart';

/// A simple text-field dialog for entering a destination path, used by the
/// copy/move actions in the multi-select bar. Returns the trimmed text via
/// [Navigator.pop], or `null` if cancelled.
class DestinationDialog extends StatelessWidget {
  const DestinationDialog({super.key, required this.hint});
  final String hint;

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    return AlertDialog(
      title: const Text('Destination'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
