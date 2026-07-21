/// Folder-browser destination picker — a navigable mini-explorer bottom sheet
/// used by the Move/Copy actions in the selection bar, in place of the old
/// type-a-path destination dialog.
///
/// Lets the user browse into folders (breadcrumbs + tappable folder rows),
/// create a new folder, and confirm the currently-shown directory as the
/// Move/Copy destination. Returns the chosen absolute path via
/// `Navigator.pop(context, path)`, or `null` if cancelled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/gradient_button.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/ui/sheet_chrome.dart';
import '../../../core/ui/state_views.dart';
import '../destination_picker_state.dart';
import 'breadcrumb_bar.dart';

/// Shows the destination picker sheet for [itemCount] selected items being
/// `copy`d or `move`d, starting at [originPath] (the explorer's current
/// directory) on [hostId].
///
/// Returns the chosen destination directory path, or `null` if cancelled.
Future<String?> showDestinationPicker(
  BuildContext context, {
  required String hostId,
  required String originPath,
  required int itemCount,
  required bool isCopy,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTopR),
    builder:
        (_) => DestinationPickerSheet(
          hostId: hostId,
          originPath: originPath,
          itemCount: itemCount,
          isCopy: isCopy,
        ),
  );
}

class DestinationPickerSheet extends ConsumerWidget {
  const DestinationPickerSheet({
    super.key,
    required this.hostId,
    required this.originPath,
    required this.itemCount,
    required this.isCopy,
  });

  final String hostId;

  /// The explorer's current directory — the picker starts here, and the
  /// confirm button is disabled while the picker is showing this directory
  /// (moving/copying "into" the origin is a no-op).
  final String originPath;

  final int itemCount;
  final bool isCopy;

  DestinationPickerArg get _arg => (hostId: hostId, startPath: originPath);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(destinationPickerProvider(_arg));
    final notifier = ref.read(destinationPickerProvider(_arg).notifier);

    final headerText =
        isCopy
            ? context.l10n.copyItemsTo(itemCount)
            : context.l10n.moveItemsTo(itemCount);
    final confirmLabel =
        isCopy ? context.l10n.copyHereButton : context.l10n.moveHereButton;
    final atOrigin = state.currentPath == originPath;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder:
          (_, scrollController) => Material(
            color: scheme.surfaceContainerLow,
            borderRadius: Radii.sheetTopR,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SheetHead(title: headerText, subtitle: originPath),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BreadcrumbBar(
                      pathStack: state.pathStack,
                      onNavigateTo: notifier.navigateTo,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _buildBody(context, state, notifier, scrollController),
                ),
                _buildFooter(
                  context,
                  ref,
                  state,
                  notifier,
                  confirmLabel,
                  atOrigin,
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DestinationPickerState state,
    DestinationPickerNotifier notifier,
    ScrollController scrollController,
  ) {
    if (state.loading && state.folders.isEmpty) {
      return const ListingSkeleton();
    }
    if (state.error != null && state.folders.isEmpty) {
      return ErrorRetryCard(message: state.error!, onRetry: notifier.refresh);
    }
    if (state.folders.isEmpty) {
      return ListView(
        controller: scrollController,
        children: const [SizedBox(height: 120), EmptyFolderView()],
      );
    }

    final folders = state.folders;
    final showLoadMore = state.hasMore;
    final itemCount = folders.length + (showLoadMore ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (i >= folders.length) {
          notifier.loadMore();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(
              child:
                  state.loadingMore
                      ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const SizedBox.square(dimension: 24),
            ),
          );
        }
        final folder = folders[i];
        return _FolderRow(
          name: folder.name,
          showDivider: i < folders.length - 1,
          onTap: () => notifier.navigate(folder.path),
        );
      },
    );
  }

  Widget _buildFooter(
    BuildContext context,
    WidgetRef ref,
    DestinationPickerState state,
    DestinationPickerNotifier notifier,
    String confirmLabel,
    bool atOrigin,
  ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.sm,
        ),
        // Mockup stacks these two full-width `.btn-block` buttons, not a
        // side-by-side Row.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GhostBlockButton(
              label: context.l10n.newFolderButton,
              icon: LucideIcons.folderPlus,
              onTap: () => _newFolder(context, ref, notifier),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                onPressed:
                    atOrigin
                        ? null
                        : () => Navigator.pop(context, state.currentPath),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newFolder(
    BuildContext context,
    WidgetRef ref,
    DestinationPickerNotifier notifier,
  ) async {
    final ctrl = TextEditingController();
    final name = await showShadDialog<String>(
      context: context,
      builder:
          (ctx) => ShadDialog(
            title: Text(ctx.l10n.newFolderButton),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(ctx.l10n.createButton),
              ),
            ],
            child: ShadInput(
              controller: ctrl,
              autofocus: true,
              placeholder: Text(ctx.l10n.nameHint),
            ),
          ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await notifier.createFolder(name);
      if (context.mounted) showSuccess(context, context.l10n.createdName(name));
    } catch (e) {
      if (context.mounted) {
        showError(context, context.l10n.createFailed(name, humanizeError(e)));
      }
    }
  }
}

/// The mockup's folder `.row`: a blue `.row-icon`, title, trailing chevron —
/// no leading checkbox/selection affordance (this list is browse-only).
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.showDivider,
    required this.onTap,
  });

  final String name;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: 11,
        ),
        decoration:
            showDivider
                ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                )
                : null,
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
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: scheme.onSurfaceVariant,
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
