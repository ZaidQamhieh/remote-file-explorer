import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/sheet_chrome.dart';
import '../explorer_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Modal bottom sheet holding every "how should this listing look" control:
/// list/grid mode, entry density, and sort (field + direction). Replaces the
/// old standalone `SortButton` — all three are persisted via
/// [viewPrefsProvider] and changes apply immediately.
///
/// The sheet **watches** the live [explorerProvider] for layout/sort/hidden
/// state rather than capturing a snapshot, so the selected Layout segment and
/// Sort chips move the instant the user taps them (otherwise they'd reflect the
/// frozen state from when the sheet opened).
class ViewOptionsSheet extends ConsumerWidget {
  const ViewOptionsSheet({super.key, required this.notifier});

  final ExplorerNotifier notifier;

  /// Shows the sheet for the given explorer [notifier].
  static Future<void> show(
    BuildContext context, {
    required ExplorerNotifier notifier,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTopR),
      builder: (_) => ViewOptionsSheet(notifier: notifier),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(explorerProvider(notifier.arg));
    final density =
        ref
            .watch(settingsProvider)
            .valueOrNull
            ?.resolveView(notifier.arg.hostId)
            .density ??
        EntryDensity.comfortable;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHero(
            badge: const Icon(LucideIcons.slidersHorizontal),
            title: context.l10n.viewOptionsTitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.hiddenCount > 0) ...[
                  _ShowHiddenTile(state: state, notifier: notifier),
                  const SizedBox(height: Spacing.lg),
                ],
                Text(
                  context.l10n.layoutLabel,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: Spacing.sm),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.l10n.listLabel),
                      icon: const Icon(LucideIcons.list),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.l10n.gridLabel),
                      icon: const Icon(LucideIcons.layoutGrid),
                    ),
                  ],
                  selected: {state.gridView},
                  onSelectionChanged: (sel) {
                    if (sel.first != state.gridView) notifier.toggleView();
                  },
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  context.l10n.densityLabel,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: Spacing.sm),
                SegmentedButton<EntryDensity>(
                  segments: [
                    ButtonSegment(
                      value: EntryDensity.comfortable,
                      label: Text(context.l10n.comfortableLabel),
                      icon: const Icon(LucideIcons.rows3),
                    ),
                    ButtonSegment(
                      value: EntryDensity.compact,
                      label: Text(context.l10n.compactLabel),
                      icon: const Icon(LucideIcons.rows4),
                    ),
                  ],
                  selected: {density},
                  onSelectionChanged:
                      (sel) => ref
                          .read(settingsProvider.notifier)
                          .setAppDensity(sel.first),
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  context.l10n.sortByLabel,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children:
                      SortField.values.map((field) {
                        final selected = state.sort.field == field;
                        return ChoiceChip(
                          label: Text(_sortFieldLabel(context, field)),
                          selected: selected,
                          onSelected: (_) {
                            if (selected) {
                              notifier.setSort(
                                state.sort.copyWith(
                                  ascending: !state.sort.ascending,
                                ),
                              );
                            } else {
                              notifier.setSort(SortOrder(field: field));
                            }
                          },
                          avatar:
                              selected
                                  ? Icon(
                                    state.sort.ascending
                                        ? LucideIcons.arrowUp
                                        : LucideIcons.arrowDown,
                                    size: 18,
                                  )
                                  : null,
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sentence-case label for [field] (e.g. "Date modified" for [SortField.date]).
String _sortFieldLabel(BuildContext context, SortField field) =>
    switch (field) {
      SortField.name => context.l10n.sortFieldName,
      SortField.size => context.l10n.sortFieldSize,
      SortField.date => context.l10n.sortFieldDate,
      SortField.type => context.l10n.sortFieldType,
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
        child: const Icon(LucideIcons.eye),
      ),
      title: Text(context.l10n.showHiddenItems),
      subtitle: Text(context.l10n.nHiddenByVisibility(state.hiddenCount)),
      value: state.showHidden,
      onChanged: (_) => notifier.toggleShowHidden(),
    );
  }
}
