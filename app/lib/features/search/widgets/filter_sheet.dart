import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../search_logic.dart' show SearchMode;
import '../search_types.dart';

class FilterSheetResult {
  const FilterSheetResult({
    required this.sizePreset,
    required this.datePreset,
    required this.searchFromHere,
    required this.includeHidden,
    required this.searchMode,
  });

  final SizePreset sizePreset;
  final DatePreset datePreset;
  final bool searchFromHere;
  final bool includeHidden;
  final SearchMode searchMode;
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.sizePreset,
    required this.datePreset,
    required this.searchFromHere,
    required this.includeHidden,
    required this.currentPath,
    required this.searchMode,
  });

  final SizePreset sizePreset;
  final DatePreset datePreset;
  final bool searchFromHere;
  final bool includeHidden;
  final String currentPath;
  final SearchMode searchMode;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SizePreset _sizePreset = widget.sizePreset;
  late DatePreset _datePreset = widget.datePreset;
  late bool _searchFromHere = widget.searchFromHere;
  late bool _includeHidden = widget.includeHidden;
  late SearchMode _searchMode = widget.searchMode;

  void _apply() {
    Navigator.of(context).pop(
      FilterSheetResult(
        sizePreset: _sizePreset,
        datePreset: _datePreset,
        searchFromHere: _searchFromHere,
        includeHidden: _includeHidden,
        searchMode: _searchMode,
      ),
    );
  }

  void _reset() {
    setState(() {
      _sizePreset = SizePreset.any;
      _datePreset = DatePreset.any;
      _searchFromHere = true;
      _includeHidden = false;
      _searchMode = SearchMode.substring;
    });
  }

  String _modeLabel(SearchMode m) => switch (m) {
    SearchMode.substring => context.l10n.searchModeSubstring,
    SearchMode.glob => context.l10n.searchModeGlob,
    SearchMode.regex => context.l10n.searchModeRegex,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.searchFiltersTooltip,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _reset,
                  child: Text(context.l10n.resetButton),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.searchModeLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.xs,
              children: [
                for (final mode in SearchMode.values)
                  ChoiceChip(
                    label: Text(_modeLabel(mode)),
                    selected: _searchMode == mode,
                    onSelected: (_) => setState(() => _searchMode = mode),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.fileSize,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.xs,
              children: [
                for (final preset in SizePreset.values)
                  ChoiceChip(
                    label: Text(preset.localizedLabel(context)),
                    selected: _sizePreset == preset,
                    onSelected: (_) => setState(() => _sizePreset = preset),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.sortFieldDate,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.xs,
              children: [
                for (final preset in DatePreset.values)
                  ChoiceChip(
                    label: Text(preset.localizedLabel(context)),
                    selected: _datePreset == preset,
                    onSelected: (_) => setState(() => _datePreset = preset),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.searchScope,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _searchFromHere
                        ? context.l10n.searchingIn(widget.currentPath)
                        : context.l10n.searchingEverywhere,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(context.l10n.fromHere),
                Switch(
                  value: !_searchFromHere,
                  onChanged:
                      (everywhere) =>
                          setState(() => _searchFromHere = !everywhere),
                ),
                Text(context.l10n.everywhere),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.includeHiddenItems),
              subtitle: Text(context.l10n.includeHiddenSubtitle),
              value: _includeHidden,
              onChanged: (v) => setState(() => _includeHidden = v),
            ),
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                child: Text(context.l10n.applyButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
