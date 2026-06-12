import 'package:flutter/material.dart';

import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/entry_leading.dart';
import '../../../core/ui/format.dart';
import 'entry_drag.dart';

/// A single row in the explorer's list view: leading icon (or checkbox in
/// multi-select mode), name + size/date subtitle, and a chevron for folders.
///
/// Supports tap, long-press (selection), and drag-to-move (via
/// [wrapDraggable]) when [onMoveInto] is provided.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onLongPress,
    required this.onSelect,
    this.onMoveInto,
  });

  final Entry entry;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = entry.isDir
        ? null
        : formatSize(entry.size) +
            (entry.modified != null
                ? '  ·  ${formatDate(entry.modified!)}'
                : '');

    Widget leading = multiSelect
        ? Checkbox(value: selected, onChanged: (_) => onSelect())
        : _IconTile(entry: entry);

    Widget tile = Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.55) : Colors.transparent,
      borderRadius: Radii.cardR,
      child: InkWell(
        borderRadius: Radii.cardR,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.isDir)
                Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
    return wrapDraggable(
      context: context,
      entry: entry,
      multiSelect: multiSelect,
      onMoveInto: onMoveInto,
      child: tile,
    );
  }
}

/// File-type icon presented inside a tonal rounded square — the roomier,
/// "distinctive modern" leading element for list rows.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.entry});

  static const double _size = 44;

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.chipR,
      ),
      alignment: Alignment.center,
      child: EntryLeading(entry: entry, size: _size * 0.5),
    );
  }
}
