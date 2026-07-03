/// Horizontal row of small tonal "pin" cards for the user's favorited
/// folders on a host — shown above the listing at the explorer root (and, for
/// Windows hosts, above the drive list) so frequently-used folders are one tap
/// away without opening the full favorites sheet.
library;

import 'package:flutter/material.dart';

import '../../../core/storage/favorites.dart';
import '../../../core/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A single row of [favorites], one tonal card per favorite (folder icon +
/// label, r16 corners). Tapping a card calls [onOpen]; long-pressing offers
/// to remove it via [onRemove].
///
/// Renders nothing if [favorites] is empty.
class FavoritesPinRow extends StatelessWidget {
  const FavoritesPinRow({
    super.key,
    required this.favorites,
    required this.onOpen,
    required this.onRemove,
  });

  final List<Favorite> favorites;
  final void Function(Favorite favorite) onOpen;
  final void Function(Favorite favorite) onRemove;

  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
        itemBuilder: (context, i) {
          final fav = favorites[i];
          return Material(
            color: scheme.secondaryContainer,
            borderRadius: Radii.cardR,
            child: InkWell(
              borderRadius: Radii.cardR,
              onTap: () => onOpen(fav),
              onLongPress: () => onRemove(fav),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.folder,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: Spacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        fav.label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
