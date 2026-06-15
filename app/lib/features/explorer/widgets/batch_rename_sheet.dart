import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../batch_rename.dart';

/// Modal sheet for batch-renaming [names] (basenames, in selection order).
/// Pops a `List<String>` of the new basenames (same length/order as [names])
/// when the user applies, or `null` on cancel.
class BatchRenameSheet extends StatefulWidget {
  const BatchRenameSheet({super.key, required this.names});

  final List<String> names;

  /// Shows the sheet and returns the chosen new basenames, or null if cancelled.
  static Future<List<String>?> show(BuildContext context, List<String> names) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BatchRenameSheet(names: names),
    );
  }

  @override
  State<BatchRenameSheet> createState() => _BatchRenameSheetState();
}

class _BatchRenameSheetState extends State<BatchRenameSheet> {
  BatchRenameMode _mode = BatchRenameMode.pattern;
  final _base = TextEditingController(text: 'File');
  final _start = TextEditingController(text: '1');
  final _find = TextEditingController();
  final _replace = TextEditingController();

  @override
  void dispose() {
    _base.dispose();
    _start.dispose();
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  List<String> _compute() => computeBatchRenames(
    names: widget.names,
    mode: _mode,
    base: _base.text.trim(),
    startNumber: int.tryParse(_start.text.trim()) ?? 1,
    find: _find.text,
    replace: _replace.text,
  );

  @override
  Widget build(BuildContext context) {
    final preview = _compute();
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg + viewInsets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rename ${widget.names.length} items',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Spacing.md),
          SegmentedButton<BatchRenameMode>(
            segments: const [
              ButtonSegment(
                value: BatchRenameMode.pattern,
                label: Text('Pattern'),
                icon: Icon(Icons.format_list_numbered),
              ),
              ButtonSegment(
                value: BatchRenameMode.findReplace,
                label: Text('Find & replace'),
                icon: Icon(Icons.find_replace),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: Spacing.md),
          if (_mode == BatchRenameMode.pattern) ...[
            TextField(
              controller: _base,
              decoration: const InputDecoration(
                labelText: 'Base name',
                helperText: 'Use {n} to place the number; else it’s appended.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _start,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Start number'),
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            TextField(
              controller: _find,
              decoration: const InputDecoration(labelText: 'Find'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _replace,
              decoration: const InputDecoration(labelText: 'Replace with'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: Spacing.md),
          _PreviewList(oldNames: widget.names, newNames: preview),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: () => Navigator.pop(context, preview),
                child: Text('Rename ${widget.names.length}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewList extends StatelessWidget {
  const _PreviewList({required this.oldNames, required this.newNames});

  final List<String> oldNames;
  final List<String> newNames;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = oldNames.length;
    final shown = count > 3 ? 3 : count;
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.cardR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shown; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${oldNames[i]}  →  ${newNames[i]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (count > shown)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '… and ${count - shown} more',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
