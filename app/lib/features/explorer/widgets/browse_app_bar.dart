import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../explorer_state.dart';
import 'breadcrumb_bar.dart';

enum OverflowAction { viewOptions, favorites, transfers, trash, storageByType }

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
    required this.onOverflow,
  });

  final ExplorerState state;
  final bool isFav;
  final VoidCallback onBack;
  final void Function(int index) onNavigateTo;
  final Future<void> Function(Entry dragged, String dest) onMoveInto;
  final VoidCallback onSearch;
  final VoidCallback onToggleFavorite;
  final void Function(OverflowAction action) onOverflow;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      key: const ValueKey('browse_app_bar'),
      leading: state.atRoot ? null : BackButton(onPressed: onBack),
      title: Text(
        folderLabel(state.currentPath),
        style: Theme.of(context).textTheme.titleLarge,
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
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: context.l10n.searchTooltip,
          onPressed: onSearch,
        ),
        IconButton(
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded),
          color: isFav ? Colors.amber : null,
          tooltip:
              isFav
                  ? context.l10n.removeFavoriteTooltip
                  : context.l10n.favoriteFolderTooltip,
          onPressed: onToggleFavorite,
        ),
        PopupMenuButton<OverflowAction>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: context.l10n.moreTooltip,
          onSelected: onOverflow,
          itemBuilder:
              (ctx) => [
                PopupMenuItem(
                  value: OverflowAction.viewOptions,
                  child: ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(ctx.l10n.viewOptionsTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.favorites,
                  child: ListTile(
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: Text(ctx.l10n.favoritesTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.transfers,
                  child: ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: Text(ctx.l10n.transfersMenuItem),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.trash,
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: Text(ctx.l10n.trashTitle),
                  ),
                ),
                PopupMenuItem(
                  value: OverflowAction.storageByType,
                  child: ListTile(
                    leading: const Icon(Icons.pie_chart_outline_rounded),
                    title: Text(ctx.l10n.storageByTypeTitle),
                  ),
                ),
              ],
        ),
      ],
    );
  }
}
