import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/host.dart';
import '../../core/storage/bookmark_store.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
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
        appBar: AppBar(title: const Text('Bookmarks')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Text(
              'No bookmarks yet. Long-press any file to bookmark it.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
      appBar: AppBar(title: const Text('Bookmarks')),
      body: ListView(
        children: [
          for (final group in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xs,
              ),
              child: Text(
                hostMap[group.key]?.label ?? group.key,
                style: textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
            for (final b in group.value)
              ListTile(
                leading: const Icon(Icons.bookmark_rounded),
                title: Text(
                  b.remotePath
                      .split('/')
                      .lastWhere(
                        (s) => s.isNotEmpty,
                        orElse: () => b.remotePath,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(b.remotePath, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (b.tag != null)
                      Chip(
                        label: Text(b.tag!),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Remove bookmark',
                      onPressed:
                          () => ref
                              .read(bookmarkStoreProvider.notifier)
                              .removeBookmark(b.hostId, b.remotePath),
                    ),
                  ],
                ),
                onTap: () {
                  final host = hostMap[b.hostId];
                  if (host == null) return;
                  ref.read(activeHostProvider.notifier).state = ActiveHost(
                    host: host,
                    initialPath: b.remotePath,
                  );
                  ref.read(selectedTabIndexProvider.notifier).state = 1;
                  Navigator.of(context).pop();
                },
              ),
          ],
        ],
      ),
    );
  }
}
