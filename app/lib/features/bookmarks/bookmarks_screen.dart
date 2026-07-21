import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/gradient_blob_hero.dart';
import '../../core/ui/grouped_card.dart' show SectionLabel;
import '../../core/ui/pressable.dart';
import '../../core/ui/screen_header.dart';
import '../home/home_state.dart';

/// Full-screen list of all bookmarks, grouped by host.
///
/// Tap a bookmark → opens [ExplorerScreen] navigated to that path.
/// Delete icon → removes the bookmark immediately.
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarkStoreProvider).valueOrNull ?? [];
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (bookmarks.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: const ScreenHeader('Bookmarks'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GradientBlobHero(icon: LucideIcons.bookmark, size: 120),
                const SizedBox(height: Spacing.sm),
                Text(
                  'No bookmarks yet. Long-press any file to bookmark it.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Group by hostId — preserve insertion order.
    final grouped = <String, List<Bookmark>>{};
    for (final b in bookmarks) {
      (grouped[b.hostId] ??= []).add(b);
    }

    // Build a hostId → Host map for display labels.
    final hostMap = <String, Host>{
      for (final h
          in ref.watch(hostStoreProvider).valueOrNull?.listHosts() ?? [])
        h.id: h,
    };

    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const ScreenHeader('Bookmarks')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          for (final group in grouped.entries) ...[
            SectionLabel(hostMap[group.key]?.label ?? group.key),
            for (final (i, b) in group.value.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: Spacing.md),
              AppearListItem(
                index: i,
                child: _BookmarkRow(
                  bookmark: b,
                  onOpen: () {
                    final host = hostMap[b.hostId];
                    if (host == null) return;
                    ref.read(activeHostProvider.notifier).state = ActiveHost(
                      host: host,
                      initialPath: b.remotePath,
                    );
                    ref.read(selectedTabIndexProvider.notifier).state = 1;
                    Navigator.of(context).pop();
                  },
                  onRemove:
                      () => ref
                          .read(bookmarkStoreProvider.notifier)
                          .removeBookmark(b.hostId, b.remotePath),
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
          ],
        ],
      ),
    );
  }
}

/// A single bookmark row — mockup's flat `.row` (blue tonal folder-ribbon
/// icon, title, mono full-path subtitle), not a card-wrapped [ListTile].
class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({
    required this.bookmark,
    required this.onOpen,
    required this.onRemove,
  });

  final Bookmark bookmark;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = bookmark.remotePath
        .split('/')
        .lastWhere((s) => s.isNotEmpty, orElse: () => bookmark.remotePath);
    // The mockup's bookmarks row has no visible delete affordance — removal
    // is long-press, same pattern as host_card.dart's "forget this device".
    return Pressable(
      onTap: onOpen,
      onLongPress: () => _confirmRemove(context, name, onRemove),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: Radii.smR,
              ),
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.bookmark,
                size: 18,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    bookmark.remotePath,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
            ),
            if (bookmark.tag != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Radii.stadiumR,
                ),
                child: Text(
                  bookmark.tag!,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    String name,
    VoidCallback onRemove,
  ) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(ctx.l10n.removeBookmarkTitle),
            description: Text(ctx.l10n.removeBookmarkConfirm(name)),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancelButton),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.removeButton),
              ),
            ],
          ),
    );
    if (confirmed == true) onRemove();
  }
}
