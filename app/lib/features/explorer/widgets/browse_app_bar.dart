import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';
import '../explorer_state.dart';
import 'breadcrumb_bar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum OverflowAction {
  viewOptions,
  favorites,
  transfers,
  trash,
  recent,
  storageByType,
  dupFinder,
  commandPalette,
  pinOffline,
}

class BrowseAppBar extends StatelessWidget {
  const BrowseAppBar({
    super.key,
    required this.state,
    required this.isFav,
    required this.onBack,
    required this.onNavigateTo,
    required this.onMoveInto,
    required this.onSearch,
    required this.onToggleFavorite,
    required this.onOpenBookmarks,
    required this.onOverflow,
    this.isCurrentFolderPinned = false,
    this.onJumpTo,
  });

  final ExplorerState state;
  final bool isFav;
  final bool isCurrentFolderPinned;
  final VoidCallback onBack;
  final void Function(int index) onNavigateTo;
  final Future<void> Function(Entry dragged, String dest) onMoveInto;

  /// Navigates to an arbitrary absolute path (e.g. pasted from the
  /// clipboard). Forwarded to [BreadcrumbBar]'s overflow menu.
  final void Function(String path)? onJumpTo;
  final VoidCallback onSearch;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenBookmarks;
  final void Function(OverflowAction action) onOverflow;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      key: const ValueKey('browse_app_bar'),
      leading: state.atRoot ? null : BackButton(onPressed: onBack),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              folderLabel(state.currentPath),
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.19,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: Spacing.md,
            bottom: Spacing.xs,
          ),
          child: BreadcrumbBar(
            pathStack: state.pathStack,
            onNavigateTo: onNavigateTo,
            onMoveInto: onMoveInto,
            onJumpTo: onJumpTo,
          ),
        ),
      ),
      actions: [
        _IconBtn(
          icon: LucideIcons.search,
          tooltip: context.l10n.searchTooltip,
          onTap: onSearch,
        ),
        _IconBtn(
          icon: LucideIcons.bookmark,
          tooltip: 'Bookmarks',
          onTap: onOpenBookmarks,
        ),
        _IconBtn(
          icon: LucideIcons.star,
          tint: isFav ? Brand.amber : null,
          tooltip:
              isFav
                  ? context.l10n.removeFavoriteTooltip
                  : context.l10n.favoriteFolderTooltip,
          onTap: onToggleFavorite,
        ),
        PopupMenuButton<OverflowAction>(
          icon: const Icon(LucideIcons.moreVertical),
          tooltip: context.l10n.moreTooltip,
          onSelected: onOverflow,
          itemBuilder:
              (ctx) => [
                const PopupMenuItem(
                  value: OverflowAction.commandPalette,
                  child: ListTile(
                    leading: Icon(LucideIcons.terminal),
                    title: Text('Command Palette'),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.viewOptions,
                  child: ListTile(
                    leading: const Icon(LucideIcons.slidersHorizontal),
                    title: Text(ctx.l10n.viewOptionsTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.favorites,
                  child: ListTile(
                    leading: const Icon(LucideIcons.bookmark),
                    title: Text(ctx.l10n.favoritesTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.transfers,
                  child: ListTile(
                    leading: const Icon(LucideIcons.fileUp),
                    title: Text(ctx.l10n.transfersMenuItem),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.trash,
                  child: ListTile(
                    leading: const Icon(LucideIcons.trash2),
                    title: Text(ctx.l10n.trashTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.recent,
                  child: ListTile(
                    leading: const Icon(LucideIcons.history),
                    title: Text(ctx.l10n.recentTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.storageByType,
                  child: ListTile(
                    leading: const Icon(LucideIcons.pieChart),
                    title: Text(ctx.l10n.storageByTypeTitle),
                  ),
                ),
                const PopupMenuItem(
                  value: OverflowAction.dupFinder,
                  child: ListTile(
                    leading: Icon(LucideIcons.replace),
                    title: Text('Find Duplicates'),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.pinOffline,
                  child: ListTile(
                    leading: Icon(LucideIcons.pin),
                    title: Text(
                      isCurrentFolderPinned ? 'Unpin offline' : 'Pin offline',
                    ),
                  ),
                ),
              ],
        ),
      ],
    );
  }
}

/// The mockup's `.iconbtn`: 34x34, transparent by default, a 19px icon,
/// scale-.92 on press — replaces Material's `IconButton` ripple.
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.tint,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Non-null when this button carries the mockup's `.iconbtn.primary`-style
  /// tint (e.g. a starred/active state) instead of the default `--text-dim`.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Pressable(
      onTap: onTap,
      pressedScale: 0.92,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: 19, color: tint ?? scheme.onSurfaceVariant),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
