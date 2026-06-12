import 'package:flutter/material.dart';

import '../../../core/models/entry.dart';
import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/entry_leading.dart';
import '../../../core/ui/format.dart';
import 'entry_drag.dart';

/// A single row in the explorer's list view: leading icon (or checkbox in
/// multi-select mode), name + size/date metadata, and a chevron for folders.
///
/// Renders in two densities (see [EntryDensity]):
/// - **comfortable** (default, ~72dp): 40dp r12 leading container, name on
///   its own `titleMedium` line, metadata below as `bodySmall` with `·`
///   separators.
/// - **compact** (~52dp): 32dp leading container, single line — name then
///   metadata inline, separated by `·`.
///
/// Selected rows paint an r16 `primaryContainer` behind the tile; otherwise
/// the tile is borderless on `surface`.
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
    this.density = EntryDensity.comfortable,
  });

  final Entry entry;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;
  final EntryDensity density;

  /// File metadata (size · date), joined with `·`. Empty for directories.
  String get _meta {
    if (entry.isDir) return '';
    final parts = <String>[];
    final size = formatSize(entry.size);
    if (size.isNotEmpty) parts.add(size);
    if (entry.modified != null) parts.add(formatDate(entry.modified!));
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = density == EntryDensity.compact;
    final meta = _meta;

    final Widget leading = multiSelect
        ? Checkbox(value: selected, onChanged: (_) => onSelect())
        : _IconTile(entry: entry, compact: compact);

    final nameStyle = Theme.of(context).textTheme.titleMedium;
    final metaStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);

    final Widget content = compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: Spacing.sm),
                Text(meta, overflow: TextOverflow.ellipsis, style: metaStyle),
              ],
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.name,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(meta, overflow: TextOverflow.ellipsis, style: metaStyle),
              ],
            ],
          );

    Widget tile = Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      borderRadius: Radii.cardR,
      child: InkWell(
        borderRadius: Radii.cardR,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: compact ? Spacing.xs : Spacing.sm,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: Spacing.md),
              Expanded(child: content),
              if (entry.isDir)
                Icon(Icons.chevron_right_rounded, color: scheme.outline),
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

/// File-type icon presented inside a tonal rounded square — 40dp (r12) in
/// comfortable density, 32dp in compact.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.entry, required this.compact});

  final Entry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = compact ? 32.0 : 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.smR,
      ),
      alignment: Alignment.center,
      child: EntryLeading(entry: entry, size: size * 0.55),
    );
  }
}
