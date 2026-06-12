import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/entry.dart';

/// Wraps an entry [child] so it can be long-press dragged and (for folders)
/// act as a drop target that moves the dropped entry into itself. In
/// multi-select mode dragging is disabled to avoid clashing with tap-to-toggle.
///
/// Shared by the explorer's list tile and grid cell so both render
/// drag/drop affordances identically.
Widget wrapDraggable({
  required BuildContext context,
  required Entry entry,
  required bool multiSelect,
  required Future<void> Function(Entry dragged, String destFolder)? onMoveInto,
  required Widget child,
}) {
  Widget tile = child;
  if (multiSelect || onMoveInto == null) {
    // Selection mode (or no move handler): keep tap-to-toggle, skip drag.
    if (entry.isDir && onMoveInto != null) {
      return folderDropTarget(context, entry, onMoveInto, tile);
    }
    return tile;
  }
  tile = LongPressDraggable<Entry>(
    data: entry,
    onDragStarted: HapticFeedback.mediumImpact,
    feedback: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.drag_indicator),
          const SizedBox(width: 4),
          Text(entry.name),
        ]),
      ),
    ),
    childWhenDragging: Opacity(opacity: 0.4, child: tile),
    child: tile,
  );
  if (entry.isDir) {
    tile = folderDropTarget(context, entry, onMoveInto, tile);
  }
  return tile;
}

/// A [DragTarget] that accepts an [Entry] dragged onto the folder [entry] and
/// moves it in, highlighting while a candidate hovers.
Widget folderDropTarget(
  BuildContext context,
  Entry entry,
  Future<void> Function(Entry dragged, String destFolder) onMoveInto,
  Widget child,
) {
  return DragTarget<Entry>(
    onWillAcceptWithDetails: (d) => d.data.path != entry.path,
    onAcceptWithDetails: (d) => onMoveInto(d.data, entry.path),
    builder: (ctx, cand, rej) => Container(
      decoration: cand.isNotEmpty
          ? BoxDecoration(
              color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: child,
    ),
  );
}
