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

import '../../../core/theme/tokens.dart';
import '../../../core/ui/entry_leading.dart';
import '../../../core/ui/feedback.dart';
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
    builder: (_) => DestinationPickerSheet(
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

    final verb = isCopy ? 'Copy' : 'Move';
    final confirmLabel = isCopy ? 'Copy here' : 'Move here';
    final atOrigin = state.currentPath == originPath;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Radii.sheetTopR,
        ),
        child: Column(
          children: [
            _buildHeader(context, verb),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BreadcrumbBar(
                  pathStack: state.pathStack,
                  onNavigateTo: notifier.navigateTo,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(context, state, notifier, scrollController)),
            _buildFooter(context, ref, state, notifier, confirmLabel, atOrigin),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String verb) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.sm, Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$verb $itemCount item${itemCount == 1 ? '' : 's'} to…',
              style: Theme.of(context).textTheme.headlineSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, DestinationPickerState state,
      DestinationPickerNotifier notifier, ScrollController scrollController) {
    if (state.loading && state.folders.isEmpty) {
      return const ListingSkeleton();
    }
    if (state.error != null && state.folders.isEmpty) {
      return ErrorRetryCard(message: state.error!, onRetry: notifier.refresh);
    }
    if (state.folders.isEmpty) {
      return ListView(
        controller: scrollController,
        children: const [
          SizedBox(height: 120),
          EmptyFolderView(),
        ],
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
              child: state.loadingMore
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.square(dimension: 24),
            ),
          );
        }
        final folder = folders[i];
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: Radii.smR,
            ),
            alignment: Alignment.center,
            child: EntryLeading(entry: folder, size: 22),
          ),
          title: Text(folder.name, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded),
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
            Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () => _newFolder(context, ref, notifier),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('New folder'),
            ),
            const Spacer(),
            FilledButton(
              onPressed:
                  atOrigin ? null : () => Navigator.pop(context, state.currentPath),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newFolder(BuildContext context, WidgetRef ref,
      DestinationPickerNotifier notifier) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await notifier.createFolder(name);
      if (context.mounted) showSuccess(context, 'Created $name');
    } catch (e) {
      if (context.mounted) showError(context, "Couldn't create $name: $e");
    }
  }
}
