import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/host.dart';
import '../../../core/storage/favorites.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/ui/sheet_chrome.dart';
import '../explorer_state.dart' show folderLabel;
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet listing the user's favorited folders for [host]. Tapping an
/// entry calls [onOpen] with its path; the star icon removes it. The
/// mockup's "Add current folder" button favorites [currentPath] (the
/// explorer's directory the sheet was opened from) via the same
/// `favoritesProvider.toggle` call `explorer_screen.dart`'s star action uses.
class FavoritesSheet extends ConsumerWidget {
  const FavoritesSheet({
    super.key,
    required this.host,
    required this.currentPath,
    required this.onOpen,
  });

  final Host host;
  final String currentPath;
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

    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHead(
            title: context.l10n.favoritesTitle,
            subtitle: context.l10n.favoritesSubtitle,
          ),
          if (favs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Text(
                context.l10n.noFavoritesYet,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in favs)
                      _FavoriteRow(
                        favorite: f,
                        onTap: () => onOpen(f.path),
                        onRemove:
                            () => ref
                                .read(favoritesProvider.notifier)
                                .remove(f.hostId, f.path),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.md,
            ),
            child: _GhostBlockButton(
              label: context.l10n.addCurrentFolderLabel(
                folderLabel(currentPath),
              ),
              icon: LucideIcons.plus,
              onTap: () {
                ref
                    .read(favoritesProvider.notifier)
                    .toggle(
                      Favorite(
                        hostId: host.id,
                        path: currentPath,
                        label: folderLabel(currentPath),
                      ),
                    );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The mockup's favorites `.row`: a drag-handle glyph (drag-to-reorder isn't
/// wired — no persisted ordering to reorder yet, so this row omits it rather
/// than fake the affordance), a blue `.row-icon`, title/host subtitle, and a
/// filled star `.iconbtn` that removes the favorite.
class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    required this.favorite,
    required this.onTap,
    required this.onRemove,
  });

  final Favorite favorite;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xs,
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
              child: Icon(LucideIcons.folder, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    favorite.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    favorite.path,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Pressable(
              onTap: onRemove,
              pressedScale: 0.92,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(LucideIcons.star, size: 16, color: Brand.amber),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block`: full-width, `surface-2`
/// background, 1px border, text then a trailing icon.
class _GhostBlockButton extends StatelessWidget {
  const _GhostBlockButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: Radii.smR,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, size: 16, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}
