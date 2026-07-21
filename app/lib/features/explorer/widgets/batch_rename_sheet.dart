import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/gradient_button.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/ui/sheet_chrome.dart';
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
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHero(
            badge: const Icon(LucideIcons.filePen),
            title: context.l10n.renameNItemsTitle(widget.names.length),
            subtitle:
                _mode == BatchRenameMode.pattern
                    ? context.l10n.patternLabel
                    : context.l10n.findAndReplaceLabel,
            onClose: () => Navigator.pop(context),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg + viewInsets,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SegmentedControl(
                  options: [
                    context.l10n.findAndReplaceLabel,
                    context.l10n.patternLabel,
                  ],
                  selectedIndex: _mode == BatchRenameMode.findReplace ? 0 : 1,
                  onChanged:
                      (i) => setState(
                        () =>
                            _mode =
                                i == 0
                                    ? BatchRenameMode.findReplace
                                    : BatchRenameMode.pattern,
                      ),
                ),
                const SizedBox(height: Spacing.md),
                if (_mode == BatchRenameMode.pattern) ...[
                  ShadInput(
                    controller: _base,
                    placeholder: Text(context.l10n.baseNameLabel),
                    onChanged: (_) => setState(() {}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      context.l10n.baseNameHelperText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  ShadInput(
                    controller: _start,
                    keyboardType: TextInputType.number,
                    placeholder: Text(context.l10n.startNumberLabel),
                    onChanged: (_) => setState(() {}),
                  ),
                ] else ...[
                  ShadInput(
                    controller: _find,
                    placeholder: Text(context.l10n.findLabel),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Spacing.sm),
                  ShadInput(
                    controller: _replace,
                    placeholder: Text(context.l10n.replaceWithLabel),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                _PreviewList(oldNames: widget.names, newNames: preview),
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    onPressed: () => Navigator.pop(context, preview),
                    child: Text(context.l10n.renameNItems(widget.names.length)),
                  ),
                ),
              ],
            ),
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
                context.l10n.andNMore(count - shown),
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

/// The mockup's `.segmented`: a pill toggle track (`surface-2`, 3px padding),
/// the active option raised on `surface-3` with a subtle shadow — replaces
/// `SegmentedButton`.
class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final void Function(int index) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.smR,
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        i == selectedIndex
                            ? scheme.surfaceContainerHighest
                            : null,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow:
                        i == selectedIndex
                            ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ]
                            : null,
                  ),
                  child: Text(
                    options[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          i == selectedIndex
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
