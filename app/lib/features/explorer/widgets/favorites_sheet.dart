import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/host.dart';
import '../../../core/storage/favorites.dart';

/// Bottom sheet listing the user's favorited folders for [host]. Tapping an
/// entry calls [onOpen] with its path; the star icon removes it.
class FavoritesSheet extends ConsumerWidget {
  const FavoritesSheet({super.key, required this.host, required this.onOpen});

  final Host host;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs =
        ref
            .watch(favoritesProvider)
            .valueOrNull
            ?.where((f) => f.hostId == host.id)
            .toList() ??
        const [];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.bookmarks_outlined),
                const SizedBox(width: 8),
                Text(
                  context.l10n.favoritesTitle,
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
          if (favs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                context.l10n.noFavoritesYet,
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: favs.length,
                itemBuilder: (ctx, i) {
                  final f = favs[i];
                  return ListTile(
                    leading: const Icon(
                      Icons.folder_special,
                      color: Colors.amber,
                    ),
                    title: Text(f.label),
                    subtitle: Text(f.path, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.star, color: Colors.amber),
                      tooltip: context.l10n.removeTooltip,
                      onPressed:
                          () => ref
                              .read(favoritesProvider.notifier)
                              .remove(f.hostId, f.path),
                    ),
                    onTap: () => onOpen(f.path),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
