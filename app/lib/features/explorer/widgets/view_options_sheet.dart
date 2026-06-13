import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../explorer_state.dart';

/// Modal bottom sheet holding every "how should this listing look" control:
/// list/grid mode, entry density, and sort (field + direction). Replaces the
/// old standalone `SortButton` — all three are persisted via
/// [viewPrefsProvider] and changes apply immediately.
class ViewOptionsSheet extends ConsumerWidget {
  const ViewOptionsSheet({
    super.key,
    required this.state,
    required this.notifier,
  });

  final ExplorerState state;
  final ExplorerNotifier notifier;

  /// Shows the sheet for the given explorer [state]/[notifier].
  static Future<void> show(
    BuildContext context, {
    required ExplorerState state,
    required ExplorerNotifier notifier,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTopR),
      builder: (_) => ViewOptionsSheet(state: state, notifier: notifier),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(viewPrefsProvider).valueOrNull ?? const ViewPrefs();
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.md, Spacing.md, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('View options', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.md),
            if (state.hiddenCount > 0) ...[
              _ShowHiddenTile(state: state, notifier: notifier),
              const SizedBox(height: Spacing.lg),
            ],
            Text('Layout', style: theme.textTheme.labelLarge),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('List'),
                  icon: Icon(Icons.view_list_rounded),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Grid'),
                  icon: Icon(Icons.grid_view_rounded),
                ),
              ],
              selected: {state.gridView},
              onSelectionChanged: (sel) {
                if (sel.first != state.gridView) notifier.toggleView();
              },
            ),
            const SizedBox(height: Spacing.lg),
            Text('Density', style: theme.textTheme.labelLarge),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<EntryDensity>(
              segments: const [
                ButtonSegment(
                  value: EntryDensity.comfortable,
                  label: Text('Comfortable'),
                  icon: Icon(Icons.density_medium_rounded),
                ),
                ButtonSegment(
                  value: EntryDensity.compact,
                  label: Text('Compact'),
                  icon: Icon(Icons.density_small_rounded),
                ),
              ],
              selected: {prefs.density},
              onSelectionChanged: (sel) =>
                  ref.read(viewPrefsProvider.notifier).setDensity(sel.first),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Sort by', style: theme.textTheme.labelLarge),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: SortField.values.map((field) {
                final selected = state.sort.field == field;
                return ChoiceChip(
                  label: Text(_sortFieldLabel(field)),
                  selected: selected,
                  onSelected: (_) {
                    if (selected) {
                      notifier.setSort(
                          state.sort.copyWith(ascending: !state.sort.ascending));
                    } else {
                      notifier.setSort(SortOrder(field: field));
                    }
                  },
                  avatar: selected
                      ? Icon(
                          state.sort.ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 18,
                        )
                      : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sentence-case label for [field] (e.g. "Date modified" for [SortField.date]).
String _sortFieldLabel(SortField field) => switch (field) {
      SortField.name => 'Name',
      SortField.size => 'Size',
      SortField.date => 'Date modified',
      SortField.type => 'Type',
    };

/// "Show hidden items" eye toggle, with a badge showing how many entries in
/// the current listing are filtered by file-visibility prefs
/// (`core/storage/visibility_prefs.dart`). Mirrors
/// [ExplorerState.showHidden] — same session-only override toggled by the
/// listing's [HiddenItemsFooter].
class _ShowHiddenTile extends StatelessWidget {
  const _ShowHiddenTile({required this.state, required this.notifier});

  final ExplorerState state;
  final ExplorerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Badge(
        label: Text('${state.hiddenCount}'),
        child: const Icon(Icons.visibility_outlined),
      ),
      title: const Text('Show hidden items'),
      subtitle: Text(
        '${state.hiddenCount} hidden by file visibility settings',
      ),
      value: state.showHidden,
      onChanged: (_) => notifier.toggleShowHidden(),
    );
  }
}
