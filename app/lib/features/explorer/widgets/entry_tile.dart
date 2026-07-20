import 'package:flutter/material.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/models/entry.dart';
import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/entry_leading.dart';
import '../../../core/ui/format.dart';
import '../thumbnail_image.dart';
import 'entry_drag.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    this.isFavorite = false,
    this.isPinned = false,
    this.onShowMeta,
    this.onBookmark,
    this.onPeek,
    this.client,
  });

  final Entry entry;

  /// When provided, image rows show a server-rendered thumbnail in the leading
  /// square (with the category icon as the fallback). When null, the row keeps
  /// the plain category icon — so the tile degrades gracefully without a client.
  final AgentClient? client;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;
  final Future<void> Function(Entry dragged, String destFolder)? onMoveInto;
  final EntryDensity density;

  /// Whether [entry] is a favorited folder — shows a small star badge on the
  /// leading icon container. Has no effect for files.
  final bool isFavorite;

  /// Whether [entry] is pinned for offline caching — shows a small pin badge
  /// on the leading icon container. Has no effect for files.
  final bool isPinned;

  /// Opens this entry's detail sheet (e.g. to favorite/unfavorite a folder).
  /// When set for a directory, the trailing chevron becomes tappable; has no
  /// effect for files (which already open their sheet via [onTap]).
  final VoidCallback? onShowMeta;

  /// When set and NOT in multiSelect mode, long-press opens the bookmark
  /// sheet instead of entering selection mode.
  final VoidCallback? onBookmark;

  /// When set, long-pressing the leading icon/thumbnail (a target distinct
  /// from the row's own long-press) shows a quick preview peek instead of
  /// the row's usual long-press behavior. Has no effect for directories.
  final VoidCallback? onPeek;

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

    Widget leading =
        multiSelect
            ? Checkbox(value: selected, onChanged: (_) => onSelect())
            : _IconTile(
              entry: entry,
              compact: compact,
              isFavorite: isFavorite && entry.isDir,
              isPinned: isPinned && entry.isDir,
              client: client,
            );

    // Long-pressing the icon/thumbnail specifically (not the row) shows a
    // quick preview peek — a target distinct from the row's own long-press
    // (bookmark/select) so neither gesture steals the other.
    if (!multiSelect && !entry.isDir && onPeek != null) {
      leading = GestureDetector(onLongPress: onPeek, child: leading);
    }

    final nameStyle = Theme.of(context).textTheme.titleMedium;
    final metaStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final Widget content =
        compact
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
        onLongPress:
            (!multiSelect && onBookmark != null) ? onBookmark : onLongPress,
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
                onShowMeta != null
                    ? IconButton(
                      icon: Icon(
                        LucideIcons.chevronRight,
                        color: scheme.primary,
                      ),
                      tooltip: context.l10n.folderDetailsTooltip,
                      onPressed: onShowMeta,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                    : Icon(LucideIcons.chevronRight, color: scheme.primary),
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
/// comfortable density, 32dp in compact. When [isFavorite] is set, overlays a
/// small star badge on the container's corner.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.entry,
    required this.compact,
    this.isFavorite = false,
    this.isPinned = false,
    this.client,
  });

  final Entry entry;
  final bool compact;
  final bool isFavorite;
  final bool isPinned;
  final AgentClient? client;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = compact ? 32.0 : 40.0;
    final container = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            dark
                ? figmaIconBg(entry)
                : entry.isDir
                ? scheme.primary.withValues(alpha: 0.16)
                : scheme.surfaceContainerHighest,
        borderRadius: Radii.smR,
      ),
      alignment: Alignment.center,
      child: EntryLeading(entry: entry, size: size * 0.55),
    );

    // Image files: show the server thumbnail inside the same tonal square,
    // falling back to the category icon while loading / when unavailable.
    // Only when a client is available; images are never favorited folders, so
    // this returns before the star-badge path below.
    final isImage = !entry.isDir && (entry.mimeType ?? '').startsWith('image/');
    if (client != null && isImage) {
      return ClipRRect(
        borderRadius: Radii.smR,
        child: SizedBox(
          width: size,
          height: size,
          child: ThumbnailImage(
            entry: entry,
            client: client!,
            size: 128,
            fallback: container,
          ),
        ),
      );
    }

    if (!isFavorite && !isPinned) return container;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        container,
        if (isFavorite)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.star, size: 12, color: Brand.amber),
            ),
          ),
        if (isPinned)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.pin, size: 11, color: scheme.primary),
            ),
          ),
      ],
    );
  }
}
