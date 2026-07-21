import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/storage/view_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/grouped_card.dart' show GroupedCard, SectionLabel;
import '../../../core/ui/pressable.dart';
import '../../../core/ui/sheet_chrome.dart';
import '../explorer_state.dart';

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
          SheetHead(title: context.l10n.viewOptionsTitle),
          Flexible(
            child: SingleChildScrollView(
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
                  Text(
                    context.l10n.layoutLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: Spacing.sm),
                  _SegmentedControl<bool>(
                    options: const [false, true],
                    labels: [context.l10n.listLabel, context.l10n.gridLabel],
                    value: state.gridView,
                    onChanged: (v) {
                      if (v != state.gridView) notifier.toggleView();
                    },
                  ),
                  const SizedBox(height: Spacing.lg),
                  // No mockup equivalent (the view-options sheet only shows
                  // Layout + Sort + Options) — kept as a real feature with the
                  // same segmented look as Layout above it for visual
                  // consistency, rather than the old raw SegmentedButton.
                  Text(
                    context.l10n.densityLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: Spacing.sm),
                  _SegmentedControl<EntryDensity>(
                    options: const [
                      EntryDensity.comfortable,
                      EntryDensity.compact,
                    ],
                    labels: [
                      context.l10n.comfortableLabel,
                      context.l10n.compactLabel,
                    ],
                    value: density,
                    onChanged:
                        (v) => ref
                            .read(settingsProvider.notifier)
                            .setAppDensity(v),
                  ),
                  const SizedBox(height: Spacing.lg),
                  SectionLabel(context.l10n.sortByLabel),
                  _SortList(state: state, notifier: notifier),
                  const SizedBox(height: Spacing.lg),
                  SectionLabel(context.l10n.optionsLabel),
                  GroupedCard(
                    padded: false,
                    children: [
                      _ToggleRow(
                        title: context.l10n.foldersFirstLabel,
                        // Directories are always partitioned before files in
                        // [_sortEntries] — there is no persisted preference to
                        // disable that, so this reflects real, always-on
                        // behavior rather than a toggle with nothing behind it.
                        value: true,
                        onChanged: null,
                        showDivider: true,
                      ),
                      _ToggleRow(
                        title: context.l10n.showHiddenItems,
                        subtitle:
                            state.hiddenCount > 0
                                ? context.l10n.nHiddenByVisibility(
                                  state.hiddenCount,
                                )
                                : null,
                        value: state.showHidden,
                        onChanged: (_) => notifier.toggleShowHidden(),
                        showDivider: false,
                      ),
                    ],
                  ),
                ],
              ),
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

/// The mockup's `.segmented`: `surface-2` track, 3px padding, active option
/// on `surface-3` + a subtle shadow. Generic over [T] so this one private
/// widget covers both the Layout and Density rows in this sheet.
class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.options,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  final List<T> options;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.smR,
      ),
      child: Row(
        children: [
          for (final (i, option) in options.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Pressable(
                onTap: () => onChanged(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color:
                        option == value ? scheme.surfaceContainerHighest : null,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow:
                        option == value
                            ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ]
                            : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          option == value
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The mockup's Sort-by `.list` of `.row`s: a flat title per [SortField],
/// with a direction arrow on the active field replacing the mockup's static
/// checkmark svg (so the sheet keeps showing which way it's actually sorted).
class _SortList extends StatelessWidget {
  const _SortList({required this.state, required this.notifier});

  final ExplorerState state;
  final ExplorerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = SortField.values;
    return Column(
      children: [
        for (final (i, field) in fields.indexed)
          Pressable(
            onTap: () {
              if (state.sort.field == field) {
                notifier.setSort(
                  state.sort.copyWith(ascending: !state.sort.ascending),
                );
              } else {
                notifier.setSort(SortOrder(field: field));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              decoration:
                  i == fields.length - 1
                      ? null
                      : BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _sortFieldLabel(context, field),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (state.sort.field == field)
                    Icon(
                      state.sort.ascending
                          ? LucideIcons.arrowUp
                          : LucideIcons.arrowDown,
                      size: 17,
                      color: scheme.primary,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A `.row-toggle` inside the Options `.card`: no leading icon (unlike
/// [SettingsTile]), just a title and a trailing `.switch`.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.showDivider,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _MockupSwitch(value: value),
        ],
      ),
    );
    return onChanged == null
        ? row
        : Pressable(onTap: () => onChanged!(!value), child: row);
  }
}

/// The mockup's `.switch`: 42x25 pill track, 19x19 thumb — this file's own
/// copy of `settings_tile.dart`'s private `_MockupSwitch` (zero-shared-
/// widget-reuse doctrine: each file owns its own literal-CSS rebuilds).
class _MockupSwitch extends StatelessWidget {
  const _MockupSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: MotionDuration.short,
      width: 42,
      height: 25,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
        border: Border.all(
          color: value ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
