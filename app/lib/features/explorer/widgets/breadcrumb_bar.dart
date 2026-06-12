import 'package:flutter/material.dart';

import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../explorer_state.dart';

/// Horizontal scrolling row of path-segment chips, shown in the explorer's
/// app bar. Tapping a chip jumps to that ancestor directory; dragging an
/// entry onto a chip (when [onMoveInto] is provided) moves it there.
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.state,
    required this.notifier,
    this.onMoveInto,
  });
  final ExplorerState state;
  final ExplorerNotifier notifier;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  @override
  Widget build(BuildContext context) {
    final stack = state.pathStack;
    final scheme = Theme.of(context).colorScheme;
    final lastIndex = stack.length - 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(stack.length, (i) {
            final label =
                i == 0 ? '/' : stack[i].split(RegExp(r'[/\\]')).last;
            final isCurrent = i == lastIndex;

            final chip = Material(
              color: isCurrent
                  ? scheme.primaryContainer
                  : scheme.secondaryContainer.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(borderRadius: Radii.chipR),
              child: InkWell(
                borderRadius: Radii.chipR,
                onTap: () => notifier.navigateTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isCurrent
                              ? scheme.onPrimaryContainer
                              : scheme.onSecondaryContainer,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            );

            final crumb = onMoveInto != null
                ? DragTarget<Entry>(
                    onWillAcceptWithDetails: (d) => d.data.path != stack[i],
                    onAcceptWithDetails: (d) =>
                        onMoveInto!(d.data, stack[i]),
                    builder: (ctx, cand, rej) => AnimatedContainer(
                      duration: MotionDuration.short,
                      decoration: BoxDecoration(
                        borderRadius: Radii.chipR,
                        border: cand.isNotEmpty
                            ? Border.all(color: scheme.primary, width: 2)
                            : Border.all(color: Colors.transparent, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: Radii.chipR,
                        child: chip,
                      ),
                    ),
                  )
                : ClipRRect(borderRadius: Radii.chipR, child: chip);

            return Padding(
              padding: const EdgeInsets.only(right: Spacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Spacing.xs),
                      child: Icon(Icons.chevron_right,
                          size: 18, color: scheme.outline),
                    ),
                  crumb,
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
