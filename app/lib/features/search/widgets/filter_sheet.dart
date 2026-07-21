import 'package:flutter/material.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/ui/sheet_chrome.dart';
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

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xs),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.09,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: Radii.sheetTopR,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHead(title: context.l10n.searchFiltersTooltip),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(context.l10n.searchModeLabel),
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final mode in SearchMode.values)
                          _Chip(
                            label: _modeLabel(mode),
                            selected: _searchMode == mode,
                            onTap: () => setState(() => _searchMode = mode),
                          ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    _sectionLabel(context.l10n.fileSize),
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final preset in SizePreset.values)
                          _Chip(
                            label: preset.localizedLabel(context),
                            selected: _sizePreset == preset,
                            onTap: () => setState(() => _sizePreset = preset),
                          ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    _sectionLabel(context.l10n.sortFieldDate),
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final preset in DatePreset.values)
                          _Chip(
                            label: preset.localizedLabel(context),
                            selected: _datePreset == preset,
                            onTap: () => setState(() => _datePreset = preset),
                          ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    _sectionLabel(context.l10n.searchScope),
                    _ToggleRow(
                      title:
                          _searchFromHere
                              ? context.l10n.searchingIn(widget.currentPath)
                              : context.l10n.searchingEverywhere,
                      value: !_searchFromHere,
                      onChanged:
                          (everywhere) =>
                              setState(() => _searchFromHere = !everywhere),
                    ),
                    const SizedBox(height: Spacing.sm),
                    _ToggleRow(
                      title: context.l10n.includeHiddenItems,
                      subtitle: context.l10n.includeHiddenSubtitle,
                      value: _includeHidden,
                      onChanged: (v) => setState(() => _includeHidden = v),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _GhostButton(
                            label: context.l10n.resetButton,
                            onTap: _reset,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          flex: 2,
                          child: _PrimaryButton(
                            label: context.l10n.applyButton,
                            onTap: _apply,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mockup's `.chip`/`.chip.active` (pill, 1px border / filled primary).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Brand.seed : Colors.transparent,
          borderRadius: Radii.stadiumR,
          border:
              selected
                  ? null
                  : Border.all(color: scheme.outlineVariant, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A row pairing a title (+ optional subtitle) with the mockup's `.switch`
/// (42x25 pill track/thumb).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
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
          const SizedBox(width: Spacing.sm),
          _MockupSwitch(value: value),
        ],
      ),
    );
  }
}

/// The mockup's `.switch`: 42x25 pill track, 19x19 thumb.
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

/// The mockup's `.btn.btn-ghost`.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.smR,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The mockup's `.btn.btn-primary` (135° gradient + glow).
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: Brand.primaryGradient,
          borderRadius: Radii.smR,
          boxShadow: [
            BoxShadow(
              color: Brand.seed.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
