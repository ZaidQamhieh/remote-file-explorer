import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.bookmarks_outlined),
                SizedBox(width: 8),
                Text('Favorites', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
          if (favs.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                'No favorites yet. Open a folder and tap the ☆ star to bookmark it.',
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
                      tooltip: 'Remove',
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
