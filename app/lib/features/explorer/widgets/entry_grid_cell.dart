import 'package:flutter/material.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/entry_leading.dart';
import '../../preview/image_preview.dart';
import '../thumbnail_image.dart';
import 'entry_drag.dart';

/// A single cell in the explorer's grid view: a square thumbnail (images) or
/// tonal icon, with the entry name below.
///
/// Supports tap, long-press (selection), and drag-to-move (via
/// [wrapDraggable]) when [onMoveInto] is provided.
class EntryGridCell extends StatelessWidget {
  const EntryGridCell({
    super.key,
    required this.entry,
    required this.client,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onLongPress,
    this.hostId,
    this.onMoveInto,
    this.isFavorite = false,
    this.isPinned = false,
    this.onBookmark,
  });

  final Entry entry;
  final AgentClient client;

  /// The host this entry lives on — used to build a stable, host-scoped
  /// [Hero] tag so an image thumbnail flies into its full-screen preview.
  /// When null, the thumbnail is not wrapped in a [Hero].
  final String? hostId;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;

  /// Whether [entry] is a favorited folder — shows a small star badge on the
  /// leading icon/thumbnail container. Has no effect for files.
  final bool isFavorite;

  /// Whether [entry] is pinned for offline caching — shows a small pin badge.
  /// Has no effect for files.
  final bool isPinned;

  /// When set and NOT in multiSelect mode, long-press opens the bookmark
  /// sheet instead of entering selection mode.
  final VoidCallback? onBookmark;

  /// Wraps [child] in a [Hero] when [hostId] is set so the thumbnail animates
  /// into the full-screen image preview (matching tag). A cheap flight on Skia
  /// (transform/opacity only — no shaders).
  Widget _maybeHero(Widget child) {
    if (hostId == null) return child;
    return Hero(
      tag: imagePreviewHeroTag(hostId!, entry.path),
      // Keep the rounded thumbnail shape through the flight.
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mime = entry.mimeType ?? '';
    final isImage = !entry.isDir && mime.startsWith('image/');

    final cell = Material(
      color:
          selected
              ? scheme.secondaryContainer.withValues(alpha: 0.65)
              : scheme.surfaceContainerLow,
      borderRadius: Radii.cardR,
      child: InkWell(
        borderRadius: Radii.cardR,
        onTap: onTap,
        onLongPress:
            (!multiSelect && onBookmark != null) ? onBookmark : onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.cardR,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          padding: const EdgeInsets.all(Spacing.sm),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isImage)
                    _maybeHero(
                      ClipRRect(
                        borderRadius: Radii.chipR,
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: ThumbnailImage(
                            entry: entry,
                            client: client,
                            fallback: Center(
                              child: EntryLeading(entry: entry, size: 40),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: Radii.chipR,
                      ),
                      alignment: Alignment.center,
                      child: EntryLeading(entry: entry, size: 32),
                    ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    entry.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              if (isFavorite && entry.isDir)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: Colors.amber,
                    ),
                  ),
                ),
              if (isPinned && entry.isDir)
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 12,
                      color: scheme.primary,
                    ),
                  ),
                ),
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
      child: cell,
    );
  }
}
