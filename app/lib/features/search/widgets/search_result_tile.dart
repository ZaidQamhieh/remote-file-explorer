import 'package:flutter/material.dart';

import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';
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
    final subtitleParts = <String>[
      entry.path,
      if (!entry.isDir) formatSize(entry.size),
      if (entry.modified != null) formatDate(entry.modified!),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      leading: resultIcon(entry),
      title: _highlightedName(context),
      subtitle: Text(
        subtitleParts.where((s) => s.isNotEmpty).join('  ·  '),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: entry.isDir ? const Icon(LucideIcons.chevronRight) : null,
      onTap: onTap,
    );
  }

  Widget _highlightedName(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final range = highlight ? highlightRange(entry.name, query) : null;
    if (range == null) {
      return Text(
        entry.name,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    final highlightStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.bold,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
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

Icon resultIcon(Entry entry) {
  if (entry.isDir) {
    return const Icon(LucideIcons.folder, color: Colors.amber);
  }
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('image/')) {
    return const Icon(LucideIcons.image, color: Colors.blue);
  }
  if (mime.startsWith('video/')) {
    return const Icon(LucideIcons.video, color: Colors.purple);
  }
  if (mime.startsWith('audio/')) {
    return const Icon(LucideIcons.music, color: Colors.green);
  }
  if (mime.contains('pdf')) {
    return const Icon(LucideIcons.fileText, color: Colors.red);
  }
  if (mime.contains('zip') || mime.contains('archive')) {
    return const Icon(LucideIcons.fileArchive, color: Colors.orange);
  }
  if (mime.startsWith('text/') || mime.contains('json')) {
    return const Icon(LucideIcons.fileText, color: Colors.teal);
  }
  return const Icon(LucideIcons.file);
}
