import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';

/// Maximum number of crumbs shown before head ancestors collapse into a
/// `…` menu chip. The root and the tail crumbs (ending with the current
/// directory) are always visible.
const int kMaxVisibleCrumbs = 4;

/// Returns the indices of [stackLength] path-stack entries that should
/// collapse behind a `…` menu chip, given [maxVisible] total visible crumbs.
///
/// Pure function (no widget dependencies) so the collapse policy can be unit
/// tested directly. The root (index 0) and the current directory (the last
/// index) are always visible, plus up to `maxVisible - 1` more ancestors
/// immediately preceding it; everything strictly between collapses. Returns
/// an empty list when [stackLength] already fits within [maxVisible].
///
/// Example: `stackLength=6, maxVisible=4` → visible = `[0, 3, 4, 5]`,
/// collapsed = `[1, 2]`.
List<int> collapsedCrumbIndices(
  int stackLength, {
  int maxVisible = kMaxVisibleCrumbs,
}) {
  if (stackLength <= maxVisible) return const [];
  // At least the current directory (1) stays visible in the tail, even for
  // degenerate maxVisible <= 1.
  final visibleTailCount = (maxVisible - 1).clamp(1, stackLength);
  final firstVisibleTail = stackLength - visibleTailCount;
  // firstVisibleTail is guaranteed >= 1 here, so indices 1..firstVisibleTail-1
  // form a valid (possibly empty) range.
  return List.generate(firstVisibleTail - 1, (i) => i + 1);
}

/// Horizontal scrolling row of M3 chips, one per path segment, shown in the
/// explorer's app bar. The current directory renders as a filled-tonal chip,
/// ancestors as outlined chips, separated by chevrons. When the path is deep,
/// head ancestors collapse into a `…` chip that opens a menu listing them.
///
/// Tapping a chip jumps to that ancestor directory (via [onNavigateTo]).
/// Long-pressing a chip copies its absolute path to the clipboard. Dragging
/// an entry onto a chip (when [onMoveInto] is provided) moves it there.
///
/// Only depends on [pathStack] + [onNavigateTo] (not the full
/// `ExplorerState`/`ExplorerNotifier`) so other navigable listings — e.g. the
/// destination picker sheet — can reuse it with their own state/notifier.
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.pathStack,
    required this.onNavigateTo,
    this.onMoveInto,
  });

  /// Path segments from the filesystem root to the current directory (see
  /// `buildPathStack`).
  final List<String> pathStack;

  /// Called with the path-stack index to navigate to when a crumb (or a
  /// collapsed-menu entry) is tapped.
  final void Function(int index) onNavigateTo;

  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final stack = pathStack;
    final lastIndex = stack.length - 1;
    // Contiguous range of head-ancestor indices to collapse (e.g. [1, 2]),
    // or empty if the path fits without collapsing.
    final collapsedRange = collapsedCrumbIndices(stack.length);
    final collapsed = collapsedRange.toSet();

    final children = <Widget>[];
    for (var i = 0; i < stack.length; i++) {
      if (collapsed.contains(i)) {
        // Emit one "…" menu chip for the whole collapsed range, at its first
        // index, then skip the rest of the range.
        if (i == collapsedRange.first) {
          children.add(_separator(context, show: i > 0));
          children.add(
            _CollapsedChip(
              pathStack: stack,
              onNavigateTo: onNavigateTo,
              indices: collapsedRange,
            ),
          );
        }
        continue;
      }
      children.add(_separator(context, show: i > 0));
      children.add(
        _Crumb(
          pathStack: stack,
          onNavigateTo: onNavigateTo,
          index: i,
          isCurrent: i == lastIndex,
          onMoveInto: onMoveInto,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _separator(BuildContext context, {required bool show}) {
    if (!show) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      child: Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
    );
  }
}

/// Label for the path-stack entry at [index] — `/` for the root, otherwise
/// the final path segment.
String crumbLabel(List<String> stack, int index) =>
    index == 0 ? '/' : stack[index].split(RegExp(r'[/\\]')).last;

/// Copies [path] to the clipboard and shows a confirmation snackbar.
void copyPathToClipboard(BuildContext context, String path) {
  Clipboard.setData(ClipboardData(text: path));
  HapticFeedback.selectionClick();
  showInfo(context, context.l10n.copiedPath(path));
}

/// A single breadcrumb chip: filled-tonal for the current directory,
/// outlined for ancestors. Tap navigates, long-press copies the path.
class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.pathStack,
    required this.onNavigateTo,
    required this.index,
    required this.isCurrent,
    this.onMoveInto,
  });

  final List<String> pathStack;
  final void Function(int index) onNavigateTo;
  final int index;
  final bool isCurrent;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stack = pathStack;
    final label = crumbLabel(stack, index);
    final path = stack[index];

    final chip = Material(
      color: isCurrent ? scheme.secondaryContainer : Colors.transparent,
      shape: StadiumBorder(
        side:
            isCurrent
                ? BorderSide.none
                : BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => onNavigateTo(index),
        onLongPress: () => copyPathToClipboard(context, path),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color:
                  isCurrent
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );

    if (onMoveInto == null) {
      return ClipPath(clipper: const _StadiumClipper(), child: chip);
    }

    return DragTarget<Entry>(
      onWillAcceptWithDetails: (d) => d.data.path != path,
      onAcceptWithDetails: (d) => onMoveInto!(d.data, path),
      builder:
          (ctx, cand, rej) => AnimatedContainer(
            duration: MotionDuration.short,
            decoration: ShapeDecoration(
              shape: StadiumBorder(
                side:
                    cand.isNotEmpty
                        ? BorderSide(color: scheme.primary, width: 2)
                        : const BorderSide(color: Colors.transparent, width: 2),
              ),
            ),
            child: ClipPath(clipper: const _StadiumClipper(), child: chip),
          ),
    );
  }
}

/// `ClipPath` clipper matching a [StadiumBorder] shape, used so the chip's
/// [InkWell] ripple stays within the pill outline.
class _StadiumClipper extends CustomClipper<Path> {
  const _StadiumClipper();

  @override
  Path getClip(Size size) =>
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
      );

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// The `…` chip shown when head ancestors collapse. Tapping opens a popup
/// menu listing the collapsed ancestors (root excluded, since it always has
/// its own visible chip); selecting one navigates there.
class _CollapsedChip extends StatelessWidget {
  const _CollapsedChip({
    required this.pathStack,
    required this.onNavigateTo,
    required this.indices,
  });

  final List<String> pathStack;
  final void Function(int index) onNavigateTo;
  final List<int> indices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stack = pathStack;

    return PopupMenuButton<int>(
      tooltip: context.l10n.showHiddenFoldersTooltip,
      onSelected: onNavigateTo,
      itemBuilder:
          (_) =>
              indices
                  .map(
                    (i) => PopupMenuItem(
                      value: i,
                      child: Text(crumbLabel(stack, i)),
                    ),
                  )
                  .toList(),
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Text(
            '…',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
