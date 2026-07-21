import 'package:flutter/material.dart';

import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/pressable.dart';
import '../search_logic.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.entry,
    required this.query,
    required this.highlight,
    required this.onTap,
  });

  final Entry entry;
  final String query;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[
      entry.path,
      if (!entry.isDir) formatSize(entry.size),
      if (entry.modified != null) formatDate(entry.modified!),
    ];
    // Mockup's `.row`: 38x38 tinted `.row-icon`, 14px/500 title, 11.5px
    // faint monospace subtitle (the search result's path).
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 11,
          horizontal: Spacing.xs,
        ),
        child: Row(
          children: [
            _resultIconTile(entry),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _highlightedName(context),
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.where((s) => s.isNotEmpty).join('  ·  '),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'JetBrains Mono',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (entry.isDir) ...[
              const SizedBox(width: Spacing.xs),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _highlightedName(BuildContext context) {
    const baseStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final range = highlight ? highlightRange(entry.name, query) : null;
    if (range == null) {
      return Text(
        entry.name,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    final highlightStyle = baseStyle.copyWith(
      fontWeight: FontWeight.bold,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        children: [
          TextSpan(text: entry.name.substring(0, range.start)),
          TextSpan(
            text: entry.name.substring(range.start, range.end),
            style: highlightStyle,
          ),
          TextSpan(text: entry.name.substring(range.end)),
        ],
      ),
    );
  }
}

/// The mockup's `.row-icon`: 38x38 rounded square (`Radii.smR`, r-md) with a
/// .14-alpha tint of the entry's category colour.
Widget _resultIconTile(Entry entry) {
  final icon = resultIcon(entry);
  final color = icon.color ?? Colors.grey;
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: Radii.smR,
    ),
    alignment: Alignment.center,
    child: Icon(icon.icon, color: color, size: 19),
  );
}

Icon resultIcon(Entry entry) {
  if (entry.isDir) {
    return const Icon(LucideIcons.folder, color: Brand.amber);
  }
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('image/')) {
    return const Icon(LucideIcons.image, color: Brand.seed);
  }
  if (mime.startsWith('video/')) {
    return const Icon(LucideIcons.video, color: Brand.accent);
  }
  if (mime.startsWith('audio/')) {
    return const Icon(LucideIcons.music, color: Brand.online);
  }
  if (mime.contains('pdf')) {
    return const Icon(LucideIcons.fileText, color: Brand.red);
  }
  if (mime.contains('zip') || mime.contains('archive')) {
    return const Icon(LucideIcons.fileArchive, color: Brand.amber);
  }
  if (mime.startsWith('text/') || mime.contains('json')) {
    return const Icon(LucideIcons.fileText, color: Colors.teal);
  }
  return const Icon(LucideIcons.file);
}
